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

const result = {}; const R = (k, v) => { result[k] = v; console.log('CHECK', k, JSON.stringify(v)); };
async function startRun(q) { await load(q); await tapTarget('start'); return await waitFor((x) => x.mode === 'play', 5000, 'play'); }
const dirs = [[50, 0], [0, 50], [-50, 0], [0, -50]]; let kk = 0;
async function step() { const [dx, dy] = dirs[kk++ % 4]; await dragHold(195, 450, dx, dy, 250); }
async function safeCard(i = 0) { await sleep(600); const s = await st(); const t = s.targets.find((x) => x.name === 'card' + i); if (s.mode === 'levelup' && t) await tap(...center(t.rect), 'card' + i); await sleep(300); }
async function untilPicker(ms = 120000) { const t0 = Date.now(); while (Date.now() - t0 < ms) { const s = await st(); if (s.mode === 'levelup') { await sleep(700); return await st(); } await step(); } throw new Error('no picker'); }
async function tapName(name) { await sleep(150); const s = await st(); const t = s.targets.find((x) => x.name === name); if (!t) throw new Error('no target ' + name + ' ' + JSON.stringify(s.targets.map((x) => x.name))); await tap(...center(t.rect), name); await sleep(350); return await st(); }
const logsSince = (n, re) => logs.slice(n).filter((l) => re.test(l));
// #1 kills == change during first 30s
let s = await startRun('god=1');
const samples = []; let bad = 0;
while (true) { s = await st(); if (s.t >= 29.5) break; if (s.mode === 'levelup') { await safeCard(); continue; } samples.push([s.t, s.kills, s.change]); if (s.kills !== s.change) bad++; await step(); }
R('c1_kills_eq_change', { samples: samples.length, mismatches: bad, last: samples[samples.length - 1], has_bonus_field: 'bonus_coins' in s });
// #2 tip -> change (+15 normal)
s = await startRun('t=55&god=1&order=kill');
s = await waitFor((x) => x.customers.length > 0, 15000, 'cust');
let b0 = { change: s.change, kills: s.kills };
while (s.cust_stats.done < 1) { s = await st(); if (s.mode === 'levelup') { await safeCard(); continue; } b0 = s.cust_stats.done < 1 ? { change: s.change, kills: s.kills } : b0; await step(); }
await sleep(300); s = await st();
R('c2_tip_normal', { tip: (s.change - b0.change) - (s.kills - b0.kills), log: logs.filter((l) => /ORDER_DONE/.test(l)).slice(-1), bonus_field: 'bonus_coins' in s });
// elite: stand still, god
s = await startRun('t=300&god=1&order=elite&skills=espresso:5,kettle:5,grinder:5');
s = await waitFor((x) => x.customers.length > 0, 15000, 'elite');
let e0 = { change: s.change, kills: s.kills };
{ const tq = Date.now(); while (Date.now() - tq < 60000) { s = await st(); if (s.mode === 'levelup') { await safeCard(); continue; } if (s.cust_stats.done >= 1 || s.cust_stats.timeout >= 1) break; e0 = { change: s.change, kills: s.kills }; await step(); } }
await sleep(200); s = await st();
R('c2_tip_elite', { done: s.cust_stats.done, timeout: s.cust_stats.timeout, log: logs.filter((l) => /ORDER_DONE|ORDER_FAIL|ORDER_TIME/.test(l)).slice(-1), tip: (s.change - e0.change) - (s.kills - e0.kills) });
// #3 change=50: first banish -> 30, second fee 40 greyed
s = await startRun('god=1&pacifist=1&skills=espresso:1&change=50&offer=kettle,foam,ice');
await sleep(800);
async function taps(x, y, n) { for (let i = 0; i < n; i++) { await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [tp(x, y)] }); await sleep(50); await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] }); await sleep(140); } await sleep(400); }
await taps(195, 70, 5); s = await st(); console.log('admin open', s.mode, 'change', s.change);
await tapTarget('adm_lvup'); await sleep(900); s = await st();
await shot('picker_banish_ui');
R('c3_picker', { options: s.options, change: s.change, targets: s.targets.map((x) => x.name) });
s = await tapName('banish_0');
R('c3_first', { change: s.change, banished: s.banished, spent: s.banish_spent, options: s.options, mode: s.mode });
await sleep(600); s = await st();
const unownedIdx = s.options.findIndex((o) => ['espresso','kettle','foam','ice','grinder','latte'].includes(o) && !(s.skills[o] > 0));
const names = s.targets.map((x) => x.name);
await shot('picker_greyed');
const greyRect = { x: 20 + (390 - 40) - 98 + 44, y: 190 + unownedIdx * 142 + 8 + 21 };
await tap(greyRect.x, greyRect.y, 'greyed'); await sleep(500); const s2 = await st();
R('c3_second', { unowned_option: s.options[unownedIdx], banish_target_present: names.includes('banish_' + unownedIdx), after_tap: { mode: s2.mode, change: s2.change, banished: s2.banished, options: s2.options, still_in_pool: s2.options.includes(s.options[unownedIdx]) } });
// #4 sacrifice Lv2 kettle
s = await startRun('t=120&god=1&skills=kettle:2');
s = await untilPicker();
const c4 = s.change;
s = await tapName('banishown_kettle');
R('c4_sacrifice', { delta: s.change - c4, kettle: s.skills.kettle || 0, banished: s.banished, log: logs.filter((l) => /BANISH/.test(l)).slice(-1) });
await safeCard(); await sleep(1500); s = await st(); R('c4_after', { skills: s.skills, mode: s.mode });
// #6 blend lost
s = await startRun('t=120&god=1&skills=espresso:3,ice:3');
let L6 = logs.length;
{ const tq = Date.now(); while (Date.now() - tq < 20000) { s = await st(); if (s.blend_stats.slow_hits > 3) break; if (s.mode === 'levelup') { await safeCard(); continue; } await step(); } }
s = await untilPicker();
const sh0 = s.blend_stats.slow_hits;
s = await tapName('banishown_espresso');
await shot('blend_lost_banner');
R('c6_blend_lost', { blends: s.blends, log: logsSince(L6, /BLEND_LOST/), slow_hits_before: sh0 });
await safeCard(); await sleep(4000); s = await st();
R('c6_after', { blends: s.blends, slow_hits: s.blend_stats.slow_hits, onslow: s.onslow });
// #7 menu mult + cap
s = await startRun('t=120&god=1&change=1000');
s = await untilPicker();
for (let n = 0; n < 5; n++) {
  if (n === 2) { s = await st(); R('c7_two', { menu_mult: s.menu_mult, banished: s.banished }); await shot('picker_menu_line'); }
  s = await st(); const nm = s.targets.map((x) => x.name).find((x) => x.startsWith('banish_') || x.startsWith('banishown_'));
  if (!nm) break; s = await tapName(nm); await sleep(500);
}
s = await st(); await shot('picker_five_banished');
R('c7_five', { menu_mult: s.menu_mult, banished: s.banished, banish_targets: s.targets.map((x) => x.name).filter((x) => x.startsWith('banish')), change: s.change, spent: s.banish_spent, options: s.options });
// #5 settlement with change=37
s = await startRun('t=100&pacifist=1&hp=1&change=37');
s = await waitFor((x) => x.mode === 'result', 60000, 'death');
await sleep(500); await shot('result_change');
R('c5_settle', { change: s.change, run_coins: s.run_coins, t: s.t, expect: Math.floor(Math.min(s.t, 600) / 20) + Math.floor(37 / s.change_rate), rate: s.change_rate });
// #8 banish=foam auto run
let L8 = logs.length;
await send('Page.navigate', { url: BASE + '?cb=' + Date.now() + '&auto=1&steps=12&seed=42&banish=foam' }); await sleep(3000);
s = await waitFor((x) => x.mode === 'result', 600000, 'auto');
const lv = logsSince(L8, /LEVELUP|COFFEE_BLEND |BANISH/);
R('c8_banish_foam', { win: s.win, t: s.t, foam_offered: lv.filter((l) => /LEVELUP/.test(l) && /foam/.test(l)).length, levelups: lv.filter((l) => /LEVELUP/.test(l)).length, blends: s.blends, banished: s.banished, skills: s.skills, menu_mult: s.menu_mult, change: s.change, run_coins: s.run_coins });
R('errors', errors);
console.log('RESULT', JSON.stringify(result));
ws.close();
