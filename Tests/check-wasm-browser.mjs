#!/usr/bin/env node
// Exercise the real production Wasm loader/canvas in an isolated Chrome page.
// Requires Node with global WebSocket support and ImageMagick (`magick`).
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';

const [url = 'http://127.0.0.1:8010/', endpoint = 'http://127.0.0.1:9237', output = '.build/validation/wasm-browser', mode = 'controls'] = process.argv.slice(2);
assert.ok(['controls', 'navigation'].includes(mode), 'Mode must be controls or navigation');
await fs.mkdir(output, { recursive: true });
const targets = await (await fetch(endpoint + '/json/list')).json();
const target = targets.find(item => item.type === 'page');
assert.ok(target, 'Chrome must have an isolated page target');
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
let nextID = 0;
const pending = new Map(), events = [], checks = [];
socket.onmessage = event => {
    const message = JSON.parse(event.data);
    if (message.id) {
        const request = pending.get(message.id);
        if (!request) return;
        pending.delete(message.id);
        clearTimeout(request.timeout);
        message.error ? request.reject(new Error(JSON.stringify(message.error))) : request.resolve(message.result);
    } else if (['Runtime.exceptionThrown', 'Runtime.consoleAPICalled', 'Log.entryAdded', 'Inspector.targetCrashed'].includes(message.method)) {
        events.push(message);
    }
};
const command = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++nextID;
    const timeout = setTimeout(() => { pending.delete(id); reject(new Error('Chrome command timed out: ' + method)); }, 25000);
    pending.set(id, { resolve, reject, timeout });
    socket.send(JSON.stringify({ id, method, params }));
});
const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const evaluate = async expression => (await command('Runtime.evaluate', { expression, returnByValue: true })).result.value;
const canvas = () => evaluate(`(() => { const c = document.querySelector('canvas'); if (!c) return null; const r = c.getBoundingClientRect(); return {busy:c.getAttribute('aria-busy'),width:c.width,height:c.height,x:r.x,y:r.y,w:r.width,h:r.height}; })()`);
const check = (name, pass, evidence = {}) => { checks.push({ name, pass, ...evidence }); };
const screenshot = async name => {
    const result = await command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
    const filename = path.join(output, name + '.png');
    await fs.writeFile(filename, Buffer.from(result.data, 'base64'));
    return filename;
};
const fieldDigest = filename => {
    // Exclude title and controls so UI highlight/text changes cannot masquerade
    // as shader animation or a palette change.
    const rgb = execFileSync('magick', [filename, '-crop', '1000x380+100+110', '-alpha', 'off', '-depth', '8', 'rgb:-'], { maxBuffer: 5_000_000 });
    return createHash('sha256').update(rgb).digest('hex');
};
const settingsDigest = filename => {
    const rgb = execFileSync('magick', [filename, '-crop', '512x32+344+627', '-alpha', 'off', '-depth', '8', 'rgb:-'], { maxBuffer: 100_000 });
    return createHash('sha256').update(rgb).digest('hex');
};
const rotationDigest = filename => {
    const rgb = execFileSync('magick', [filename, '-crop', '512x20+344+714', '-alpha', 'off', '-depth', '8', 'rgb:-'], { maxBuffer: 100_000 });
    return createHash('sha256').update(rgb).digest('hex');
};
const tap = async (x, y) => {
    await command('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
    await command('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
    await command('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
    await wait(500);
};
const control = async offset => {
    const bounds = await canvas();
    assert.equal(bounds.w, 1200, 'Control checks require the documented 1200×800 viewport');
    assert.equal(bounds.h, 800);
    // The sample's centered 540-point panel sits above its source-link footer.
    await tap(bounds.x + bounds.w / 2 + offset, bounds.y + bounds.h - 111);
};
const menuChoice = async (name, offset, index, optionCount) => {
    const bounds = await canvas();
    assert.equal(bounds.w, 1200);
    assert.equal(bounds.h, 800);
    const x = bounds.x + bounds.w / 2 + offset;
    const y = bounds.y + bounds.h - 157;
    await tap(x, y);
    await screenshot(name + '-menu');
    // Svala places this menu above its anchor: 16-point inset, 44-point
    // actions and 8-point action gaps. Keep real pointer input throughout.
    const height = 32 + 44 * optionCount + 8 * (optionCount - 1);
    const optionY = y - 13 - 4 - height + 16 + 22 + index * 52;
    await tap(x, optionY);
    return screenshot(name + '-selected');
};
const stepRotation = async direction => {
    const bounds = await canvas();
    await tap(bounds.x + bounds.w / 2 + direction * 69, bounds.y + bounds.h - 157);
};
const centerField = async () => {
    const bounds = await canvas();
    await tap(bounds.x + bounds.w - 164, bounds.y + 40);
};
const navigationChecks = async baseline => {
    const bounds = await canvas();
    const start = { x: bounds.x + bounds.w / 2 - 120, y: bounds.y + bounds.h / 2 - 60 };
    await command('Input.dispatchMouseEvent', { type: 'mouseMoved', ...start });
    await command('Input.dispatchMouseEvent', { type: 'mousePressed', ...start, button: 'left', buttons: 1, clickCount: 1 });
    for (let step = 1; step <= 8; ++step) {
        await command('Input.dispatchMouseEvent', { type: 'mouseMoved', x: start.x + step * 18, y: start.y + step * 8, button: 'left', buttons: 1 });
        await wait(20);
    }
    await command('Input.dispatchMouseEvent', { type: 'mouseReleased', x: start.x + 144, y: start.y + 64, button: 'left', buttons: 0, clickCount: 1 });
    await wait(500);
    const panned = await screenshot('navigation-panned');
    check('drag-pans-the-paused-field', fieldDigest(baseline) !== fieldDigest(panned));
    await centerField();
    const centeredPan = await screenshot('navigation-pan-centered');
    check('center-restores-the-original-pan-exactly', fieldDigest(baseline) === fieldDigest(centeredPan));

    await command('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 2 });
    await command('Input.synthesizePinchGesture', { x: bounds.x + bounds.w / 2, y: bounds.y + bounds.h / 2 - 50, scaleFactor: 1.5, relativeSpeed: 400, gestureSourceType: 'touch' });
    await wait(500);
    const pinched = await screenshot('navigation-pinched');
    const touchCounts = await evaluate('window.__einsteinTouchCounts');
    const maxTouches = Math.max(0, ...touchCounts);
    check('touch-pinch-zooms-the-paused-field', fieldDigest(baseline) !== fieldDigest(pinched) && maxTouches >= 2, { maxSimultaneousTouches: maxTouches });
    await command('Emulation.setTouchEmulationEnabled', { enabled: false });
    await centerField();
    const centeredPinch = await screenshot('navigation-pinch-centered');
    check('center-restores-the-original-pinch-zoom-exactly', fieldDigest(baseline) === fieldDigest(centeredPinch));

    for (const [direction, deltaY] of [['in', -150], ['out', 150]]) {
        const viewportBefore = await evaluate('({scale:window.visualViewport.scale,ratio:window.devicePixelRatio})');
        await command('Input.dispatchMouseEvent', { type: 'mouseWheel', x: bounds.x + bounds.w / 2, y: bounds.y + bounds.h / 2 - 50, deltaX: 0, deltaY });
        await wait(500);
        const wheeled = await screenshot('navigation-wheel-zoomed-' + direction);
        const viewportAfter = await evaluate('({scale:window.visualViewport.scale,ratio:window.devicePixelRatio})');
        check('mouse-wheel-zooms-' + direction + '-without-zooming-the-browser', fieldDigest(baseline) !== fieldDigest(wheeled) && JSON.stringify(viewportBefore) === JSON.stringify(viewportAfter));
        await centerField();
        const centeredWheel = await screenshot('navigation-wheel-centered-' + direction);
        check('center-restores-the-original-wheel-zoom-' + direction + '-exactly', fieldDigest(baseline) === fieldDigest(centeredWheel));
    }
};
try {
    await command('Page.enable');
    await command('Runtime.enable');
    await command('Log.enable');
    await command('Network.enable');
    await command('Network.setCacheDisabled', { cacheDisabled: true });
    // Record actual Link dispatch without opening an external tab or relying
    // on the remote site's availability. The production SwiftUI button and
    // Svala's browser URL bridge still receive the real pointer interaction.
    await command('Page.addScriptToEvaluateOnNewDocument', {
        source: `(() => { window.__einsteinOpenedURLs = [];
            window.__einsteinTouchCounts = [];
            const activeTouches = new Set();
            document.addEventListener('pointerdown', event => {
                if (event.pointerType === 'touch') {
                    activeTouches.add(event.pointerId);
                    window.__einsteinTouchCounts.push(activeTouches.size);
                }
            }, { capture: true, passive: true });
            for (const name of ['pointerup', 'pointercancel']) {
                document.addEventListener(name, event => activeTouches.delete(event.pointerId), { capture: true, passive: true });
            }
            window.open = () => ({ opener: null, location: {
                replace: url => window.__einsteinOpenedURLs.push(String(url))
            } }); })();`,
    });
    await command('Emulation.setDeviceMetricsOverride', { width: 1200, height: 800, deviceScaleFactor: 1, mobile: false });
    await command('Page.navigate', { url });
    let ready = false;
    for (let attempt = 0; attempt < 180; ++attempt) {
        await wait(250);
        if ((await canvas())?.busy === 'false') { ready = true; break; }
        if (events.some(event => event.method === 'Runtime.exceptionThrown' || event.method === 'Inspector.targetCrashed')) break;
    }
    check('production-loader-starts', ready, { canvas: await canvas() });
    assert.ok(ready, 'Production Wasm app did not start');
    if (mode === 'navigation') {
        await control(218); // Freeze time so gestures and reset can be compared exactly.
        const initial = await screenshot('navigation-default-field');
        const selected = await menuChoice('navigation-1024-field', 175, 2, 4);
        check('1024-field-option-can-be-selected', settingsDigest(initial) !== settingsDigest(selected));
        await navigationChecks(selected);
    } else {
        const initialBounds = await canvas();
        await tap(initialBounds.x + 105, initialBounds.y + 28);
        await tap(initialBounds.x + initialBounds.w - 155, initialBounds.y + initialBounds.h - 25);
        const openedURLs = await evaluate('window.__einsteinOpenedURLs');
        check('article-link-opens-the-requested-destination', openedURLs.includes('https://www.scientificamerican.com/article/newfound-mathematical-einstein-shape-creates-a-never-repeating-pattern/'), { openedURLs });
        check('source-link-opens-the-requested-destination', openedURLs.includes('https://github.com/svalasoft/EinsteinFlow'), { openedURLs });
        await wait(1200);
        const first = await screenshot('playing-first');
        await wait(1200);
        const second = await screenshot('playing-second');
        check('shader-animation-advances', fieldDigest(first) !== fieldDigest(second));

        await control(218); // Pause.
        const paused = await screenshot('paused-first');
        await wait(1200);
        const pausedSecond = await screenshot('paused-second');
        check('pause-freezes-shader-time', fieldDigest(paused) === fieldDigest(pausedSecond));
        await control(-42); // Prism.
        const prism = await screenshot('prism');
        await control(103); // Ink.
        const ink = await screenshot('ink');
        await control(-188); // Aurora.
        const aurora = await screenshot('aurora');
        check('three-palettes-change-the-rendered-field', new Set([fieldDigest(prism), fieldDigest(ink), fieldDigest(aurora)]).size === 3);

        await control(218); // Play.
        const resumed = await screenshot('resumed-first');
        await wait(1200);
        const resumedSecond = await screenshot('resumed-second');
        check('play-resumes-shader-animation', fieldDigest(resumed) !== fieldDigest(resumedSecond));

        await control(218); // Freeze the field so this check isolates visibility.
        const shown = await screenshot('shown-controls');
        const before = await canvas();
        await tap(before.x + before.w - 78, before.y + 40);
        const hidden = await screenshot('hidden-controls');
        await tap(before.x + before.w - 78, before.y + 40);
        const restored = await screenshot('restored-controls');
        const shownBytes = await fs.readFile(shown), hiddenBytes = await fs.readFile(hidden), restoredBytes = await fs.readFile(restored);
        check('controls-can-be-hidden-and-restored', !shownBytes.equals(hiddenBytes) && shownBytes.equals(restoredBytes));

        const eightLasers = await menuChoice('eight-lasers', -175, 7, 8);
        check('laser-count-menu-changes-the-rendered-cutters', fieldDigest(restored) !== fieldDigest(eightLasers));
        await stepRotation(-1); // Default clockwise 1× becomes stopped.
        const stopped = await screenshot('rotation-stopped');
        check('rotation-can-stop-without-moving-the-paused-field', rotationDigest(eightLasers) !== rotationDigest(stopped) && fieldDigest(eightLasers) === fieldDigest(stopped) && settingsDigest(eightLasers) === settingsDigest(stopped));
        await stepRotation(-1); // Continue through zero to counterclockwise 1×.
        const reversed = await screenshot('rotation-counterclockwise');
        check('rotation-can-reverse-without-changing-cutter-speed', rotationDigest(stopped) !== rotationDigest(reversed) && fieldDigest(stopped) === fieldDigest(reversed) && settingsDigest(stopped) === settingsDigest(reversed));
        await stepRotation(1);
        await stepRotation(1);
        const clockwise = await screenshot('rotation-clockwise-restored');
        check('rotation-arrows-restore-the-clockwise-default', rotationDigest(clockwise) === rotationDigest(eightLasers) && fieldDigest(clockwise) === fieldDigest(eightLasers) && settingsDigest(clockwise) === settingsDigest(eightLasers));

        const fast = await menuChoice('eight-times-speed', 0, 5, 6);
        check('speed-menu-updates-without-unpausing', settingsDigest(eightLasers) !== settingsDigest(fast) && fieldDigest(eightLasers) === fieldDigest(fast));
        const larger = await menuChoice('1024-field', 175, 2, 4);
        check('finite-field-menu-changes-the-selected-size', settingsDigest(fast) !== settingsDigest(larger));
        const largest = await menuChoice('largest-field', 175, 3, 4);
        await control(218); // Play eight cutters at 8× on the 2,048-hat field.
        await wait(1100);
        const constructing = await screenshot('large-field-playing');
        await wait(2500);
        const progressed = await screenshot('large-field-progress');
        check('maximum-field-keeps-constructing', settingsDigest(larger) !== settingsDigest(largest) && fieldDigest(constructing) !== fieldDigest(progressed));
        await control(218); // Freeze again before resizing.

        for (const [name, width, height] of [['portrait', 500, 850], ['wide', 1500, 600]]) {
            await command('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
            await wait(900);
            const bounds = await canvas();
            const filename = await screenshot(name);
            const statistics = execFileSync('magick', ['identify', '-format', '%w %h %[standard-deviation]', filename], { encoding: 'utf8' }).trim().split(/\s+/).map(Number);
            check(name + '-resizes-and-renders', bounds.w === width && bounds.h === height && statistics[0] === width && statistics[1] === height && statistics[2] > 100, { bounds, imageStatistics: statistics });
        }
    }
    const errors = events.filter(event => event.method === 'Runtime.exceptionThrown' || event.method === 'Inspector.targetCrashed' || (event.method === 'Runtime.consoleAPICalled' && event.params.type === 'error'));
    check('no-browser-runtime-errors', errors.length === 0, { errors });
} catch (error) {
    checks.push({ name: 'runner-completes', pass: false, error: String(error) });
} finally {
    await fs.writeFile(path.join(output, 'report.json'), JSON.stringify({ url, mode, checks, events }, null, 2));
    console.log(JSON.stringify({ output, passed: checks.filter(item => item.pass).length, total: checks.length, failed: checks.filter(item => !item.pass) }, null, 2));
    socket.close();
    if (checks.some(item => !item.pass)) process.exitCode = 1;
}
