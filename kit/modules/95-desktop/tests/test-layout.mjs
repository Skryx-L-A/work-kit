// Unit test of the kit tiler's layout math (extensions/kit-tiling@work-kit/layout.js).
// Run: node tests/test-layout.mjs   (or gjs -m). Prints "ok"/"FAIL" lines, exits 1 on a failure.
import {tileRects, neighbour, resizeSplit, stackWeights, MIN_TILE, nextAsk, waitMs, SETTLE_MS, OFF_BY, RETRIES, ROUNDS,
    shouldFloat, isTerminal, centred, lateFit, NEW_MS, FAST_MS} from '../extensions/kit-tiling@work-kit/layout.js';

let fail = 0;
const check = (name, cond) => { console.log(`${cond ? 'ok  ' : 'FAIL'} ${name}`); if (!cond) fail = 1; };
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const area = {x: 0, y: 24, width: 1280, height: 776};
const r = (x, y, width, height) => ({x, y, width, height});
// every pixel of the area covered exactly once
const covers = (rects, a) => {
    const sum = rects.reduce((s, q) => s + q.width * q.height, 0);
    const inside = rects.every(q => q.x >= a.x && q.y >= a.y && q.x + q.width <= a.x + a.width && q.y + q.height <= a.y + a.height);
    const overlap = rects.some((p, i) => rects.some((q, j) => i < j &&
        p.x < q.x + q.width && q.x < p.x + p.width && p.y < q.y + q.height && q.y < p.y + p.height));
    return sum === a.width * a.height && inside && !overlap;
};

check('no window, no tile', eq(tileRects(area, 0), []));
check('one window fills the work area', eq(tileRects(area, 1), [r(0, 24, 1280, 776)]));
check('two windows split it in halves', eq(tileRects(area, 2), [r(0, 24, 640, 776), r(640, 24, 640, 776)]));
check('three windows: main left, stack of two on the right',
    eq(tileRects(area, 3), [r(0, 24, 640, 776), r(640, 24, 640, 388), r(640, 412, 640, 388)]));
for (const n of [1, 2, 3, 4, 5, 7])
    check(`tall, ${n} windows cover the area without gaps or overlap`, covers(tileRects(area, n), area));
for (const n of [2, 3, 5])
    check(`wide, ${n} windows cover the area`, covers(tileRects(area, n, 'wide'), area));
check('wide: main on top', eq(tileRects(area, 3, 'wide')[0], r(0, 24, 1280, 388)));
check('ratio 0.6 widens the main area', tileRects(area, 2, 'tall', 0.6)[0].width === 768);
check('ratio is clamped to 0.2 .. 0.8', tileRects(area, 2, 'tall', 0.95)[0].width === 1024);
check('monocle: every window fills the area', tileRects(area, 3, 'monocle').every(q => eq(q, area)));
const odd = {x: 1280, y: 0, width: 1277, height: 799};
check('odd sizes still cover exactly (second monitor)', covers(tileRects(odd, 4), odd));
const t3 = tileRects(area, 3);
check('neighbour: right of main is a stack window', [1, 2].includes(neighbour(t3, 0, 'right')));
check('neighbour: left of the stack is main', neighbour(t3, 1, 'left') === 0 && neighbour(t3, 2, 'left') === 0);
check('neighbour: down / up inside the stack', neighbour(t3, 1, 'down') === 2 && neighbour(t3, 2, 'up') === 1);
check('neighbour: nothing left of main, nothing above the top', neighbour(t3, 0, 'left') === -1 && neighbour(t3, 1, 'up') === -1);

