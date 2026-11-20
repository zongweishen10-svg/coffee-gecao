// 390x844 @3x touch walkthrough for 咖啡割草. Interaction only via Input.dispatchTouchEvent.
// usage: node touch_test.mjs [baseUrl] ; env OUT=shot dir, CDP=port
import fs from 'fs';
const BASE = process.argv[2] || 'http://127.0.0.1:8811/';
const OUT = process.env.OUT || '/workspace/coffee/shots/';
const CDP = process.env.CDP || '9335';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const list = await (await fetch(`http://127.0.0.1:${CDP}/json/list`)).json();
const page = list.find((t) => t.type === 'page');
const ws = new WebSocket(page.webSocketDebuggerUrl);
let id = 0; const pending = new Map(); const errors = []; const logs = [];
const send = (method, params = {}) => new Promise((res) => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
ws.onmessage = (ev) => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result ?? m.error); pending.delete(m.id); }
  if (m.method === 'Runtime.consoleAPICalled') {
    const txt = (m.params.args || []).map((a) => a.value ?? a.description ?? '').join(' ');
    if (/COFFEE_/.test(txt)) { logs.push(txt); console.log('  CONS', txt.slice(0, 160)); }
    if (m.params.type === 'error' || /SCRIPT ERROR|USER ERROR/.test(txt)) { errors.push(txt); console.log('  ERR', txt.slice(0, 200)); }
  }
  if (m.method === 'Runtime.exceptionThrown') { const d = m.params.exceptionDetails; errors.push(d.text + ' ' + (d.exception?.description || '')); console.log('  EXC', d.text); }
  if (m.method === 'Log.entryAdded' && m.params.entry.level === 'error') { errors.push('LOG ' + m.params.entry.text + ' ' + (m.params.entry.url || '')); console.log('  LOGERR', m.params.entry.text, m.params.entry.url || ''); }
};
await new Promise((r) => (ws.onopen = r));
await send('Page.enable'); await send('Runtime.enable'); await send('Log.enable');
await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 3, mobile: true });
await send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
const ev = async (e) => { const r = await send('Runtime.evaluate', { expression: e, returnByValue: true }); return r?.result?.value; };
const st = async () => JSON.parse((await ev('JSON.stringify(window.__coffee||null)')) || 'null');
async function waitFor(pred, ms = 180000, label = '') {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) { const s = await st(); if (s && pred(s)) return s; await sleep(200); }
  throw new Error('timeout ' + label + ' last=' + JSON.stringify(await st()));
}
let n = 0;
async function shot(name) {
  const r = await send('Page.captureScreenshot', { format: 'png' });
  const p = `${OUT}${String(++n).padStart(2, '0')}_${name}.png`;
  fs.writeFileSync(p, Buffer.from(r.data, 'base64')); console.log('  shot', p);
}
let K = 1;
const tp = (x, y) => ({ x: x * K, y: y * K, radiusX: 6, radiusY: 6, force: 1, id: 1 });
async function tap(x, y, label) {
  await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [tp(x, y)] });
  await sleep(70);
  await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  console.log(`TOUCH ${label} vp=(${x.toFixed(0)},${y.toFixed(0)})`);
  await sleep(300);
}
const center = (r) => [r[0] + r[2] / 2, r[1] + r[3] / 2];
async function tapTarget(name) {
  const s = await st(); const t = s.targets.find((x) => x.name === name);
  if (!t) throw new Error('no target ' + name + ' in ' + JSON.stringify(s.targets));
  await tap(...center(t.rect), name);
}
async function dragHold(x0, y0, dx, dy, holdMs, end = true) {
  await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [tp(x0, y0)] });
  for (let i = 1; i <= 8; i++) { await send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [tp(x0 + dx * i / 8, y0 + dy * i / 8)] }); await sleep(25); }
  await sleep(holdMs);
  if (end) await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}
