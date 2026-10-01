// Pure layout math of kit-tiling (no GNOME imports, so tests can run it with node or gjs).
// Rectangles are {x, y, width, height} in pixels; the tiles cover the area exactly, without gaps.

export const MIN_RATIO = 0.2, MAX_RATIO = 0.8;
// smallest tile a border drag may leave (pixels along the dragged axis)
export const MIN_TILE = 100;

const clampRatio = r => Math.min(MAX_RATIO, Math.max(MIN_RATIO, r));

// stackWeights(weights, count): the first count weights (missing or invalid ones are 1), each kept
// within 1/4 .. 4 of the mean so no stack tile vanishes
export function stackWeights(weights = [], count = 0) {
    const w = Array.from({length: count}, (_, i) => {
        const v = Number(weights[i]);
        return Number.isFinite(v) && v > 0 ? v : 1;
    });
    const mean = w.reduce((s, v) => s + v, 0) / (count || 1);
    return w.map(v => Math.min(mean * 4, Math.max(mean / 4, v)));
}

// splits length into parts proportional to weights; the parts add up to length exactly
function split(length, weights) {
    const total = weights.reduce((s, v) => s + v, 0);
    const cuts = [0];
    let acc = 0;
    for (const v of weights) {
        acc += v;
        cuts.push(Math.round(length * acc / total));
    }
    return weights.map((_, i) => [cuts[i], cuts[i + 1] - cuts[i]]);
}

// tileRects(area, n, mode, ratio, weights): tiles for n windows, in window order.
//   n = 1: the whole area; n = 2: main and one other side by side (top and bottom for "wide");
//   n >= 3: main area plus a stack that shares the rest by weights (default: evenly).
//   mode: "tall" (main on the left), "wide" (main on top), "monocle" (every window fills the area).
//   ratio: share of the main area, 0.2 .. 0.8.
//   weights: relative sizes of the stack tiles, first stack tile first; extra entries are kept for
//   larger window counts and ignored here (see stackWeights).
export function tileRects(area, n, mode = 'tall', ratio = 0.5, weights = []) {
    if (n <= 0)
        return [];
    const {x, y, width, height} = area;
    if (n === 1 || mode === 'monocle')
        return Array.from({length: n}, () => ({x, y, width, height}));
    const r = clampRatio(ratio);
    const parts = split(mode === 'wide' ? width : height, stackWeights(weights, n - 1));
    if (mode === 'wide') {
        const mh = Math.round(height * r);
        return [{x, y, width, height: mh},
            ...parts.map(([o, len]) => ({x: x + o, y: y + mh, width: len, height: height - mh}))];
    }
    const mw = Math.round(width * r);
    return [{x, y, width: mw, height},
        ...parts.map(([o, len]) => ({x: x + mw, y: y + o, width: width - mw, height: len}))];
}