// ---- border drags (resizeSplit) ------------------------------------------------------------
const S0 = {ratio: 0.5, weights: []};
const grow = (q, d) => ({...q, ...d});
// main's right edge dragged to x = 800: the ratio follows, the stack moves along
let s = resizeSplit(area, 3, 'tall', S0, 0, t3[0], grow(t3[0], {width: 800}));
check('main right edge sets the ratio', s.ratio === 0.625 && eq(s.weights, []));
check('...and the stack starts where main ends', tileRects(area, 3, 'tall', s.ratio, s.weights)[1].x === 800);
s = resizeSplit(area, 3, 'tall', S0, 2, t3[2], grow(t3[2], {x: 500, width: 780}));
check('a stack window\'s left edge sets the ratio too', tileRects(area, 3, 'tall', s.ratio)[0].width === 500);
s = resizeSplit(area, 2, 'tall', S0, 1, tileRects(area, 2)[1], grow(tileRects(area, 2)[1], {x: 900, width: 380}));
check('two windows: the border between them sets the ratio', tileRects(area, 2, 'tall', s.ratio)[0].width === 900);
check('ratio drag is clamped to 0.2 .. 0.8',
    resizeSplit(area, 2, 'tall', S0, 0, t3[0], grow(t3[0], {width: 1270})).ratio === 0.8 &&
    resizeSplit(area, 2, 'tall', S0, 1, t3[1], grow(t3[1], {x: 10, width: 1270})).ratio === 0.2);
// the border between stack windows 1 and 2 of a four-window layout
const t4 = tileRects(area, 4);
s = resizeSplit(area, 4, 'tall', S0, 1, t4[1], grow(t4[1], {height: t4[1].height + 100}));
let r4 = tileRects(area, 4, 'tall', s.ratio, s.weights);
check('stack border: upper neighbour grows by the drag', r4[1].height === t4[1].height + 100);
check('stack border: lower neighbour shrinks by the same', r4[2].height === t4[2].height - 100 && r4[2].y === t4[2].y + 100);
check('stack border: the other stack window keeps its size', eq(r4[3], t4[3]));
check('stack border: ratio unchanged, area still covered', s.ratio === 0.5 && covers(r4, area));
// the same border from the other side (top edge of the lower window)
const s2 = resizeSplit(area, 4, 'tall', S0, 2, t4[2], grow(t4[2], {y: t4[2].y + 100, height: t4[2].height - 100}));
check('stack border from below gives the same split', eq(tileRects(area, 4, 'tall', s2.ratio, s2.weights), r4));
// a corner: main/stack border and stack border at once
s = resizeSplit(area, 3, 'tall', S0, 1, t3[1], grow(t3[1], {x: 700, width: 580, height: 500}));
let r3 = tileRects(area, 3, 'tall', s.ratio, s.weights);
check('corner drag moves both borders', r3[1].x === 700 && r3[1].height === 500 && r3[2].height === 276);
// minimum sizes
s = resizeSplit(area, 3, 'tall', S0, 1, t3[1], grow(t3[1], {height: 770}));
r3 = tileRects(area, 3, 'tall', s.ratio, s.weights);
check(`stack border stops ${MIN_TILE} px before the neighbour vanishes`, r3[2].height === MIN_TILE && r3[1].height === 776 - MIN_TILE);
s = resizeSplit(area, 3, 'tall', S0, 2, t3[2], grow(t3[2], {y: 30, height: 770}));
check('...also when dragged from below', tileRects(area, 3, 'tall', s.ratio, s.weights)[1].height === MIN_TILE);
// minimum sizes the windows report (learned by the extension)
s = resizeSplit(area, 3, 'tall', S0, 2, t3[2], grow(t3[2], {y: 300, height: 500}), [null, {width: 0, height: 294}, {}]);
check('stack border stops at the neighbour\'s minimum height', tileRects(area, 3, 'tall', s.ratio, s.weights)[1].height === 294);
s = resizeSplit(area, 3, 'tall', S0, 0, t3[0], grow(t3[0], {width: 1000}), [{}, {width: 400, height: 0}, {width: 360, height: 0}]);
check('main border stops at the widest stack minimum', tileRects(area, 3, 'tall', s.ratio, s.weights)[1].width === 400);
s = resizeSplit(area, 2, 'tall', S0, 1, t3[1], grow(t3[1], {x: 300, width: 980}), [{width: 500, height: 0}, {}]);
check('...and at main\'s own minimum', tileRects(area, 2, 'tall', s.ratio)[0].width === 500);
check('minimums that do not fit leave the border alone',
    eq(resizeSplit(area, 3, 'tall', S0, 1, t3[1], grow(t3[1], {height: 300}), [{}, {height: 500}, {height: 500}]), S0));