async function load(q) {
  const url = BASE + '?cb=' + Date.now() + (q ? '&' + q : '');
  console.log('navigate', url);
  await send('Page.navigate', { url });
  const t0 = Date.now();
  const s = await waitFor((x) => x.mode === 'title', 240000, 'title');
  K = (await ev('window.innerWidth')) / s.vw;
  console.log(`loaded in ${((Date.now() - t0) / 1000).toFixed(1)}s viewport ${s.vw}x${s.vh} css/vp=${K} coins=${s.total_coins}`);
  return s;
}

const result = {};
async function safeCard() { await sleep(350); const s = await st(); const t = s.targets.find((x) => x.name === 'card0'); if (s.mode === 'levelup' && t) await tap(...center(t.rect), 'card0'); }
async function startRun(q) { await load(q); await tapTarget('start'); return await waitFor((x) => x.mode === 'play', 5000, 'play'); }
const dirs = [[50, 0], [0, 50], [-50, 0], [0, -50]]; let kk = 0;
async function wander(ms, pred) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    let s = await st(); if (pred(s)) return s;
    if (s.mode === 'levelup') { await sleep(400); await safeCard(); continue; }
    const [dx, dy] = dirs[kk++ % 4]; await dragHold(195, 450, dx, dy, 350);
  }
  return await st();
}
async function waitReady(minFull = 3.0) { const tq = Date.now(); let s; while (Date.now() - tq < 150000) { s = await st();
  if (s.mode === 'levelup') { await safeCard(); continue; }
  if (s.full > minFull && s.targets.find((x) => x.name === 'burst')) return s;
  if (s.full > 0) { await sleep(150); continue; }
  const [dx, dy] = dirs[kk++ % 4]; await dragHold(195, 450, dx, dy, 250); } throw new Error('never ready'); }
async function resolveLevelups() { for (let i = 0; i < 8; i++) { const s = await st(); if (s.mode !== 'levelup') return s; await sleep(400); await safeCard(); await sleep(500); } return await st(); }
const pick = (s) => ({ t: s.t, caf: s.caf, full: s.full, atk: s.atk, jitter: s.jitter, kills: s.kills, onscreen: s.onscreen, beans: s.beans, xp: s.xp, level: s.level, ppos: s.ppos, drag: s.drag, bursts: s.bursts, boss_hp: s.boss_hp, burst_target: !!s.targets.find((x) => x.name === 'burst') });
// ---- #1 + #2: real 45 beans from empty, ready window, keep collecting beans, timeout -> jitter ----
let s = await startRun('t=150&god=1');
s = await wander(240000, (x) => x.full > 0);
if (!(s.full > 0)) throw new Error('never filled');
await sleep(250); s = await st(); await shot('ready_state');
result.c1_ready = pick(s);
const bt = s.targets.find((x) => x.name === 'burst'); result.c1_button_rect = bt && bt.rect;
const tFull = s.t + s.full - 5.0;
const xp0 = s.xp, lv0 = s.level;
// keep collecting beans during window (should NOT extend)
let maxFull = s.full, samples = [];
while (true) { s = await st(); if (s.mode === 'levelup') { await sleep(300); await safeCard(); continue; } if (!(s.full > 0)) break; maxFull = Math.max(maxFull, s.full); samples.push([s.t, s.full, s.caf]); const [dx, dy] = dirs[kk++ % 4]; await dragHold(195, 450, dx, dy, 150); }
s = await st();
result.c2_timeout = { full_started_at: +tFull.toFixed(1), ended_at: s.t, window_len: +(s.t - tFull).toFixed(1), jitter: s.jitter, burst_target: !!s.targets.find((x) => x.name === 'burst'), caf: s.caf, atk: s.atk, xp_gained_during_window: (s.level - lv0) * 1000 + (s.xp - xp0), caf_during_window_min: Math.min(...samples.map((x) => x[2])), samples: samples.length };
await shot('jitter_after_timeout');
await sleep(3300); s = await st(); result.c2_after3s = { jitter: s.jitter, caf: s.caf, atk: s.atk };
console.log('PARTIAL', JSON.stringify(result));
// ---- #3: tap burst, ppos unchanged, no drag ----
s = await startRun('t=150&god=1&caf=40');
s = await waitReady(4.0); await sleep(500); s = await st(); if (!s.targets.find((x) => x.name === 'burst')) s = await waitReady(1.0);
const before = pick(s);
await shot('pre_burst');
const r = s.targets.find((x) => x.name === 'burst').rect; const [bx, by] = center(r);
await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [tp(bx, by)] });
await sleep(450); const during = pick(await st());
// keep the finger down and slide it 60px: must still not move the player
for (let i = 1; i <= 6; i++) { await send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [tp(bx - i * 10, by - i * 10)] }); await sleep(60); }
await sleep(500); const sliding = pick(await st());
await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
await sleep(300); await shot('post_burst'); const after = pick(await st());
result.c3_burst = { before, during_press: during, while_sliding_finger: sliding, after,
  ppos_unchanged: JSON.stringify(before.ppos) === JSON.stringify(during.ppos) && JSON.stringify(before.ppos) === JSON.stringify(sliding.ppos) && JSON.stringify(before.ppos) === JSON.stringify(after.ppos) };
