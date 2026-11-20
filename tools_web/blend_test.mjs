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
async function startRun(q) { await load(q); await tapTarget('start'); return await waitFor((x) => x.mode === 'play', 5000, 'play'); }
const dirs = [[50, 0], [0, 50], [-50, 0], [0, -50]]; let kk = 0;
async function wanderUntilPicker(ms) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) { const s = await st(); if (s.mode === 'levelup') return s; const [dx, dy] = dirs[kk++ % 4]; await dragHold(195, 450, dx, dy, 300); }
  throw new Error('no picker');
}
async function safeCard() { await sleep(350); const s = await st(); const t = s.targets.find((x) => x.name === 'card0'); if (s.mode === 'levelup' && t) await tap(...center(t.rect), 'card0'); }
const logsSince = (n, re) => logs.slice(n).filter((l) => re.test(l));
// ---- B1 + B5: picker tag, then americano activation ----
let s = await startRun('t=120&god=1&skills=ice:3,espresso:2,kettle:2&offer=espresso,kettle');
let L0 = logs.length;
s = await wanderUntilPicker(120000);
await sleep(700); s = await st(); await shot('picker_blend_tag');
result.b5_picker = { options: s.options, hints: s.hints };
const iEsp = s.options.indexOf('espresso');
const t0 = s.targets.find((x) => x.name === 'card' + iEsp); await tap(...center(t0.rect), 'card' + iEsp);
await sleep(500); s = await st(); await shot('blend_banner');
result.b1_activate = { skills: s.skills, blends: s.blends, log: logsSince(L0, /COFFEE_BLEND /) };
// B2: slowing
{ const tq = Date.now(); while (Date.now() - tq < 30000) { s = await st(); if (s.mode === 'levelup') { await safeCard(); continue; } if (s.onslow >= 3) break; await sleep(150); } }
await shot('americano_slowed'); s = await st();
result.b2_slow = { slow_hits: s.blend_stats.slow_hits, slowed_enemies: s.onslow, enemies: s.enemies };
// negative: kettle (partner grinder 0) only -> no tag
s = await startRun('t=120&god=1&skills=ice:2,espresso:2,kettle:2&offer=espresso,kettle,foam');
s = await wanderUntilPicker(120000); await sleep(500); s = await st();
result.b5_negative = { options: s.options, hints: s.hints };
await shot('picker_no_tag');
// B2 boss slowed
s = await startRun('t=597&god=1&skills=ice:3,espresso:3');
s = await waitFor((x) => x.boss_hp > 0, 20000, 'boss');
let bs = false; const tb = Date.now();
while (Date.now() - tb < 20000) { s = await st(); if (s.mode === 'levelup') { const c = s.targets.find((x) => x.name === 'card0'); if (c) await tap(...center(c.rect), 'card0'); } if (s.boss_slow) { bs = true; break; } await sleep(200); }
await shot('boss_slowed');
result.b2_boss = { boss_slow_seen: bs, blends: s.blends };
// ---- B3: latteart, stand still, get hit ----
s = await startRun('t=40&hp=100&skills=foam:3,latte:3,espresso:0');
L0 = logs.length;
const t3 = Date.now();
while (Date.now() - t3 < 30000) { s = await st(); if (s.mode !== 'play') break; await sleep(300); }
await shot('latteart');
const sl = logsSince(L0, /COFFEE_BLEND_SLASH/).map((l) => +l.match(/t=([\d.]+)/)[1]);
result.b3_latte = { blends: s.blends, blocks: s.blend_stats.blocks, slashes: s.blend_stats.slashes, slash_times: sl, min_gap: sl.length > 1 ? Math.min(...sl.slice(1).map((x, i) => +(x - sl[i]).toFixed(2))) : null, mode: s.mode, hp: s.hp };
// ---- B4: pourover, no espresso ----
s = await startRun('t=60&god=1&skills=kettle:3,grinder:3,espresso:0');
{ const tq = Date.now(); while (Date.now() - tq < 25000) { s = await st(); if (s.mode === 'levelup') { await safeCard(); continue; } await sleep(200); } }
for (let i = 0; i < 10; i++) { s = await st(); if (s.mode !== 'levelup') break; await safeCard(); }
await shot('pourover'); s = await st();
result.b4_pour = { blends: s.blends, pour_hits: s.blend_stats.pour_hits, skills: s.skills };
// ---- B6 (browser part): auto bot, blends field vs log ----
L0 = logs.length;
await send('Page.navigate', { url: BASE + '?cb=' + Date.now() + '&auto=1&steps=12&seed=42' }); await sleep(3000);
s = await waitFor((x) => x.mode === 'result', 600000, 'auto result');
await shot('auto_result');
result.b6_browser_auto = { win: s.win, t: s.t, blends_state: s.blends, blend_logs: logsSince(L0, /COFFEE_BLEND /), bursts: s.bursts, skills: s.skills };
result.errors = errors;
console.log('RESULT', JSON.stringify(result, null, 1));
ws.close();