// outer edges change nothing (the window snaps back)
const outer = [
    [1, 0, t3[0], grow(t3[0], {y: 100, height: 700})],     // main top edge
    [1, 0, t3[0], grow(t3[0], {x: 40, width: 600})],       // main left edge
    [3, 1, t3[1], grow(t3[1], {width: 600})],              // stack right edge
    [3, 1, t3[1], grow(t3[1], {y: 80, height: 332})],      // top edge of the first stack window
    [3, 2, t3[2], grow(t3[2], {height: 300})],             // bottom edge of the last stack window
];
check('outer edges and a single window keep the split', outer.every(([n, i, b, a]) => eq(resizeSplit(area, n, 'tall', S0, i, b, a), S0)));
check('monocle ignores resizing', eq(resizeSplit(area, 3, 'monocle', S0, 0, t3[0], grow(t3[0], {width: 800})), S0));
// persistence across window count changes
s = resizeSplit(area, 4, 'tall', S0, 1, t4[1], grow(t4[1], {height: t4[1].height + 100}));
const w4 = s.weights;
const r3b = tileRects(area, 3, 'tall', s.ratio, w4);
check('a window closes: the remaining stack keeps the proportions of its first tiles',
    Math.abs(r3b[1].height / r3b[2].height - r4[1].height / r4[2].height) < 0.02 && covers(r3b, area));
check('the window comes back: the four-window split is exactly as before', eq(tileRects(area, 4, 'tall', s.ratio, w4), r4));
const r5 = tileRects(area, 5, 'tall', s.ratio, w4);
check('a fifth window gets an even share and everything still covers the area', covers(r5, area) && r5[4].height > 100);
s = resizeSplit(area, 3, 'tall', {ratio: 0.5, weights: [1.5, 0.5, 1, 2]}, 1, t3[1], grow(t3[1], {height: 400}));
check('a drag with fewer windows keeps the weights for more windows', s.weights.length === 4 && s.weights[2] === 1 && s.weights[3] === 2);
// wide layout: main on top, the stack is a row
const w3 = tileRects(area, 3, 'wide');
s = resizeSplit(area, 3, 'wide', S0, 0, w3[0], grow(w3[0], {height: 500}));
check('wide: main bottom edge sets the ratio', tileRects(area, 3, 'wide', s.ratio)[0].height === 500);
s = resizeSplit(area, 3, 'wide', S0, 1, w3[1], grow(w3[1], {width: 800}));
const rw = tileRects(area, 3, 'wide', s.ratio, s.weights);
check('wide: border inside the row', rw[1].width === 800 && rw[2].x === 800 && rw[2].width === 480 && covers(rw, area));
const sw = stackWeights([100, 1], 2);
check('weights are kept within 1/4 .. 4 of the mean, invalid ones count as 1',
    eq(sw, [100, 12.625]) && eq(stackWeights([0, 'x'], 2), [1, 1]));

