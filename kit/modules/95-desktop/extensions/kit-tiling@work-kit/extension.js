// kit-tiling: Omarchy-like automatic tiling for GNOME 46-50 (work-kit module 95-desktop).
// Per workspace and monitor: one window fills the work area, two split it, three or more make a
// main area and a stack (tileRects in layout.js). No gaps: a thin border (border-width, default 2 px)
// inside every tile shows where a window ends, the focused one in the accent colour. Keys (set by install.sh): focus and swap
// by direction, float, next layout (main left / main on top), monocle, main area narrower / wider.
// Windows that are dialogs, fixed-size, minimized, maximized or full screen are left alone. A window
// that stays larger than its tile floats centred at its own size (shouldFloat): a new one within
// about 1.5 s, any other after the retries; a late answer of the client does not move it off centre.
// Borders between tiles can be dragged with the mouse (or resized with the keyboard): the other
// windows follow while dragging; the split is kept per workspace and monitor until logout.
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import Shell from 'gi://Shell';
import St from 'gi://St';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import {tileRects, neighbour, resizeSplit, nextAsk, shouldFloat, isTerminal, centred, lateFit, NEW_MS, FAST_MS, OFF_BY} from './layout.js';

const DIRS = ['left', 'right', 'up', 'down'];
const LATE_MS = 20000;
// grab ops that resize: an edge direction, or Alt+F8 before the first arrow key (moves have neither)
const G = Meta.GrabOp;
const RESIZE_BITS = ((G.RESIZING_N | G.RESIZING_S | G.RESIZING_E | G.RESIZING_W) & ~G.WINDOW_BASE) |
    (G.KEYBOARD_RESIZING_UNKNOWN & ~G.KEYBOARD_MOVING);

// "workspace:monitor" -> {ratio, weights}: splits changed by dragging or Super+- / Super+= (German: Super++). In memory
// only, until logout (owner decision 2026-09-26, like Hyprland). Kept at module level so the screen
// lock, which disables and enables the extension, does not reset them.
const splits = new Map();

export default class Work kitTiling extends Extension {
    enable() {
        this._settings = this.getSettings();
        this._mutter = new Gio.Settings({schema_id: 'org.gnome.mutter'});
        this._order = [];            // tracked windows in tiling order (first = main)
        this._floating = new Set();
        this._above = new Set();     // floating windows this tiler put above the tiles (make_above)
        this._auto = new Map();      // window -> {tile, at, fast, area, centre, moves}: floating because it stayed larger than its tile
        this._born = new Map();      // window -> time of its first frame (ms), for new windows only
        this._fitted = new Set();    // windows that had their tile size at least once
        this._pinned = new Set();    // tiled by hand (Super+T): never floated automatically
        this._wide = new Set();      // "workspace:monitor" keys using the "main on top" layout
        this._monocle = new Set();   // "workspace:monitor" keys in monocle mode
        this._winSignals = new Map();
        this._actorSignals = new Map(); // window -> [actor, notify::allocation handler]
        this._signals = [];
        this._sources = new Set();
        this._relayoutId = 0;
        this._grab = null;           // the tiled window being resized or moved with the mouse or keys
        this._asked = new Map();     // window -> tile size last asked for by _place (nextAsk)
        this._mins = new Map();      // window -> smallest {width, height} it answered with (learned)
        this._borders = new Map();   // window -> border actor (St.Widget above the window actor)
        this._borderId = 0;
        this._checkId = 0;           // pending look at sizes asked for (nextAsk)
        this._checkDue = 0;          // when it runs (ms)

        const on = (obj, name, fn) => this._signals.push([obj, obj.connect(name, fn)]);
        on(global.display, 'window-created', (_d, w) => this._track(w, true));
        on(global.display, 'workareas-changed', () => this._queue());
        // the window's monitor is updated after this signal: tile again a moment later
        on(global.display, 'window-entered-monitor', () => {
            this._queue();
            this._later(300);
        });
        on(global.display, 'grab-op-begin', (_d, w, op) => this._grabBegin(w, op));
        on(global.display, 'grab-op-end', (_d, w) => this._grabEnd(w));
        on(global.workspace_manager, 'active-workspace-changed', () => this._queue());
        on(Main.layoutManager, 'monitors-changed', () => this._queue());
        on(this._settings, 'changed::main-ratio', () => this._queue());
        on(this._mutter, 'changed::workspaces-only-on-primary', () => this._queue());
        on(this._settings, 'changed::border-width', () => this._queue());
        on(this._settings, 'changed::border-color', () => this._bordersSoon());
        on(this._settings, 'changed::inactive-border-color', () => this._bordersSoon());
        on(global.display, 'notify::focus-window', () => this._bordersSoon());
        on(global.display, 'restacked', () => this._bordersSoon());

        global.get_window_actors().map(a => a.meta_window)
            .sort((a, b) => a.get_stable_sequence() - b.get_stable_sequence())
            .forEach(w => this._track(w, false));

        const keys = {
            'untile-window': () => this._toggleFloat(),
            'cycle-layouts': () => this._toggleSet(this._wide),
            'span-window-all-tiles': () => this._toggleSet(this._monocle),
            'shrink-main': () => this._ratio(-0.05),
            'grow-main': () => this._ratio(0.05),
        };
        for (const d of DIRS) {
            keys[`focus-window-${d}`] = () => this._focus(d);
            keys[`move-window-${d}`] = () => this._swap(d);
            keys[`window-to-monitor-${d}`] = () => this._toMonitor(global.display.focus_window, d);
        }
        this._keys = Object.keys(keys);
        for (const [name, fn] of Object.entries(keys))
            Main.wm.addKeybinding(name, this._settings, Meta.KeyBindingFlags.NONE, Shell.ActionMode.NORMAL, fn);
        this._queue();
    }

