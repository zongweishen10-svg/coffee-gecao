# 咖啡割草 – coffee survivor-like prototype

手机网页试玩：https://zongweishen10-svg.github.io/coffee-gecao/

拖动屏幕走位，自动攻击，撑过十分钟，打败最终 Boss「周一早晨」。标题页可以用金币买永久强化（生命上限、磁铁范围、重随一次）。局内每隔一段时间来一位顾客点单，做完拿小费、回一点血。咖啡因满槽后有 5 秒可以点右下角「爆发」清屏，不点就手抖；两个技能都到 3 级会自动拼成一杯（冰美式 / 拿铁 / 手冲套装），多一条联动。Godot 4.7.2 网页导出（单线程，iPhone Safari 可玩）。

## 目录
- `proto/`：Godot 项目源码（`scripts/main.gd` 全部玩法）。
- 根目录 `index.*`：网页导出。`index.wasm` 是官方 Godot 4.7.2 web no-threads 模板原样文件，部署时由 `scripts/fetch_engine.py` 下载并校验 sha256，不存进仓库。
- `_chunks/`：（只在首次上传时出现）二进制文件的 base64，Actions 用 `scripts/assemble.py` 解码并提交后删除。
- `tools_web/`：无头 Chrome 触屏测试脚本。

## 本地重新导出
```
cd proto
python3 tools/make_font.py /path/to/NotoSansSC.ttf   # 改了文字就重跑
godot --headless --export-release "Web" ../index.html
```
测试用 URL 参数：`t` 开局秒数、`god=1` 无敌、`hp` 开局血量、`bosshp` Boss 血量、`auto=1` 自动游玩（1 会躲怪的 bot，2 粗心绕圈，3 站着不动）、`order=kill|bean|elite` 指定顾客订单、`pacifist=1` 不开火（测订单超时）、`caf` 开局咖啡因、`skills=ice:3,espresso:2` 开局技能等级、`offer=espresso` 选卡必出。验收测试：`tools_web/order_test.mjs`、`burst_test.mjs`、`blend_test.mjs`。

无头平衡模拟：`cd proto && godot --headless -- --auto=1 --steps=30 --quit=1 --seed=7`

测试面板（手机上测试用）：标题页连点标题「咖啡割草」5 下，或局内连点顶部计时器 5 下（会暂停）。用过测试功能的局 HUD 左上角显示「测试」。验收脚本：`tools_web/admin_test.mjs`。