// ---- asking a window for its tile size again (nextAsk) ---------------------------------------
// F34: after its "First Steps" window closed, the Agent Workbench (Electron, Wayland) kept reporting
// 636x405 although it drew 636x764, and asking again for 636x764 made mutter send nothing new
const tile = {width: 636, height: 764};
const stale = {width: 636, height: 405};
let a = nextAsk({width: 636, height: 380}, tile, null, 0);
check('a new tile size is asked for and looked at again', eq(a.size, tile) && a.check === SETTLE_MS && a.asked.tries === 0);
a = nextAsk(stale, tile, a.asked, 100);
check('...a client still answering gets the same request, no nudge yet', eq(a.size, tile) && a.check === SETTLE_MS - 100);
a = nextAsk(stale, tile, a.asked, SETTLE_MS + 10);
check('still off after SETTLE_MS: asked with one pixel less', eq(a.size, {width: 636, height: 763}) && a.asked.tries === 1);
check('...the record keeps the tile size, not the nudge', a.asked.width === 636 && a.asked.height === 764);
check('...and waits twice as long for the answer', a.check === waitMs(1) && waitMs(1) === 2 * SETTLE_MS);
const nudged = a.asked;
// F34 on a real display (x86 VM, virtio-gpu): the client answered after seconds; the tile size sent
// right after the nudge reached it together with the nudge, and it answered only the last request
a = nextAsk(stale, tile, nudged, SETTLE_MS + 20);
check('an unanswered nudge is not followed by the tile size at once', a.size === null && a.check > 0);
a = nextAsk({width: 636, height: 763}, tile, nudged, SETTLE_MS + 30);
check('the client answered the nudge: the tile size at once', eq(a.size, tile) && a.check === waitMs(1));
a = nextAsk(stale, tile, nudged, SETTLE_MS + 10 + waitMs(1));
check('no answer within the wait: the tile size anyway', eq(a.size, tile) && !a.asked.nudged);
const b = nextAsk(stale, tile, a.asked, SETTLE_MS + 10 + waitMs(1) + SETTLE_MS);
check('the next nudge waits longer (backoff)', eq(b.size, tile) && b.asked.tries === 1);
// a client that stays silent: RETRIES nudges, then the tiler stops looking
let st = null, t = 0, nudges = 0, last = null;
for (; t < 120000; t += 100) {
    const n = nextAsk(stale, tile, st, t);
    if (n.size && n.size.height === 763)
        nudges++;
    st = n.asked;
    last = n;
}
check(`a client that stays off gets ${RETRIES} nudges, then no more checks`, nudges === RETRIES && last.check === 0 && eq(last.size, tile));
// F34 on the real display: frame 636x379 while the buffer was already 680x808; after the retries the
// client draws another size on its own: a new round, at most ROUNDS per tile size
let rr = nextAsk(stale, tile, st, t, {width: 680, height: 808});
check('after the retries, a client that draws a new size gets a new round', rr.asked.tries === 0 && rr.asked.rounds === 1 && rr.check === SETTLE_MS);
let rounds = 1;
for (let k = 0; k < 10; k++) {
    let s2 = rr.asked;
    for (let u = 0; u < 60000; u += 100) {
        t += 100;
        s2 = nextAsk(stale, tile, s2, t, {width: 680, height: 808}).asked;
    }
    rr = nextAsk(stale, tile, s2, t, {width: 680, height: 700 + k});
    if (rr.asked.tries === 0 && rr.asked.rounds > rounds)
        rounds = rr.asked.rounds;
}
check(`...at most ${ROUNDS} rounds`, rounds === ROUNDS - 1 && rr.check === 0);
check('a window that stays still after the retries is left alone (minimum size)',
    nextAsk(stale, tile, st, t + 1000).check === 0 && nextAsk(stale, tile, st, t + 1000).asked === st);
const fit = nextAsk(tile, tile, st, t);
check('fits: nothing to ask, the record is dropped', fit.size === null && fit.check === 0 && fit.asked === null);
const slip = nextAsk(stale, tile, fit.asked, t + 5000);
check('...a later slip starts over with all its retries', eq(slip.size, tile) && slip.asked.tries === 0 && slip.asked.rounds === 0 &&
    nextAsk(stale, tile, slip.asked, t + 5000 + SETTLE_MS).asked.tries === 1);
const grid = nextAsk({width: 630, height: 750}, tile, {...tile, since: 0, tries: 0}, 10 * SETTLE_MS);
check(`a character grid (up to ${OFF_BY} px off) is not nudged`, eq(grid.size, tile) && !grid.check);
const wide = nextAsk({width: 744, height: 764}, tile, {...tile, since: 0, tries: 0}, SETTLE_MS);
check('a window too wide is nudged in its width', eq(wide.size, {width: 635, height: 764}));
check('a new tile size starts over', nextAsk(stale, {width: 636, height: 380}, st, t).asked.tries === 0);
check('the waits double up to 16x', waitMs(0) === SETTLE_MS && waitMs(4) === 16 * SETTLE_MS && waitMs(9) === waitMs(4));