    disable() {
        for (const name of this._keys ?? [])
            Main.wm.removeKeybinding(name);
        for (const [obj, id] of this._signals)
            obj.disconnect(id);
        for (const [w, ids] of this._winSignals)
            ids.forEach(id => w.disconnect(id));
        for (const w of [...this._actorSignals.keys()])
            this._dropActor(w);
        for (const id of this._sources)
            GLib.source_remove(id);
        if (this._grab?.sizeId)
            this._grab.w.disconnect(this._grab.sizeId);
        if (this._relayoutId)
            GLib.source_remove(this._relayoutId);
        if (this._borderId)
            GLib.source_remove(this._borderId);
        if (this._checkId)
            GLib.source_remove(this._checkId);
        this._checkId = 0;
        for (const b of this._borders?.values() ?? [])
            b.destroy();
        for (const w of this._above ?? []) {
            try {
                if (w.is_above())
                    w.unmake_above();
            } catch (e) {
                // the window is already gone
            }
        }
        this._above = null;
        this._borders = null;
        this._borderId = 0;
        this._signals = this._winSignals = this._actorSignals = this._sources = this._order = this._floating = null;
        this._auto = this._pinned = this._born = this._fitted = null;
        this._wide = this._monocle = this._settings = this._mutter = this._keys = this._fresh = this._moving = null;
        this._relayoutId = 0;
        this._grab = this._asked = this._mins = null;
    }

