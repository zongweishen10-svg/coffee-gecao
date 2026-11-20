const [url, dpr] = [process.argv[2], +process.argv[3]];
const list = await (await fetch('http://127.0.0.1:9335/json/list')).json();
const ws = new WebSocket(list.find((t) => t.type === 'page').webSocketDebuggerUrl);
let id = 0; const pending = new Map();
const send = (m, p = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method: m, params: p })); });
ws.onmessage = (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result ?? m.error); pending.delete(m.id); } };
await new Promise((r) => (ws.onopen = r));
await send('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: dpr, mobile: true });
await send('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 5 });
await send('Page.navigate', { url });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const st = async () => JSON.parse((await send('Runtime.evaluate', { expression: 'JSON.stringify(window.__coffee||null)', returnByValue: true })).result.value || 'null');
let s; while (!(s = await st()) || s.mode !== 'title') await sleep(300);
const b = s.targets[0].rect;
await send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: b[0] + 100, y: b[1] + 30 }] }); await sleep(60);
await send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
for (let i = 0; i < 6; i++) { await sleep(2500); s = await st(); console.log('dpr', dpr, 'mode', s.mode, 't', s.t, 'enemies', s.enemies, 'beans', s.beans, 'fps', s.fps, 'upd_us', s.us_update, 'draw_us', s.us_draw); }
ws.close();