// ---- a window that stays larger than its tile floats (shouldFloat, owner decision 2026-09-27, Q4) ------
// the Agent Workbench's "Sessions" window (Electron, no Wayland parent) keeps its minimum 744x540 frame
// in a 636x380 stack tile and overlapped its neighbours; it floats once the retries are used up
const sTile = {width: 636, height: 380};
const sessions = {width: 744, height: 540};
// runs the tiler's passes every 100 ms (shouldFloat before nextAsk, as _relayout does); frameAt(t) and
// bufferAt(t) give the client's sizes. Returns the float time (-1: never), the nudges, the last request
const simulate = (frameAt, opts = {}, until = 120000, bufferAt = frameAt) => {
    let rec = null, floatAt = -1, nudges = 0, lastAsk = -1;
    for (let tt = 0; tt <= until; tt += 100) {
        if (shouldFloat(frameAt(tt), sTile, rec, tt, bufferAt(tt), opts)) {
            floatAt = tt;
            break;
        }
        const n = nextAsk(frameAt(tt), sTile, rec, tt, bufferAt(tt));
        if (n.size && (n.size.width !== sTile.width || n.size.height !== sTile.height))
            nudges++;
        if (n.asked && n.asked !== rec && !n.asked.nudged)
            lastAsk = tt;
        rec = n.asked;
    }
    return {floatAt, nudges, lastAsk};
};
const sim = simulate(() => sessions);
check('a window at a minimum larger than its tile floats', sim.floatAt > 0);
check(`...only after all ${RETRIES} retries and the wait after the last request`,
    sim.nudges === RETRIES && sim.floatAt >= sim.lastAsk + waitMs(RETRIES) && sim.floatAt < sim.lastAsk + waitMs(RETRIES) + 200);
let rec = null;
for (let tt = 0; tt < 60000; tt += 100) {
    const n = nextAsk(sessions, sTile, rec, tt);
    if (n.asked && n.asked.tries === RETRIES && !n.asked.nudged && n.asked !== rec) {
        check('the last request after the retries is looked at once more (for shouldFloat)', n.check === waitMs(RETRIES));
        break;
    }
    rec = n.asked;
}
check('a terminal is never floated (character grid or a minimum such as Ptyxis 294 px)',
    simulate(() => sessions, {terminal: true}).floatAt === -1);
check('a window the user tiled by hand (Super+T) is not floated again', simulate(() => sessions, {pinned: true}).floatAt === -1);
check('a window that fits is never floated', simulate(() => sTile).floatAt === -1 && !shouldFloat(sTile, sTile, null, 0));
check(`a character grid (up to ${OFF_BY} px larger) is never floated`,
    simulate(() => ({width: 636 + OFF_BY, height: 380 + OFF_BY})).floatAt === -1);
// F34: a stale main window reports a size smaller than its tile; that is the retry's case, not a float
check('a window smaller than its tile is never floated', simulate(() => ({width: 636, height: 302})).floatAt === -1);
check('a window larger only while the retries run takes its tile and is not floated',
    simulate(tt => (tt < 4000 ? sessions : sTile)).floatAt === -1);
// after the retries the client draws a new buffer on its own: a new round first, then the float
const newRound = simulate(() => sessions, {}, 240000, tt => (tt < 25000 ? {width: 788, height: 584} : {width: 790, height: 586}));
check('a client that draws a new size after the retries gets its new round before it floats',
    newRound.floatAt > sim.floatAt && newRound.nudges > RETRIES);
check('isTerminal knows the terminals by WM class or app id',
    ['com.mitchellh.ghostty', 'org.gnome.Terminal', 'Gnome-terminal', 'org.gnome.Ptyxis', 'Alacritty', 'kitty', 'XTerm',
        'org.kde.konsole', 'foot', 'org.wezfurlong.wezterm', 'org.gnome.Console'].every(c => isTerminal(c)));