    // ---- window tracking ---------------------------------------------------------------------
    _track(w, created) {
        if (!w || this._winSignals.has(w) || w.get_window_type() !== Meta.WindowType.NORMAL)
            return;
        const ids = [];
        const on = (name, fn) => {
            try {
                ids.push(w.connect(name, fn));
            } catch (e) { /* property missing in this GNOME version */ }
        };
        on('unmanaged', () => this._untrack(w));
        // a client that resizes itself (GNOME Terminal adding an info bar grew past its tile on
        // GNOME 50) goes back into its tile; one that keeps its size (character grid) sends no signal
        on('size-changed', () => {
            this._lateFit(w);
            this._recentre(w);
            if (this._grab?.w !== w)
                this._queue();
            this._bordersSoon();
        });
        on('position-changed', () => {
            this._recentre(w);
            this._bordersSoon();
        });
        // a window that becomes a dialog of another one floats and frees its tile
        on('notify::transient-for', () => this._queue());
        on('workspace-changed', () => {
            this._queue();
            this._later(300);
        });
        // on-all-workspaces: a window leaving a shared monitor loses it only later (GNOME 46 VM)
        for (const p of ['minimized', 'fullscreen', 'maximized-horizontally', 'maximized-vertically', 'on-all-workspaces']) {
            on(`notify::${p}`, () => {
                this._unmaxFresh(w);
                this._queue();
            });
        }
        // the border follows every move and resize of the window actor, also one the client or
        // mutter makes without a size or position signal; a client off its tile that draws a new size
        // without reporting it (Electron) is looked at again (nextAsk)
        const actor = w.get_compositor_private();
        if (actor) {
            this._actorSignals.set(w, [actor, actor.connect('notify::allocation', () => {
                this._bordersSoon();
                const a = this._asked?.get(w), f = w.get_frame_rect();
                if (a && (f.width !== a.width || f.height !== a.height) && this._grab?.w !== w)
                    this._queue();
            })]);
        }
        this._winSignals.set(w, ids);
        this._order.push(w);
        if (created) {
            // Wayland clients pick their size with the first frame: tile again once it is there.
            // A maximize in the first 2 s is mutter's auto-maximize or the app's saved state, not a
            // user action: undo it so the window tiles
            this._fresh ??= new Map();
            this._fresh.set(w, GLib.get_monotonic_time());
            const actor = w.get_compositor_private();
            if (actor) {
                const id = actor.connect('first-frame', () => {
                    actor.disconnect(id);
                    this._born?.set(w, GLib.get_monotonic_time() / 1000);
                    this._unmaxFresh(w);
                    this._queue();
                    this._later(FAST_MS + 50); // a new window too large for its tile floats fast
                });
            }
            this._later(150);
            this._later(600);
        }
        this._queue();
    }

    _unmaxFresh(w) {
        const t = this._fresh?.get(w);
        if (t === undefined || GLib.get_monotonic_time() - t > 2000000 || !this._maximized(w))
            return;
        if (w.get_maximized)
            w.unmaximize(Meta.MaximizeFlags.BOTH);
        else
            w.unmaximize();
    }

    _untrack(w) {
        if (this._grab?.w === w)
            this._grabDone();
        this._fresh?.delete(w);
        this._moving?.delete(w);
        this._asked?.delete(w);
        this._mins?.delete(w);
        (this._winSignals.get(w) ?? []).forEach(id => w.disconnect(id));
        this._winSignals.delete(w);
        this._dropActor(w);
        this._borders?.get(w)?.destroy();
        this._borders?.delete(w);
        this._floating.delete(w);
        this._above.delete(w);
        this._auto.delete(w);
        this._pinned.delete(w);
        this._born.delete(w);
        this._fitted.delete(w);
        this._order = this._order.filter(o => o !== w);
        this._queue();
    }

    _dropActor(w) {
        const [actor, id] = this._actorSignals.get(w) ?? [];
        this._actorSignals.delete(w);
        try {
            actor?.disconnect(id);
        } catch (e) { /* actor already destroyed */ }
    }

    _maximized(w) {
        return Boolean(w.maximizedHorizontally || w.maximizedVertically ||
            w.maximized_horizontally || w.maximized_vertically);
    }

    _tileable(w) {
        if (!w || this._floating.has(w) || w.minimized || w.is_fullscreen() || this._maximized(w))
            return false;
        if (w.get_transient_for() || w.is_attached_dialog() || w.is_skip_taskbar() || !w.allows_resize())
            return false;
        const cls = w.get_wm_class() ?? '';
        return !this._settings.get_strv('float-classes').includes(cls);
    }

