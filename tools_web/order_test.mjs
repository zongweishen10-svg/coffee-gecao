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
const cust = (s) => (s.customers && s.customers[0]) || null;
async function startRun(q) { let s = await load(q); await tapTarget('start'); return await waitFor((x) => x.mode === 'play', 5000, 'play'); }
async function wander(ms, pred) {
  const dirs = [[50, 0], [0, 50], [-50, 0], [0, -50]]; let k = 0; const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    let s = await st();
    if (pred(s)) return s;
    if (s.mode === 'levelup') { await sleep(400); await tapTarget('card0'); continue; }
    const [dx, dy] = dirs[k++ % 4]; await dragHold(195, 600, dx, dy, 600);
  }
  return await st();
}
// ---- #1 + #2: t=55, customer at 60, complete kill order (god so HP only changes by reward) ----
let s = await startRun('t=55&hp=50&god=1&order=kill');
s = await waitFor((x) => cust(x), 15000, 'customer');
const c1 = cust(s);
result.c1_appear = { t: s.t, born: c1.born, kind: c1.kind, progress: `${c1.have}/${c1.need}`, ttl: c1.ttl };
await sleep(600); await shot('customer_bubble');
const hpBefore = s.hp, bonusBefore = (s.change - s.kills);
s = await wander(45000, (x) => x.cust_stats.done >= 1);
result.c2_reward = { hp_before: hpBefore, hp_after: s.hp, max_hp: s.max_hp, bonus_before: bonusBefore, bonus_after: (s.change - s.kills), done: s.cust_stats.done, next_cust_t: s.next_cust_t, t: s.t };
await shot('order_done');
// heal cap: hp 95, bean order
s = await startRun('t=55&hp=95&god=1&order=bean');
s = await waitFor((x) => cust(x), 15000, 'customer2');
s = await wander(45000, (x) => x.cust_stats.done >= 1);
result.c2_cap = { hp_after: s.hp, max_hp: s.max_hp, bonus_after: (s.change - s.kills), done: s.cust_stats.done };
// settlement: no god, finish an order, then die and read result
s = await startRun('t=55&hp=40&order=kill');
s = await wander(60000, (x) => x.cust_stats.done >= 1 || x.mode === 'result');
const bonusAtDone = (s.change - s.kills);
for (let i = 0; i < 400; i++) { s = await st(); if (s.mode === 'result') break; if (s.mode === 'levelup') await tapTarget('card0'); await sleep(600); }
await sleep(400); await shot('result_with_bonus');
result.c2_settle = { bonus_coins: (s.change - s.kills), bonus_at_done: bonusAtDone, run_coins: s.run_coins, kills: s.kills, t: s.t, change: s.change, expect: Math.floor(Math.min(s.t, 600) / 20) + Math.floor(s.change / (s.change_rate || 5)), orders_done: s.cust_stats.done };
// ---- #3: timeout (god + pacifist: no kills, no beans) ----
s = await startRun('t=55&god=1&pacifist=1&order=bean');
s = await waitFor((x) => cust(x), 15000, 'customer3');
const born3 = cust(s).born, snap = { hp: s.hp, bonus: (s.change - s.kills), level: s.level, max_hp: s.max_hp };
s = await waitFor((x) => !cust(x), 60000, 'timeout');
await sleep(300); await shot('customer_left');
result.c3_timeout = { born: born3, left_at: s.t, timeout_count: s.cust_stats.timeout, done: s.cust_stats.done, next_cust_t: s.next_cust_t,
  before: snap, after: { hp: s.hp, bonus: (s.change - s.kills), level: s.level, max_hp: s.max_hp } };
s = await waitFor((x) => cust(x), 100000, 'next customer');
result.c3_next = { appeared_at: cust(s).born, gap_after_leave: +(cust(s).born - result.c3_timeout.next_cust_t + 75).toFixed(1) };
// ---- #5: customer present when boss arrives (normal + elite) ----
for (const kind of ['kill', 'elite']) {
  s = await startRun(`t=592&god=1&pacifist=1&order=${kind}`);
  s = await waitFor((x) => cust(x), 15000, 'boss-customer');
  await sleep(700); await shot('pre_boss_' + kind);
  const pre = { t: s.t, kind: cust(s).kind, milk: s.kinds[3] };
  s = await waitFor((x) => x.boss_hp > 0, 15000, 'boss');
  await sleep(800);
  for (let i = 0; i < 6; i++) { s = await st(); if (s.mode !== 'levelup') break; await tapTarget('card0'); await sleep(900); }
  await sleep(1200); s = await st(); await shot('boss_after_' + kind);
  result['c5_' + kind] = { pre, after: { t: s.t, customers: s.customers.length, boss_left: s.cust_stats.boss_left, milk_alive: s.kinds[3], boss_hp: s.boss_hp, next_cust_t: s.next_cust_t } };
  await sleep(4000); s = await st(); result['c5_' + kind].later_customers = s.customers.length;
}
result.errors = errors;
console.log('RESULT', JSON.stringify(result, null, 1));
ws.close();