check('...and not the apps', !['agent-workbench', 'Agent Workbench', 'code', 'Code', 'firefox', 'org.gnome.Nautilus',
    'dev.zed.Zed', 'org.gnome.TextEditor'].some(c => isTerminal(c)) && !isTerminal(null, undefined, ''));
check('...a match in any name counts (WM class, then app id)', isTerminal('Main', 'com.mitchellh.ghostty'));
check('centred on the work area, below the top bar', eq(centred(area, sessions), {x: 268, y: 142}));
check('a window larger than the work area starts at its top-left corner', eq(centred(area, {width: 1400, height: 900}), {x: 0, y: 24}));

// ---- new windows float fast (follow-up: Sessions overlapped its neighbours for about 30 s) ----------
// passes every 100 ms from `start` (a window-created pass may come before the first frame at `born`);
// returns the float time or -1
const floatTime = (frameAt, tile, opts, start = 0, until = 60000) => {
    let rec = null;
    for (let tt = start; tt <= until; tt += 100) {
        const fr = frameAt(tt);
        if (shouldFloat(fr, tile, rec, tt, fr, opts))
            return tt;
        rec = nextAsk(fr, tile, rec, tt).asked;
    }
    return -1;
};
const born = 1000;
// created at 900 (asked before its first frame, frame still 0x0), first frame at 1000 at its minimum
let ft = floatTime(tt => (tt < born ? {width: 0, height: 0} : sessions), sTile, {born}, 900);
check('a new Sessions-like window (no answer) floats within about 2 s of its first frame', ft >= born + FAST_MS && ft <= born + 2000);
check('...the request from before its first frame does not count as answered (no float at the first frame)', ft > born + 100);
// asked right at its first frame, the client answers (a new size, still too large): it floats at once
ft = floatTime(tt => (tt < born + 300 ? {width: 800, height: 600} : sessions), sTile, {born}, born);
check('a new window that answers and stays too large floats right after the answer', ft >= born + 300 && ft <= born + 400);
check('a new window that takes its tile quickly is not floated',
    floatTime(tt => (tt < born + 400 ? {width: 1200, height: 800} : sTile), sTile, {born}, born) === -1);
check('a new window that is smaller than its tile is not floated', floatTime(() => ({width: 400, height: 300}), sTile, {born}, born) === -1);
check('a new terminal or a new window tiled by hand is not floated',
    floatTime(() => sessions, sTile, {born, terminal: true}, born) === -1 && floatTime(() => sessions, sTile, {born, pinned: true}, born) === -1);
// not new: the slow path with all retries
const retriesEnd = sim.floatAt; // Sessions without a first-frame time: after the retries (about 30 s)
const vsBack = {width: 668, height: 422}; // VS Code back from full screen in a 636x380 tile (kit-tile2)
ft = floatTime(() => vsBack, sTile, {born: 0}, 60000, 180000);
check('an existing window larger after leaving full screen does not float before its retries',
    ft === -1 || ft - 60000 >= retriesEnd);
check('...and not at all when it takes its tile within 12 s, as VS Code did',
    floatTime(tt => (tt < 72000 ? vsBack : sTile), sTile, {born: 0}, 60000, 180000) === -1);
check(`a window whose first frame was ${NEW_MS / 1000} s or more ago takes the slow path`,
    floatTime(() => sessions, sTile, {born: 0}, NEW_MS) - NEW_MS >= retriesEnd);
check('a new window that had its tile size once takes the slow path (a stale Electron size, F34)',
    floatTime(() => sessions, sTile, {born, fitted: true}, born) - born >= retriesEnd);
check('a window with no first-frame time (there before the tiler started) takes the slow path',
    floatTime(() => sessions, sTile, {born: null}, 0) === retriesEnd);
check('lateFit: a fast-floated window that took its tile size (or the nudge) goes back',
    lateFit(sTile, sTile) && lateFit({width: 635, height: 380}, sTile) && !lateFit(sessions, sTile) && !lateFit(sTile, null));

process.exitCode = fail;