    // the monitor a window belongs to: a move the tiler asked for counts at once (mutter reports the
    // new monitor only after the client answered; GNOME 46 moved the window back meanwhile)
    _monitor(w) {
        const t = this._moving?.get(w);
        if (t) {
            if (w.get_monitor() === t.mon || GLib.get_monotonic_time() - t.since > 3000000) {
                this._moving.delete(w);
                this._later(500);
            }
            else
                return t.mon;
        }
        return w.get_monitor();
    }

    _key(ws, mon) {
        return this._shared(mon) ? `all:${mon}` : `${ws.index()}:${mon}`;
    }

    // With GNOME's workspaces-only-on-primary (the default) every window on another monitor is on all
    // workspaces: those monitors have one set of windows. Elsewhere a sticky window is left alone.
    _shared(mon) {
        return mon !== global.display.get_primary_monitor() && this._mutter.get_boolean('workspaces-only-on-primary');
    }

    // mons: window -> monitor, taken once per relayout (a window just placed must not count for a
    // second monitor in the same pass while its new size is still pending)
    _tiled(ws, mon, mons = null) {
        const shared = this._shared(mon);
        const active = global.workspace_manager.get_active_workspace();
        return this._order.filter(w => {
            if (!this._tileable(w) || (mons?.get(w) ?? this._monitor(w)) !== mon)
                return false;
            if (shared)
                return true;
            if (w.is_on_all_workspaces()) // coming from a shared monitor: it lands on the active workspace
                return Boolean(this._moving?.has(w)) && ws === active;
            return w.get_workspace() === ws;
        });
    }

