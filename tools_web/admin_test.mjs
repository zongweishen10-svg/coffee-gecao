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
async function taps(x, y, n) { for (let i = 0; i < n; i++) { await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [tp(x, y)] }); await sleep(50); await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] }); await sleep(140); } await sleep(400); }
async function btn(name) { await tapTarget(name); await sleep(250); return await st(); }
let s = await load('');
const coins0 = s.total_coins;
await taps(195, s.vh * 0.235, 4); s = await st(); R('four_taps_no_open', s.mode);
await sleep(900);
await taps(195, s.vh * 0.235, 5); s = await st(); R('open_from_title', { mode: s.mode, adm: s.adm });
await shot('panel_title');
s = await btn('adm_coins'); R('coins', { before: coins0, after: s.total_coins });
s = await btn('adm_god'); const g1 = s.god; s = await btn('adm_god'); const g2 = s.god; s = await btn('adm_god'); R('god_toggle', [g1, g2, s.god]);
s = await btn('adm_next_min'); R('next_min_from_title', { mode: s.mode, t: s.t });
s = await btn('adm_next_min'); R('next_min_again', { t: s.t });
s = await btn('adm_skillpage'); R('skill_page', s.adm); await shot('panel_skill_page');
s = await btn('adm_sk_ice'); R('skill_plus1_ice', s.skills.ice);
s = await btn('adm_back');
s = await btn('adm_bl_americano'); R('blend_americano', { skills: s.skills, blends: s.blends });
s = await btn('adm_bl_latteart'); s = await btn('adm_bl_pourover'); R('blend_all', { skills: s.skills, blends: s.blends });
s = await btn('adm_maxall'); R('max_all', s.skills);
s = await btn('adm_caf'); R('caf_full', { caf: s.caf, full: s.full });
s = await btn('adm_cust'); R('cust_normal', s.customers.map((c) => c.kind));
s = await btn('adm_cust_elite'); R('cust_elite', s.customers.map((c) => c.kind));
const tFrozen = s.t; await sleep(1200); s = await st(); R('paused_while_open', { t1: tFrozen, t2: s.t });
s = await btn('adm_boss'); R('jump_955', s.t);
s = await btn('adm_close'); await sleep(1200); s = await st(); R('closed_resumes', { mode: s.mode, t: s.t, cheat: s.cheat, full: s.full, bursts: s.bursts });
await shot('hud_cheat_mark');
// mid-run open via timer
for (let i = 0; i < 6; i++) { s = await st(); if (s.mode === 'levelup') { await sleep(500); await tapTarget('card0'); } else break; }
await taps(195, 70, 5); s = await st(); R('open_midrun', { mode: s.mode, adm: s.adm });
await shot('panel_midrun');
const t0 = s.t; await sleep(1000); s = await st(); R('midrun_paused', { t0, t1: s.t });
s = await btn('adm_lvup'); R('level_up_now', { mode: s.mode, options: s.options });
await sleep(600); await tapTarget('card0'); await sleep(500); s = await st(); R('after_pick', { mode: s.mode, level: s.level });
await sleep(4500); s = await st(); R('boss_after_jump', { boss_hp: s.boss_hp, t: s.t });
await taps(195, 70, 5); s = await st();
s = await btn('adm_reset'); const lab = s.targets.find((x) => x.name === 'adm_reset'); await shot('reset_confirm');
s = await btn('adm_reset'); R('reset_save', { mode: s.mode, coins: s.total_coins, meta: s.meta });
await sleep(500); await load(''); s = await st(); R('reset_persisted', { coins: s.total_coins, meta: s.meta });
R('errors', errors);
console.log('RESULT', JSON.stringify(result));
ws.close();