// resizeSplit(area, n, mode, split, index, before, after, mins): the split after the user resized
// the tiled window at index from frame rect before to frame rect after (mouse on any edge or corner,
// or the keyboard). split and the result are {ratio, weights}. mins (optional): per window in tile
// order, the smallest {width, height} it accepts (0 = unknown).
//   - the edge between main and stack sets the ratio (0.2 .. 0.8, and no window below its minimum);
//   - an edge between two stack tiles moves only that border: the two neighbours share the change,
//     the other stack tiles keep their size; neither neighbour gets smaller than MIN_TILE or its
//     minimum;
//   - outer edges (at the area's border) change nothing: the window snaps back into its tile.
// A new weights array is returned; entries beyond the current stack are kept for later.
export function resizeSplit(area, n, mode, splitState, index, before, after, mins = []) {
    const ratio = clampRatio(splitState?.ratio ?? 0.5);
    const weights = [...(splitState?.weights ?? [])];
    const out = {ratio, weights};
    if (n < 2 || mode === 'monocle' || index < 0 || index >= n)
        return out;
    const wide = mode === 'wide';
    // "main axis" = the axis across the main/stack border; "stack axis" = the one along the stack
    const lo = (r, stackAxis) => (wide === stackAxis ? r.x : r.y);
    const hi = (r, stackAxis) => lo(r, stackAxis) + (wide === stackAxis ? r.width : r.height);
    const moved = (stackAxis, end) => (end ? hi : lo)(after, stackAxis) !== (end ? hi : lo)(before, stackAxis);
    const aLo = lo(area, false), aLen = wide ? area.height : area.width;
    // minimum of window i along an axis
    const least = (i, stackAxis) => Number((wide === stackAxis ? mins[i]?.width : mins[i]?.height) ?? 0) || 0;

    // main/stack border: the far edge of main, or the near edge of a stack tile
    const mainEdge = index === 0 ? (moved(false, true) ? hi(after, false) : null)
        : (moved(false, false) ? lo(after, false) : null);
    if (mainEdge !== null) {
        let len = mainEdge - aLo;
        const stackMin = Math.max(0, ...Array.from({length: n - 1}, (_, i) => least(i + 1, false)));
        len = Math.max(len, least(0, false));
        len = Math.min(len, aLen - stackMin);
        out.ratio = clampRatio(len / aLen);
    }

    if (index === 0 || n < 3)
        return out;
    // border between stack tiles i-1 and i (i counts in the stack, 0 = first stack tile)
    const rest = n - 1, s = index - 1;
    const sLo = lo(area, true), sLen = wide ? area.width : area.height;
    const sizes = split(sLen, stackWeights(weights, rest)).map(([, len]) => len);
    let changed = false;
    const border = (i, pos) => {
        if (i <= 0 || i >= rest)
            return;
        const pair = sizes[i - 1] + sizes[i];
        const minA = Math.max(MIN_TILE, least(i, true)), minB = Math.max(MIN_TILE, least(i + 1, true));
        if (pair < minA + minB)
            return;
        const start = sLo + sizes.slice(0, i - 1).reduce((a, v) => a + v, 0);
        sizes[i - 1] = Math.min(pair - minB, Math.max(minA, pos - start));
        sizes[i] = pair - sizes[i - 1];
        changed = true;
    };
    if (moved(true, false))
        border(s, lo(after, true));
    if (moved(true, true))
        border(s + 1, hi(after, true));
    if (!changed)
        return out;
    // weights relative to an even share, rounded; later entries stay
    sizes.forEach((len, i) => {
        weights[i] = Math.round(len * rest / sLen * 1000) / 1000;
    });
    out.weights = weights;
    return out;
}

// A client gets SETTLE_MS to take the size the tiler asked for, twice as long after every retry (up
// to 16x). Still more than OFF_BY pixels off after that, it is asked again with one pixel less and,
// once it answered that (or the same wait passed), with the tile size, at most RETRIES times: Electron
// on Wayland (Agent Workbench, GNOME 46) sometimes keeps reporting an old window size although it drew
// the new one, and mutter sends no new request for a size it already asked for; a different size makes
// the client report its real one. The tile size is not sent while the nudge is unanswered: a client
// that gets both before its next frame answers only the last one, the size it already has (F34 on a
// real display: an x86 VM answered after up to 18 s). A few pixels off is a character grid (GNOME
// Terminal), larger than asked a minimum size: after RETRIES the tiler stops asking. A client that then
// draws or reports another size on its own while still off its tile gets a new round (at most ROUNDS
// per tile size); a window that fits is forgotten, so a later slip starts over. The tiler looks once
// more after the last request, for shouldFloat below.
export const SETTLE_MS = 500, OFF_BY = 32, RETRIES = 4, ROUNDS = 3;

// how long to wait for an answer after the request made at `tries` retries
export function waitMs(tries) {
    return SETTLE_MS * 2 ** Math.min(tries, 4);
}