    // ---- layout ------------------------------------------------------------------------------
    _later(ms) {
        const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
            this._sources?.delete(id);
            this._queue();
            return GLib.SOURCE_REMOVE;
        });
        this._sources.add(id);
    }

    // Relayout and borders run at default priority, not as low-priority idle: on a real display that
    // redraws while clients resize (virtio-gpu VM, GNOME 46) low-priority idle callbacks waited up to
    // 11 s, so windows kept their old tiles and borders for that long (F34, measured)
    _queue() {
        if (this._relayoutId || !this._order)
            return;
        this._relayoutId = GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            this._relayoutId = 0;
            this._relayout();
            return GLib.SOURCE_REMOVE;
        });
    }

    _mode(key) {
        return this._monocle.has(key) ? 'monocle' : this._wide.has(key) ? 'wide' : 'tall';
    }

    // the split of a workspace and monitor; main-ratio is the default for one never resized
    _split(key) {
        return splits.get(key) ?? {ratio: this._settings.get_double('main-ratio'), weights: []};
    }

    _rects(ws, mon, n) {
        const key = this._key(ws, mon);
        const {ratio, weights} = this._split(key);
        return tileRects(ws.get_work_area_for_monitor(mon), n, this._mode(key), ratio, weights);
    }

    _relayout() {
        const nMon = global.display.get_n_monitors();
        const wm = global.workspace_manager;
        const mons = new Map(this._order.map(w => [w, this._monitor(w)]));
        for (let i = 0; i < wm.get_n_workspaces(); i++) {
            const ws = wm.get_workspace_by_index(i);
            for (let mon = 0; mon < nMon; mon++) {
                if (this._shared(mon) && ws !== wm.get_active_workspace())
                    continue;
                let wins = this._tiled(ws, mon, mons);
                let rects = this._rects(ws, mon, wins.length);
                const off = wins.filter((w, k) => this._floatsOff(w, this._inset(rects[k])));
                if (off.length) { // the others tile without them at once
                    off.forEach(w => this._autoFloat(w, ws, mon, this._inset(rects[wins.indexOf(w)])));
                    wins = wins.filter(w => !off.includes(w));
                    rects = this._rects(ws, mon, wins.length);
                }
                wins.forEach((w, k) => this._place(w, this._inset(rects[k])));
            }
        }
        this._updateBorders();
    }

    // ---- borders -------------------------------------------------------------------------------
    _bw() {
        return Math.max(0, Math.min(8, this._settings.get_int('border-width')));
    }

    // a window sits inside its tile, border-width away from every edge; the border fills that strip
    _inset(r) {
        const b = this._bw();
        return {x: r.x + b, y: r.y + b, width: r.width - 2 * b, height: r.height - 2 * b};
    }

    _outset(r) {
        const b = this._bw();
        return {x: r.x - b, y: r.y - b, width: r.width + 2 * b, height: r.height + 2 * b};
    }

    _bordersSoon() {
        if (this._borderId || !this._borders)
            return;
        this._borderId = GLib.idle_add(GLib.PRIORITY_DEFAULT, () => {
            this._borderId = 0;
            this._updateBorders();
            return GLib.SOURCE_REMOVE;
        });
    }

    // One border actor per tiled window (and the focused floating one, and every one floated because it
    // did not fit its tile), kept just above the window's
    // actor, so a window on top covers the borders below it (monocle, floating windows).
    _updateBorders() {
        if (!this._borders)
            return;
        const bw = this._bw();
        const focus = global.display.focus_window;
        const active = global.workspace_manager.get_active_workspace();
        const colour = this._settings.get_string('border-color');
        const inactive = this._settings.get_string('inactive-border-color');
        const keep = new Set();
        for (const w of bw > 0 ? this._order : []) {
            if (w.minimized || w.is_fullscreen() || this._maximized(w) || !w.located_on_workspace(active))
                continue;
            if (!this._tileable(w) && w !== focus && !this._auto.has(w))
                continue;
            const actor = w.get_compositor_private();
            if (!actor || actor.get_parent() !== global.window_group)
                continue;
            let b = this._borders.get(w);
            if (!b) {
                b = new St.Widget({reactive: false});
                global.window_group.add_child(b);
                this._borders.set(w, b);
            }
            const f = this._outset(w.get_frame_rect());
            b.set_position(f.x, f.y);
            b.set_size(f.width, f.height);
            b.style = `border: ${bw}px solid ${w === focus ? colour : inactive};`;
            b.visible = actor.visible;
            global.window_group.set_child_above_sibling(b, actor);
            keep.add(w);
        }
        for (const [w, b] of this._borders) {
            if (!keep.has(w)) {
                b.destroy();
                this._borders.delete(w);
            }
        }
    }

    _place(w, r) {
        if (this._grab?.w === w) // the user is dragging it: the others follow, it stays
            return;
        const f = w.get_frame_rect();
        // a client that does not take its size is asked again (nextAsk in layout.js); one that fits
        // is forgotten
        const next = nextAsk(f, r, this._asked.get(w), GLib.get_monotonic_time() / 1000, w.get_buffer_rect());
        if (next.asked) {
            this._asked.set(w, next.asked);
        } else {
            this._asked.delete(w);
            this._fitted.add(w);
        }
        if (next.check)
            this._checkIn(next.check);
        // move first: a combined move and resize lands only when the client commits a new size, and a
        // terminal that snaps to its character grid (GNOME Terminal) may keep its size and never move
        if (f.x !== r.x || f.y !== r.y)
            w.move_frame(false, r.x, r.y);
        if (next.size)
            w.move_resize_frame(false, r.x, r.y, next.size.width, next.size.height);
    }

    // a tiled window still larger than its tile r: a new one soon, any other after its retries
    // (shouldFloat, owner decision Q4)
    _floatsOff(w, r) {
        if (this._grab?.w === w)
            return false;
        const now = GLib.get_monotonic_time() / 1000, f = w.get_frame_rect(), asked = this._asked.get(w);
        const born = this._born.get(w) ?? null, fitted = this._fitted.has(w);
        const terminal = isTerminal(w.get_wm_class(), w.get_gtk_application_id?.(), w.get_sandboxed_app_id?.());
        const opts = {terminal, pinned: this._pinned.has(w), born, fitted};
        if (shouldFloat(f, r, asked, now, w.get_buffer_rect(), opts))
            return true;
        // a new window too large for its tile: look again when the fast path is due
        if (born !== null && !fitted && now - born < NEW_MS && asked && !terminal && !opts.pinned &&
            (f.width > r.width + OFF_BY || f.height > r.height + OFF_BY))
            this._checkIn(Math.max(50, FAST_MS - (now - Math.max(born, asked.at ?? asked.since))));
        return false;
    }

    // floats w centred on its monitor at its own size, above the others, with the kit border
    _autoFloat(w, ws, mon, r) {
        const now = GLib.get_monotonic_time() / 1000, born = this._born.get(w);
        this._float(w);
        const area = ws.get_work_area_for_monitor(mon);
        this._auto.set(w, {tile: r, at: now, fast: born !== undefined && !this._fitted.has(w) && now - born < NEW_MS,
            area, centre: true, moves: 0});
        this._asked.delete(w);
        const p = centred(area, w.get_frame_rect());
        w.move_frame(false, p.x, p.y);
        w.raise();
    }

    // A client that answers the tile request only after it was floated gets the tile position mutter
    // kept for that request, pushed on screen (Sessions, fast path on the GNOME 46 VM: 536,260 instead
    // of centred): an auto-floated window is centred again after every move or resize of its own, until
    // the user grabs or moves it, for LATE_MS after the float (at most 20 moves)
    _recentre(w) {
        const a = this._auto?.get(w);
        if (!a?.centre || this._grab?.w === w)
            return;
        if (GLib.get_monotonic_time() / 1000 - a.at > LATE_MS || a.moves >= 20) {
            a.centre = false;
            return;
        }
        const f = w.get_frame_rect(), p = centred(a.area, f);
        if (f.x === p.x && f.y === p.y)
            return;
        a.moves++;
        w.move_frame(false, p.x, p.y);
    }

    // a window floated on the fast path that takes its tile size after all (a slow client answering
    // late, on an emulated VM up to 18 s) goes back into the tiles; checked for LATE_MS after the float
    _lateFit(w) {
        const a = this._auto?.get(w);
        if (!a?.fast || GLib.get_monotonic_time() / 1000 - a.at > LATE_MS || !lateFit(w.get_frame_rect(), a.tile))
            return;
        this._auto.delete(w);
        this._unfloat(w);
        this._fitted.add(w);
        this._queue();
    }

    // one timer for all windows waiting for an answer: it runs at the earliest time one of them asked for
    _checkIn(ms) {
        const due = GLib.get_monotonic_time() / 1000 + ms;
        if (this._checkId && this._checkDue <= due)
            return;
        if (this._checkId)
            GLib.source_remove(this._checkId);
        this._checkDue = due;
        this._checkId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, Math.ceil(ms) + 50, () => {
            this._checkId = 0;
            this._queue();
            return GLib.SOURCE_REMOVE;
        });
    }

    // ---- actions -----------------------------------------------------------------------------
    _focus(dir) {
        const ws = global.workspace_manager.get_active_workspace();
        const wins = global.display.get_tab_list(Meta.TabList.NORMAL, ws).filter(w => !w.minimized);
        const cur = global.display.focus_window;
        if (!cur || !wins.includes(cur)) {
            wins[0]?.activate(global.get_current_time());
            return;
        }
        const rects = wins.map(w => w.get_frame_rect());
        const i = neighbour(rects, wins.indexOf(cur), dir);
        if (i >= 0)
            wins[i].activate(global.get_current_time());
    }

    _swap(dir) {
        const w = global.display.focus_window;
        if (!w || !this._winSignals.has(w))
            return;
        if (this._tileable(w)) {
            const wins = this._tiled(w.get_workspace(), this._monitor(w));
            const i = neighbour(wins.map(o => o.get_frame_rect()), wins.indexOf(w), dir);
            if (i >= 0) {
                const a = this._order.indexOf(w), b = this._order.indexOf(wins[i]);
                [this._order[a], this._order[b]] = [this._order[b], this._order[a]];
                this._queue();
                this._later(400);
                return;
            }
        }
        // nothing there on this monitor: move the window to the monitor in that direction
        this._toMonitor(w, dir);
    }

    // The tiler places the window on the other monitor itself: mutter 46 moved a window at the
    // left edge of a monitor to x = 0 of the same monitor instead (move_to_monitor, GNOME 46 VM)
    _toMonitor(w, dir) {
        if (!w || !this._winSignals.has(w))
            return;
        const md = {left: Meta.DisplayDirection.LEFT, right: Meta.DisplayDirection.RIGHT,
            up: Meta.DisplayDirection.UP, down: Meta.DisplayDirection.DOWN}[dir];
        const target = global.display.get_monitor_neighbor_index(this._monitor(w), md);
        if (target >= 0) {
            const a = this._auto.get(w);
            if (a)
                a.centre = false;
            this._moving ??= new Map();
            this._moving.set(w, {mon: target, since: GLib.get_monotonic_time()});
            if (!this._tileable(w))
                w.move_to_monitor(target);
            this._queue();
            this._later(300);
        }
    }

    // A floating window stays above the tiles, as on Omarchy (Hyprland): without this, focusing a tiled
    // window raised it over the auto-floated First Steps window of the Agent Workbench (GNOME 46 VM,
    // 28.09.). Only windows this tiler floated get it, and only when they were not above already, so
    // a user's own "always on top" (Super+O) is left alone.
    _float(w) {
        this._floating.add(w);
        if (!w.is_above()) {
            w.make_above();
            this._above.add(w);
        }
    }

    _unfloat(w) {
        this._floating.delete(w);
        if (this._above.delete(w) && w.is_above())
            w.unmake_above();
    }

    _toggleFloat() {
        const w = global.display.focus_window;
        if (!w || !this._winSignals.has(w))
            return;
        if (this._floating.has(w)) {
            this._unfloat(w);
            this._auto.delete(w);
            this._pinned.add(w); // tiled by hand: not floated automatically again
        } else {
            this._float(w);
            const a = w.get_work_area_current_monitor();
            const width = Math.round(a.width * 0.6), height = Math.round(a.height * 0.7);
            w.move_resize_frame(false, a.x + Math.round((a.width - width) / 2),
                a.y + Math.round((a.height - height) / 2), width, height);
            w.raise();
        }
        this._queue();
        this._later(400);
    }

    _toggleSet(set) {
        const w = global.display.focus_window;
        const ws = global.workspace_manager.get_active_workspace();
        const key = this._key(ws, w ? this._monitor(w) : global.display.get_current_monitor());
        if (set.has(key))
            set.delete(key);
        else
            set.add(key);
        this._queue();
        this._later(400);
        if (w && set === this._monocle)
            w.raise();
    }

    // Super+- / Super+= (German: Super++): the main area of the focused window's workspace and monitor
    _ratio(delta) {
        const w = global.display.focus_window;
        const ws = global.workspace_manager.get_active_workspace();
        const key = this._key(ws, w ? this._monitor(w) : global.display.get_current_monitor());
        const split = this._split(key);
        const r = Math.min(0.8, Math.max(0.2, split.ratio + delta));
        splits.set(key, {...split, ratio: Math.round(r * 100) / 100});
        this._queue();
    }

    // ---- mouse and keyboard resize ---------------------------------------------------------------
    // A client still larger than asked a moment after the request has reached its minimum size
    // (Ptyxis: 294 px high): remember it, so a dragged border stops there instead of making windows
    // overlap. A few pixels more are a character grid (GNOME Terminal), not a minimum. A size below a
    // remembered minimum proves it wrong. Returns true when a minimum changed.
    _learnMin(w) {
        const a = this._asked.get(w);
        const f = w.get_frame_rect();
        const old = this._mins.get(w) ?? {width: 0, height: 0};
        const m = {...old};
        const settled = a && GLib.get_monotonic_time() / 1000 - a.since > 150;
        for (const d of ['width', 'height']) {
            if (m[d] && f[d] < m[d])
                m[d] = 0;
            if (settled && f[d] > a[d] + 8)
                m[d] = f[d];
        }
        this._mins.set(w, m);
        return m.width !== old.width || m.height !== old.height;
    }

    // neighbours of a drag that just ended may still refuse their new size: stop the border there
    _settleMins(g) {
        if (g.wins.filter(o => o !== g.w && this._winSignals?.has(o)).map(o => this._learnMin(o)).some(Boolean))
            this._resizing(g, g.after);
    }

    // A resize of a tiled window (any edge or corner, or Alt+F8) moves the borders it shares with its
    // neighbours: they follow while the size changes, and on release the window snaps into its new
    // tile. Outer edges snap back. A move (Super + drag) swaps on release (_dropped).
    _grabBegin(w, op) {
        if (this._grab)
            this._grabDone();
        const a = this._auto?.get(w);
        if (a)
            a.centre = false; // the user moves or resizes it: it stays where they put it
        if (!w || !this._winSignals.has(w) || !this._tileable(w))
            return;
        const ws = w.get_workspace(), mon = this._monitor(w);
        const wins = this._tiled(ws, mon);
        const key = this._key(ws, mon);
        this._grab = {w, wins, key, n: wins.length, index: wins.indexOf(w), mode: this._mode(key),
            area: ws.get_work_area_for_monitor(mon), before: this._outset(w.get_frame_rect()), base: this._split(key)};
        // a move (Super + drag) may change the size too (a terminal on its grid): not a resize
        if (op & RESIZE_BITS)
            this._grab.sizeId = w.connect('size-changed', () => this._resizing(this._grab));
    }

    // the split for the grabbed window's tile after (default: now; the frame rect plus the border)
    _resizing(g, after = this._outset(g.w.get_frame_rect())) {
        g.after = after;
        if (after.width === g.before.width && after.height === g.before.height)
            return false;
        g.wins.forEach(o => o !== g.w && this._winSignals.has(o) && this._learnMin(o));
        // minimum tile = the window's minimum plus the border on both sides
        const bw2 = 2 * this._bw();
        const mins = g.wins.map(o => this._mins.get(o)).map(m => m && {
            width: m.width ? m.width + bw2 : 0, height: m.height ? m.height + bw2 : 0});
        splits.set(g.key, resizeSplit(g.area, g.n, g.mode, g.base, g.index, g.before, after, mins));
        this._queue();
        return true;
    }

    _grabDone() {
        const g = this._grab;
        this._grab = null;
        if (g?.sizeId)
            g.w.disconnect(g.sizeId);
    }

    _grabEnd(w) {
        const g = this._grab;
        if (!g || g.w !== w) {
            this._dropped(w);
            return;
        }
        const resized = Boolean(g.sizeId) && this._resizing(g);
        this._grabDone();
        if (resized) {
            for (const ms of [300, 1000]) {
                const id = GLib.timeout_add(GLib.PRIORITY_DEFAULT, ms, () => {
                    this._sources?.delete(id);
                    this._settleMins(g);
                    return GLib.SOURCE_REMOVE;
                });
                this._sources.add(id);
            }
        } else {
            this._dropped(w);
        }
        this._queue();
        this._later(300);
    }

    // a tiled window dragged with the mouse (Super + drag) onto another one swaps with it;
    // anywhere else it snaps back into its tile
    _dropped(w) {
        if (!w || !this._winSignals.has(w) || !this._tileable(w))
            return;
        const [px, py] = global.get_pointer();
        const other = this._tiled(w.get_workspace(), this._monitor(w)).find(o => {
            if (o === w)
                return false;
            const r = o.get_frame_rect();
            return px >= r.x && px < r.x + r.width && py >= r.y && py < r.y + r.height;
        });
        if (other) {
            const a = this._order.indexOf(w), b = this._order.indexOf(other);
            [this._order[a], this._order[b]] = [this._order[b], this._order[a]];
        }
        this._queue();
    }
}
