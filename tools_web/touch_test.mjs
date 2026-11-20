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
{ await send('Network.enable'); await send('Network.setCacheDisabled', { cacheDisabled: true });
  await send('Network.emulateNetworkConditions', { offline: false, latency: 50, downloadThroughput: 4000000, uploadThroughput: 1000000 });
  await send('Page.navigate', { url: BASE + '?cb=load' + Date.now() }); await sleep(4000); await shot('loading');
  await send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: -1, uploadThroughput: -1 });
  await send('Network.setCacheDisabled', { cacheDisabled: false }); }
let s = await load('');
result.coins_before = s.total_coins;
await shot('title');
await tapTarget('start');
s = await waitFor((x) => x.mode === 'play', 5000, 'play');
await sleep(500); await shot('start_hint');
const p0 = s.ppos;
await dragHold(195, 600, 0, -60, 1500);
s = await st(); const p1 = s.ppos;
await dragHold(195, 600, 60, 0, 1200);
s = await st(); const p2 = s.ppos;
console.log('drag up', p0, '->', p1, ' drag right ->', p2);
result.drag_up_ok = p1[1] < p0[1] - 100;
result.drag_right_ok = p2[0] > p1[0] + 80;
s = await waitFor((x) => x.enemies > 0, 15000, 'enemies');
result.enemies_seen = s.enemies;
let lvShot = false; const dirs = [[50, 0], [0, 50], [-50, 0], [0, -50]]; let k = 0;
const tLv = Date.now();
while (Date.now() - tLv < 120000) {
  s = await st();
  if (s.mode === 'levelup') break;
  const [dx, dy] = dirs[k++ % 4];
  await dragHold(195, 600, dx, dy, 700);
  if (!lvShot && s.enemies > 8) { lvShot = true; await shot('play_enemies'); }
}
s = await waitFor((x) => x.mode === 'levelup', 5000, 'levelup');
await sleep(500);
await shot('levelup_picker');
result.levelup_options = s.options;
const before = JSON.stringify(s.skills);
await tapTarget('card1');
s = await waitFor((x) => x.mode === 'play' || x.mode === 'levelup', 3000, 'after pick');
result.picked = { before, after: JSON.stringify(s.skills), opt: result.levelup_options[1] };
result.pick_ok = before !== JSON.stringify(s.skills) || ['heal', 'coin'].includes(result.levelup_options[1]);
const tJ = Date.now(); let jitterSeen = false; k = 0;
while (Date.now() - tJ < 60000) {
  s = await st();
  if (s.mode === 'levelup') { await sleep(400); await tapTarget('card0'); continue; }
  if (s.mode !== 'play') break;
  if (s.jitter) { jitterSeen = true; await shot('jitter'); break; }
  const [dx, dy] = dirs[k++ % 4];
  await dragHold(195, 600, dx, dy, 600);
}
result.jitter_seen = jitterSeen;
s = await st(); result.play_state = { t: s.t, level: s.level, kills: s.kills, hp: s.hp, caf: s.caf, fps: s.fps, skills: s.skills };
await shot('midgame');
s = await load('t=598&god=1&bosshp=120');
await tapTarget('start');
s = await waitFor((x) => x.boss_hp > 0, 15000, 'boss');
await sleep(1800); await shot('boss');
{ const tb = Date.now(); let ringShot = false;
  while (Date.now() - tb < 300000) {
    s = await st();
    if (s.mode === 'result') break;
    if (s.mode === 'levelup') { await sleep(400); await tapTarget('card0'); continue; }
    if (!ringShot && s.boss_state === 'tele_ring') { ringShot = true; await shot('boss_ring'); }
    await sleep(150);
  } }
s = await waitFor((x) => x.mode === 'result', 5000, 'boss result');
await sleep(400); await shot('result_win');
result.win = { win: s.win, run_coins: s.run_coins, total: s.total_coins, kills: s.kills };
await tapTarget('again');
s = await waitFor((x) => x.mode === 'play', 3000, 'again');
result.again_ok = s.mode === 'play' && s.t < 600;
s = await load('hp=3');
result.coins_persisted = s.total_coins;
await tapTarget('start');
s = await waitFor((x) => x.mode === 'result', 90000, 'lose');
await sleep(400); await shot('result_lose');
result.lose = { win: s.win, t: s.t, run_coins: s.run_coins, total: s.total_coins };
await tapTarget('title');
s = await waitFor((x) => x.mode === 'title', 3000, 'title back');
await shot('title_after');
{ const c0 = s.total_coins, m0 = s.meta.hp;
  await tapTarget('buy_hp');
  s = await waitFor((x) => x.meta.hp === m0 + 1, 3000, 'buy hp');
  result.shop = { coins_before: c0, coins_after: s.total_coins, hp_lv: s.meta.hp };
  await shot('title_bought'); }
if (s.meta.reroll === 0 && s.total_coins >= 50) { await tapTarget('buy_reroll'); s = await waitFor((x) => x.meta.reroll === 1, 3000, 'buy reroll'); }
s = await load('');
result.shop_persisted = s.meta;
await tapTarget('start');
s = await waitFor((x) => x.mode === 'play', 5000, 'play2');
result.max_hp_run = s.max_hp;
if (s.rerolls > 0) {
  k = 0; const tR = Date.now();
  while (Date.now() - tR < 120000) { s = await st(); if (s.mode === 'levelup') break; const [dx, dy] = dirs[k++ % 4]; await dragHold(195, 600, dx, dy, 700); }
  await sleep(500); s = await st(); const o0 = JSON.stringify(s.options), r0 = s.rerolls;
  await shot('reroll_before'); await tapTarget('reroll');
  s = await waitFor((x) => x.mode === 'levelup' && x.rerolls === r0 - 1, 3000, 'reroll');
  result.reroll = { before: o0, after: JSON.stringify(s.options), rerolls_left: s.rerolls };
  await tapTarget('card0');
}
result.errors = errors;
console.log('RESULT', JSON.stringify(result, null, 1));
ws.close();