// nextAsk(frame, target, asked, now, buffer): the size to ask a tiled window for in this pass.
//   frame, target: its frame rect and its tile ({width, height} suffice); buffer: its buffer rect
//   (default: frame); asked: what was asked before ({width, height, since, tries, rounds, nudged,
//   seen, at, seen0}; width and height are the tile size, also while a nudge is out; seen = frame and
//   buffer size at the last request; at, seen0 = time and sizes of the first request for this tile) or
//   null; now: time in ms.
// Returns {size, asked, check}: size = {width, height} to ask for now, or null (it fits, or a nudge is
// waiting for its answer); asked = the new record (null: it fits, forget it); check = ms after which the tiler should look again,
// 0 = no need.
export function nextAsk(frame, target, asked, now, buffer = frame) {
    const {width, height} = target;
    const seen = `${frame.width}x${frame.height} ${buffer.width}x${buffer.height}`;
    const mine = Boolean(asked) && asked.width === width && asked.height === height;
    if (frame.width === width && frame.height === height) // fits: a later slip starts over
        return {size: null, asked: null, check: 0};
    if (!mine)
        return {size: {width, height}, asked: {width, height, since: now, tries: 0, rounds: 0, seen, at: now, seen0: seen}, check: SETTLE_MS};
    const offW = Math.abs(frame.width - width), offH = Math.abs(frame.height - height);
    const {tries, rounds = 0} = asked;
    const answered = seen !== asked.seen, waited = now - asked.since;
    if (asked.nudged) { // the tile size again, once the client answered the nudge
        if (!answered && waited < waitMs(tries))
            return {size: null, asked, check: waitMs(tries) - waited};
        return {size: {width, height}, asked: {...asked, since: now, nudged: false, seen}, check: waitMs(tries)};
    }
    if (Math.max(offW, offH) <= OFF_BY) // a character grid
        return {size: {width, height}, asked, check: 0};
    if (tries >= RETRIES) {
        if (!answered || rounds + 1 >= ROUNDS)
            return {size: {width, height}, asked, check: 0};
        return {size: {width, height}, asked: {...asked, since: now, tries: 0, rounds: rounds + 1, seen}, check: SETTLE_MS};
    }
    if (waited < waitMs(tries))
        return {size: {width, height}, asked, check: waitMs(tries) - waited};
    const size = offW > OFF_BY ? {width: width - 1, height} : {width, height: height - 1};
    return {size, asked: {...asked, since: now, tries: tries + 1, nudged: true, seen}, check: waitMs(tries + 1)};
}

// Owner decision 2026-09-27 (Q4): a window that stays larger than its tile floats, centred on its
// monitor at its own size, and the others tile without it. A new window (first frame less than NEW_MS
// ago, never at its tile size yet) floats fast: once it answered the first request made after its
// first frame and is still too large, or FAST_MS after that request without an answer (Sessions would
// otherwise overlap its neighbours for about 30 s). Any other window floats only after the retries:
// a window that was resized, the stale sizes Electron reports (F34), VS Code back from full screen with
// 668x422 in a 636x380 tile. Electron child windows
// (Agent Workbench "Sessions", 700x460 minimum, and "First Steps") carry no parent on native Wayland,
// so mutter does not float them as dialogs; in a smaller tile they overlapped their neighbours.
// Terminals are never floated (a character grid, or a minimum such as Ptyxis' 294 px in a deep
// stack), and neither is a window the user tiled by hand (Super+T) or one that fits.
export const NEW_MS = 5000, FAST_MS = 1500;
const TERMINALS = new Set(['terminal', 'ghostty', 'alacritty', 'ptyxis', 'kitty', 'xterm', 'uxterm',
    'konsole', 'foot', 'footclient', 'wezterm', 'tilix', 'console', 'kgx', 'terminator', 'urxvt', 'rxvt',
    'st', 'terminology', 'blackbox']);