// second finger while dragging
s = await startRun('t=150&god=1&caf=40');
s = await waitReady(3.0);
const r2 = s.targets.find((x) => x.name === 'burst').rect; const [cx2, cy2] = center(r2);
const f1 = (x, y) => ({ x: x * K, y: y * K, radiusX: 6, radiusY: 6, force: 1, id: 1 }), f2 = (x, y) => ({ x: x * K, y: y * K, radiusX: 6, radiusY: 6, force: 1, id: 2 });
await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [f1(150, 450)] });
for (let i = 1; i <= 5; i++) { await send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [f1(150 - i * 10, 450)] }); await sleep(30); }
await sleep(300); const mv0 = pick(await st());
await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [f1(100, 450), f2(cx2, cy2)] });
await sleep(400); const mv1 = pick(await st());
await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [f1(100, 450)] });
await sleep(400); const mv2 = pick(await st());
await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
result.c3_two_finger = { dragging_before: mv0.drag, bursts_after: mv1.bursts, still_dragging: mv1.drag, x_moving: [mv0.ppos[0], mv1.ppos[0], mv2.ppos[0]] };
console.log('PARTIAL', JSON.stringify(result));
// ---- #4: boss fight burst = exactly 300 ----
s = await startRun('t=580&god=1&pacifist=1');
s = await waitFor((x) => x.boss_hp > 0, 40000, 'boss');
s = await waitReady(1.0);
await sleep(250); s = await st();
const b0 = pick(s); await shot('boss_ready');
await tapTarget('burst'); await sleep(300); s = await st(); const b1 = pick(s);
await shot('boss_after_burst');
result.c4_boss = { before: b0, after: b1, boss_delta: +(b0.boss_hp - b1.boss_hp).toFixed(2) };
console.log('PARTIAL', JSON.stringify(result));
// ---- #5 (browser part): auto bot, fast-forwarded ----
await send('Page.navigate', { url: BASE + '?cb=' + Date.now() + '&auto=1&steps=12&seed=7' }); await sleep(3000);
s = await waitFor((x) => x.mode === 'result', 600000, 'auto result');
await shot('auto_result');
result.c5_browser_auto = { win: s.win, t: s.t, kills: s.kills, level: s.level, run_coins: s.run_coins, bursts: s.bursts };
const fl = logs.filter((l) => /COFFEE_(FULL|JITTER)/.test(l)).slice(0, 2); result.c2_log_window = fl;
result.errors = errors;
console.log('RESULT', JSON.stringify(result, null, 1));
ws.close();