// isTerminal(...names): true when a WM class or app id names a terminal emulator
// (com.mitchellh.ghostty, org.gnome.Terminal, Gnome-terminal, org.gnome.Ptyxis, Alacritty, ...)
export function isTerminal(...names) {
    return names.some(n => String(n ?? '').toLowerCase().split(/[^a-z0-9]+/).some(t => TERMINALS.has(t)));
}

// shouldFloat(frame, target, asked, now, buffer, {terminal, pinned, born, fitted}): true when a tiled
// window's frame is still more than OFF_BY pixels larger than its tile in width or height and
//   - it is new (born: time of its first frame in ms, less than NEW_MS ago; fitted: it had its tile
//     size once) and it answered the first request made after its first frame, or FAST_MS passed since
//     that request (fast path), or
//   - it has used up its retries for this tile (nextAsk: no new round, the wait after the last request
//     has passed; slow path).
export function shouldFloat(frame, target, asked, now, buffer = frame,
    {terminal = false, pinned = false, born = null, fitted = false} = {}) {
    if (terminal || pinned || !asked)
        return false;
    if (frame.width <= target.width + OFF_BY && frame.height <= target.height + OFF_BY)
        return false;
    if (asked.width !== target.width || asked.height !== target.height)
        return false;
    if (born !== null && !fitted && now - born < NEW_MS) {
        const seen = `${frame.width}x${frame.height} ${buffer.width}x${buffer.height}`;
        // a request from before the first frame proves nothing: the client drew its own size first
        const since = Math.max(born, asked.at ?? asked.since);
        if ((asked.at ?? -Infinity) >= born && seen !== asked.seen0)
            return true;
        if (now - since >= FAST_MS)
            return true;
    }
    const next = nextAsk(frame, target, asked, now, buffer);
    return next.asked === asked && asked.tries >= RETRIES && !asked.nudged && next.check === 0 &&
        now - asked.since >= waitMs(asked.tries);
}

// lateFit(frame, tile): a window floated on the fast path took its tile size after all (a slow client's
// late answer): it goes back into the tiles
export function lateFit(frame, tile) {
    return Boolean(tile) && frame.width <= tile.width + OFF_BY && frame.height <= tile.height + OFF_BY;
}

// centred(area, size): the top-left corner that centres size in area; a window larger than the area
// starts at its top-left corner
export function centred(area, size) {
    return {x: area.x + Math.max(0, Math.round((area.width - size.width) / 2)),
        y: area.y + Math.max(0, Math.round((area.height - size.height) / 2))};
}

// neighbour(rects, from, dir): index of the rectangle next to rects[from] in direction
// "left" | "right" | "up" | "down", or -1. Prefers rectangles that overlap on the other axis,
// then the nearest centre.
export function neighbour(rects, from, dir) {
    const a = rects[from];
    if (!a)
        return -1;
    const ac = {x: a.x + a.width / 2, y: a.y + a.height / 2};
    let best = -1, bestScore = Infinity;
    rects.forEach((b, i) => {
        if (i === from || !b)
            return;
        const bc = {x: b.x + b.width / 2, y: b.y + b.height / 2};
        const dx = bc.x - ac.x, dy = bc.y - ac.y;
        let along, across, overlap;
        switch (dir) {
        case 'left': along = -dx; across = Math.abs(dy); overlap = b.y < a.y + a.height && a.y < b.y + b.height; break;
        case 'right': along = dx; across = Math.abs(dy); overlap = b.y < a.y + a.height && a.y < b.y + b.height; break;
        case 'up': along = -dy; across = Math.abs(dx); overlap = b.x < a.x + a.width && a.x < b.x + b.width; break;
        case 'down': along = dy; across = Math.abs(dx); overlap = b.x < a.x + a.width && a.x < b.x + b.width; break;
        default: return;
        }
        if (along <= 0)
            return;
        const score = (overlap ? 0 : 1e6) + along + across / 2;
        if (score < bestScore) {
            bestScore = score;
            best = i;
        }
    });
    return best;
}
