extends Node2D
## 咖啡割草 原型 v0.1 —— 单文件实现：拖动走位、自动攻击、咖啡因槽、6 技能、3 敌人 + Boss「周一早晨」。

const SAVE_PATH := "user://coffee_save.cfg"
const RUN_LEN := 600.0
const MAX_ENEMIES := 120
const MAX_BEANS := 220
const MAX_BULLETS := 90
const MAX_FLOATS := 18
const PR := 15.0            # 玩家半径
const PLAYER_SPEED := 165.0
const PLAYER_MAX_HP := 100.0   # 基础值；局外「生命上限」每级 +5
const HEAL_DROP_CHANCE := 0.015  # 击杀掉回血豆的概率
const HEAL_DROP_AMOUNT := 8.0
const HEAL_OFFER_CHANCE := 0.15  # 升级时热拿铁占一个选项的概率
const BOSS_HP_BASE := 1200.0
const BOSS_HP_PER_LV := 60.0     # Boss 血量 = 1200 + 60×进场等级
const CAF_MAX := 45.0       # 咖啡因槽上限（颗豆子）
const JITTER_TIME := 3.0    # 手抖时长
const MAX_LV := 5

const C_BG := Color("#efe2cc")
const C_BG_DOT := Color("#e0ccad")
const C_BROWN := Color("#6b4226")
const C_DARK := Color("#3b2416")
const C_CREAM := Color("#fff6e6")
const C_CAF := Color("#7a4a26")
const C_RED := Color("#c0392b")
const C_XP := Color("#e0a63a")

const SKILL_ORDER := ["espresso", "kettle", "foam", "ice", "grinder", "latte"]
const SKILLS := {
	"kettle": {"name": "手冲壶", "icon": "壶", "color": "#4f9bc7", "desc": "身边每秒转一圈热水。",
		"ups": ["手冲壶多转一股热水。", "手冲壶的热水更烫了。", "手冲壶再多转一股热水。", "手冲壶转得更大更烫。"]},
	"espresso": {"name": "浓缩弹", "icon": "弹", "color": "#5a3520", "desc": "朝最近的敌人射一颗豆子。",
		"ups": ["浓缩弹多射一颗豆子。", "浓缩弹的豆子更痛了。", "浓缩弹再多射一颗豆子。", "浓缩弹的豆子能穿透敌人。"]},
	"foam": {"name": "奶泡盾", "icon": "盾", "color": "#c9a46c", "desc": "每5秒挡住一次伤害。",
		"ups": ["奶泡盾每4秒就能挡一次。", "奶泡盾破时会震开敌人。", "奶泡盾每3秒就能挡一次。", "奶泡盾能叠两层了。"]},
	"ice": {"name": "冰块雨", "icon": "冰", "color": "#69b7d8", "desc": "随机砸下冰块，冻住敌人。",
		"ups": ["冰块雨多砸一块冰。", "冰块冻住敌人更久了。", "冰块雨再多砸一块冰。", "冰块砸中的范围更大。"]},
	"grinder": {"name": "磨豆机", "icon": "磨", "color": "#8a6a4f", "desc": "贴身的敌人会被持续绞伤。",
		"ups": ["磨豆机绞的范围变大。", "磨豆机绞得更狠了。", "磨豆机的范围再变大。", "被绞的敌人会变慢。"]},
	"latte": {"name": "拉花刀", "icon": "刀", "color": "#e07a8a", "desc": "向前划出一道心形刀光。",
		"ups": ["拉花刀的刀光更痛了。", "拉花刀的刀光变得更大。", "拉花刀前后各划一刀。", "拉花刀出刀更快了。"]},
}
const EXTRA := {
	"heal": {"name": "热拿铁", "icon": "血", "color": "#c0392b", "desc": "喝一杯，恢复30点生命。"},
	"coin": {"name": "小费罐", "icon": "币", "color": "#e0a63a", "desc": "立刻多拿20枚金币。"},
}

enum K { WORM, GROUNDS, SMALL, MILK, BOSS }
const ENEMY_NAMES := ["瞌睡虫", "苦渣团", "小苦渣", "过期奶", "周一早晨"]


class Enemy:
	var kind := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var hp := 1.0
	var max_hp := 1.0
	var speed := 40.0
	var r := 12.0
	var dmg := 6.0
	var xp := 1
	var freeze := 0.0
	var slow := 0.0
	var flash := 0.0
	var cd := 0.0
	var kettle_next := 0.0
	var alive := true
	var phase := 0.0
	var state := "chase"
	var atk_i := 0
	var dash_dir := Vector2.RIGHT


# ---------------- 运行状态 ----------------
var font: FontFile
var mode := "title"   # title / play / levelup / pause / result
var rng := RandomNumberGenerator.new()
var vs := Vector2(390, 844)

var t := 0.0
var clock := 0.0      # 真实累计（动画用）
var ppos := Vector2.ZERO
var facing := Vector2.UP
var hp := PLAYER_MAX_HP
var max_hp := PLAYER_MAX_HP
var heals: Array = []
var rerolls := 0
var iframes := 0.0
var hurt_flash := 0.0
var level := 1
var xp := 0
var kills := 0
var pending_levels := 0
var caf := 0.0
var caf_idle := 0.0
var jitter := 0.0
var burst_unlocked := false   # 局外解锁「爆发」的钩子：本原型始终 false
var in_puddle := false
var skills := {}               # id -> level
var options: Array = []
var picker_age := 0.0
var run_win := false
var run_coins := 0
var bonus_coins := 0
var boss_spawned := false
var boss: Enemy = null
var banner := ""
var banner_t := 0.0
var hint_t := 0.0
var minute_waves_done := 0
var spawn_acc := 0.0

var enemies: Array[Enemy] = []
var beans: Array = []
var bullets: Array = []
var spits: Array = []
var puddles: Array = []
var ice_drops: Array = []
var slashes: Array = []
var rings: Array = []
var floats: Array = []

# 武器计时
var esp_cd := 0.5
var kettle_ang := 0.0
var grind_tick := 0.0
var ice_cd := 1.0
var latte_cd := 0.8
var shield := 0
var shield_cd := 0.0

# 局外
var total_coins := 0
var meta := {"hp": 0, "magnet": 0, "reroll": 0}
const SHOP := [
	{"id": "hp", "name": "生命上限", "icon": "血", "color": "#c0392b", "desc": "开局生命上限多加5点。", "max": 5, "base": 30, "step": 20},
	{"id": "magnet", "name": "磁铁范围", "icon": "磁", "color": "#4f9bc7", "desc": "吸豆子的范围变大一成。", "max": 5, "base": 30, "step": 20},
	{"id": "reroll", "name": "重随一次", "icon": "换", "color": "#8a6a4f", "desc": "每局能重随一次升级选项。", "max": 3, "base": 50, "step": 40},
]
var best_time := 0.0

# 输入
var pointer_down := false
var pointer_pos := Vector2.ZERO
var anchor := Vector2.ZERO
var press_target := ""
var last_touch_ms := -10000
var touch_idx := -1
var targets: Array = []

# 测试参数
var opt_start_t := 0.0
var opt_god := false
var opt_auto := false
var opt_bot := 1
var picker_gap := 0.0
var boss_log_t := 0.0
var tip_text := ""
var tip_t := 0.0
var seen_jitter_tip := false
var opt_steps := 1
var opt_quit := false
var opt_hp := -1.0
var opt_boss_hp := -1.0
var state_timer := 0.0
var perf_update := 0.0
var perf_draw := 0.0

var atlas: Texture2D = null
var bg_tile: Texture2D = null
const ATLAS_SCALE := 3.0
const CELL := 128
enum S { WORM, WORM_Z, GROUNDS, MILK, BEAN1, BEAN2, BEAN3, BULLET }
var sb_card: StyleBoxFlat
var sb_btn: StyleBoxFlat
var sb_btn2: StyleBoxFlat
var sb_panel: StyleBoxFlat


func _ready() -> void:
	rng.randomize()
	font = load("res://assets/NotoSansSC-subset.ttf")
	sb_card = _sb(C_CREAM, C_BROWN, 18, 3)
	sb_btn = _sb(C_BROWN, C_DARK, 22, 0)
	sb_btn2 = _sb(Color(1, 1, 1, 0.0), C_BROWN, 18, 2)
	sb_panel = _sb(C_CREAM, C_BROWN, 24, 3)
	_parse_args()
	_load_save()
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_bake()
	print("COFFEE_READY coins=", total_coins)
	if opt_auto:
		_start_run()


func _sb(bg: Color, border: Color, radius: int, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.anti_aliasing = true
	return s


func _parse_args() -> void:
	var qs := ""
	for a in OS.get_cmdline_user_args():
		qs += "&" + str(a).trim_prefix("--")
	if OS.has_feature("web"):
		qs += "&" + str(JavaScriptBridge.eval("window.location.search", true)).trim_prefix("?")
	for part in qs.split("&", false):
		var kv := part.split("=")
		var k := kv[0]
		var v := kv[1] if kv.size() > 1 else "1"
		match k:
			"t": opt_start_t = float(v)
			"god": opt_god = v == "1"
			"auto":
				opt_auto = v != "0"
				opt_bot = int(v)
			"steps": opt_steps = max(1, int(v))
			"quit": opt_quit = v == "1"
			"seed": rng.seed = int(v)
			"hp": opt_hp = float(v)
			"bosshp": opt_boss_hp = float(v)


func _load_save() -> void:
	if OS.has_feature("web"):
		var raw = JavaScriptBridge.eval("localStorage.getItem('coffee_gecao_save') || ''", true)
		var d = JSON.parse_string(str(raw)) if str(raw) != "" else null
		if d is Dictionary:
			total_coins = int(d.get("coins", 0))
			best_time = float(d.get("best_time", 0.0))
			burst_unlocked = bool(d.get("burst_unlocked", false))
			seen_jitter_tip = bool(d.get("seen_jitter_tip", false))
			var sh = d.get("shop", {})
			if sh is Dictionary:
				for k in meta:
					meta[k] = int(sh.get(k, 0))
			return
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		total_coins = int(cf.get_value("meta", "coins", 0))
		best_time = float(cf.get_value("meta", "best_time", 0.0))
		burst_unlocked = bool(cf.get_value("meta", "burst_unlocked", false))
		seen_jitter_tip = bool(cf.get_value("meta", "seen_jitter_tip", false))
		for k in meta:
			meta[k] = int(cf.get_value("shop", k, 0))


func _save() -> void:
	if opt_auto:
		return
	var cf := ConfigFile.new()
	cf.set_value("meta", "coins", total_coins)
	cf.set_value("meta", "best_time", best_time)
	cf.set_value("meta", "burst_unlocked", burst_unlocked)
	cf.set_value("meta", "seen_jitter_tip", seen_jitter_tip)
	for k in meta:
		cf.set_value("shop", k, meta[k])
	cf.save(SAVE_PATH)
	if OS.has_feature("web"):
		# 网页版另存一份到 localStorage（同步写入，刷新页面也不会丢）
		var d := {"coins": total_coins, "best_time": best_time, "burst_unlocked": burst_unlocked, "seen_jitter_tip": seen_jitter_tip, "shop": meta}
		JavaScriptBridge.eval("localStorage.setItem('coffee_gecao_save', %s);" % JSON.stringify(JSON.stringify(d)), true)


# ================= 开局 / 结束 =================
func _start_run() -> void:
	t = opt_start_t
	ppos = Vector2.ZERO
	facing = Vector2.UP
	max_hp = PLAYER_MAX_HP + 5.0 * meta["hp"]
	hp = max_hp if opt_hp <= 0 else opt_hp
	rerolls = meta["reroll"]
	picker_gap = 0.0
	tip_t = 0.0
	heals.clear()
	iframes = 0.0
	level = 1
	xp = 0
	kills = 0
	pending_levels = 0
	caf = 0.0
	caf_idle = 0.0
	jitter = 0.0
	skills = {"espresso": 1}
	run_win = false
	run_coins = 0
	bonus_coins = 0
	boss_spawned = false
	boss = null
	banner = ""
	banner_t = 0.0
	hint_t = 4.0
	minute_waves_done = int(t / 60.0)
	spawn_acc = 0.0
	for arr in [enemies, beans, bullets, spits, puddles, ice_drops, slashes, rings, floats]:
		arr.clear()
	esp_cd = 0.5
	kettle_ang = 0.0
	ice_cd = 1.0
	latte_cd = 0.8
	shield = 0
	shield_cd = 0.0
	pointer_down = false
	mode = "play"
	print("COFFEE_START t=", t)


func _end_run(win: bool) -> void:
	run_win = win
	mode = "result"
	pointer_down = false
	run_coins = int(kills / 10) + int(min(t, RUN_LEN) / 20.0) + (150 if win else 0) + bonus_coins
	total_coins += run_coins
	best_time = max(best_time, t)
	_save()
	print("COFFEE_END win=%s t=%.1f kills=%d level=%d coins=%d skills=%s" % [win, t, kills, level, run_coins, JSON.stringify(skills)])
	if opt_quit:
		get_tree().quit()


# ================= 主循环 =================
func _process(delta: float) -> void:
	vs = get_viewport_rect().size
	var dt: float = min(delta, 0.05)
	clock += dt
	if mode == "play":
		var t0 := Time.get_ticks_usec()
		for i in opt_steps:
			if mode != "play":
				break
			_update(dt if opt_steps == 1 else 1.0 / 60.0)
		perf_update = lerpf(perf_update, float(Time.get_ticks_usec() - t0), 0.1)
	elif mode == "levelup":
		picker_age += dt
		if opt_auto and picker_age > 0.3:
			_pick(rng.randi_range(0, options.size() - 1))
	for f in floats:
		f["t"] -= dt
		f["pos"].y -= 30 * dt
	floats = floats.filter(func(f): return f["t"] > 0)
	if banner_t > 0:
		banner_t -= dt
	if tip_t > 0 and mode == "play":
		tip_t -= dt
	if OS.has_feature("web"):
		state_timer -= delta
		if state_timer <= 0:
			state_timer = 0.2
			_export_state()
	queue_redraw()


func _update(dt: float) -> void:
	t += dt
	hint_t -= dt
	iframes -= dt
	hurt_flash -= dt
	_update_player(dt)
	_update_caffeine(dt)
	_spawn_director(dt)
	_update_enemies(dt)
	_update_weapons(dt)
	_update_projectiles(dt)
	_update_beans(dt)
	enemies = enemies.filter(func(e): return e.alive)
	picker_gap -= dt
	if mode == "play" and pending_levels > 0 and picker_gap <= 0:
		_open_picker()


func _atk_mult() -> float:
	if jitter > 0:
		return 2.0
	return 1.0 + caf / CAF_MAX


func _update_player(dt: float) -> void:
	var dirv := Vector2.ZERO
	if opt_auto:
		dirv = _bot_dir()
	elif pointer_down:
		var d := pointer_pos - anchor
		var l := d.length()
		if l > 70.0:
			anchor = pointer_pos - d / l * 70.0
			d = pointer_pos - anchor
			l = 70.0
		if l > 6.0:
			dirv = d / max(l, 36.0)
	in_puddle = false
	for p in puddles:
		if ppos.distance_squared_to(p["pos"]) < pow(p["r"] + PR * 0.5, 2):
			in_puddle = true
			break
	var sp := PLAYER_SPEED * (0.5 if in_puddle else 1.0)
	ppos += dirv * sp * dt
	if dirv.length() > 0.2:
		facing = dirv.normalized()


func _bot_dir() -> Vector2:
	if opt_bot == 3:
		return Vector2.ZERO
	if opt_bot == 2:
		# 粗心玩家：慢慢绕大圈，不躲怪，只顺路吃豆
		return Vector2(cos(t * 0.25), sin(t * 0.25)) * 0.6
	var away := Vector2.ZERO
	for e in enemies:
		var d := ppos - e.pos
		var l2 := d.length_squared()
		if l2 < 200.0 * 200.0:
			away += d / max(l2, 100.0) * (6.0 if e.kind == K.BOSS else 1.0)
	var circ := Vector2(cos(t * 0.4), sin(t * 0.4))
	var seek := Vector2.ZERO
	var bd := 1e12
	for b in beans:
		var d2: float = ppos.distance_squared_to(b["pos"])
		if d2 < bd:
			bd = d2
			seek = (b["pos"] - ppos).normalized()
	var v := away * 2500.0 + circ * 0.3 + seek * 1.0
	return v.normalized() if v.length() > 0.01 else Vector2.ZERO


func _update_caffeine(dt: float) -> void:
	if jitter > 0:
		jitter -= dt
		caf = CAF_MAX * max(jitter, 0.0) / JITTER_TIME
		if jitter <= 0:
			caf = 0.0
	else:
		caf_idle += dt
		if caf_idle > 2.5:
			caf = max(0.0, caf - 2.0 * dt)


func _gain_caffeine() -> void:
	if jitter > 0:
		return
	caf_idle = 0.0
	caf += 1.0
	if caf >= CAF_MAX:
		caf = CAF_MAX
		_on_caffeine_full()


func _on_caffeine_full() -> void:
	# 钩子：以后局外解锁后，满槽改成「爆发」清屏。
	if burst_unlocked:
		_espresso_burst()
		caf = 0.0
	else:
		jitter = JITTER_TIME
		if not seen_jitter_tip:
			seen_jitter_tip = true
			tip_text = "咖啡喝多了：攻速翻倍，子弹乱喷3秒！"
			tip_t = 3.5
			_save()
		_float(ppos + Vector2(0, -40), "手抖！", C_RED, 22)
		print("COFFEE_JITTER t=%.1f" % t)


func _espresso_burst() -> void:
	# 预留：浓缩冲击，清掉屏幕内的普通敌人。原型里不会触发。
	for e in enemies:
		if e.kind != K.BOSS and _on_screen(e.pos, 0):
			_damage(e, 9999.0)
		elif e.kind == K.BOSS:
			_damage(e, 300.0)
	banner = "浓缩冲击！"
	banner_t = 1.5


# ================= 刷怪 =================
func _spawn_director(dt: float) -> void:
	if t < RUN_LEN:
		var rate := 0.5 + t * 0.015
		spawn_acc += dt * rate
		while spawn_acc >= 1.0:
			spawn_acc -= 1.0
			if enemies.size() < MAX_ENEMIES:
				_spawn(_pick_kind(), _spawn_pos())
		var m := int(t / 60.0)
		if m > minute_waves_done:
			minute_waves_done = m
			print("COFFEE_MIN %d lv=%d kills=%d hp=%.0f enemies=%d beans=%d skills=%s" % [m, level, kills, hp, enemies.size(), beans.size(), JSON.stringify(skills)])
			_minute_wave(m)
	else:
		if boss != null and opt_auto and t - boss_log_t >= 20.0:
			boss_log_t = t
			print("COFFEE_BOSSLOG t=%.0f boss_hp=%.0f dist=%.0f hp=%.0f lv=%d" % [t, boss.hp, boss.pos.distance_to(ppos), hp, level])
		if not boss_spawned:
			boss_spawned = true
			boss_log_t = t
			# 闹钟一响，场上小怪全被吓醒跑掉，留下豆子
			for e in enemies:
				if e.alive:
					e.alive = false
					_drop_bean(e.pos, e.xp)
			boss = _spawn(K.BOSS, ppos + Vector2(0, -vs.y * 0.5 - 70))
			banner = "周一早晨来了！"
			banner_t = 3.0
			print("COFFEE_BOSS t=%.1f lv=%d hp=%.0f boss_hp=%.0f" % [t, level, hp, boss.max_hp])
		spawn_acc += dt * 0.4
		while spawn_acc >= 1.0:
			spawn_acc -= 1.0
			if enemies.size() < 25:
				_spawn(K.WORM if rng.randf() < 0.7 else K.GROUNDS, _spawn_pos())


func _pick_kind() -> int:
	var w_worm := 1.0
	# 越往后苦渣团、过期奶占比越高
	var w_gr := 0.0 if t < 45 else 0.25 + t / 600.0 * 0.6
	var w_milk := 0.0 if t < 120 else 0.12 + t / 600.0 * 0.35
	var milks := 0
	for e in enemies:
		if e.kind == K.MILK:
			milks += 1
	if milks >= 5 + int(t / 100.0):
		w_milk = 0.0
	var x := rng.randf() * (w_worm + w_gr + w_milk)
	if x < w_worm:
		return K.WORM
	if x < w_worm + w_gr:
		return K.GROUNDS
	return K.MILK


func _minute_wave(m: int) -> void:
	var n := 8 + m * 4 + int(m * m * 0.5)
	var dist := vs.length() * 0.5 + 20
	for i in n:
		var a := TAU * i / n
		if enemies.size() < MAX_ENEMIES + 40:
			_spawn(K.WORM, ppos + Vector2(cos(a), sin(a)) * dist)
	banner = "瞌睡虫围上来了！"
	banner_t = 2.0


func _spawn_pos() -> Vector2:
	var a := rng.randf() * TAU
	return ppos + Vector2(cos(a), sin(a)) * (vs.length() * 0.5 + 30)


func _spawn(kind: int, pos: Vector2) -> Enemy:
	var e := Enemy.new()
	e.kind = kind
	e.pos = pos
	e.phase = rng.randf() * TAU
	# 单怪随时间变强：血量、伤害、速度、掉的豆子
	var hm := 1.0 + t / 150.0 + pow(t / 400.0, 2.0)
	var dm := (0.55 + 0.45 * minf(t / 150.0, 1.0)) * (1.0 + t / 500.0)  # 前两分半伤害减轻
	var sm := 1.0 + t / 1500.0
	var xm := 1 + int(t / 200.0)
	match kind:
		K.WORM:
			e.hp = 9 * hm; e.speed = 42; e.r = 12; e.dmg = 5 * dm; e.xp = 1
		K.GROUNDS:
			e.hp = 12 * hm; e.speed = 88; e.r = 12; e.dmg = 7 * dm; e.xp = 2
		K.SMALL:
			e.hp = 5 * hm; e.speed = 105; e.r = 8; e.dmg = 4 * dm; e.xp = 1
		K.MILK:
			e.hp = 20 * hm; e.speed = 70; e.r = 14; e.dmg = 6 * dm; e.xp = 3; e.cd = rng.randf_range(1.2, 2.4)
		K.BOSS:
			e.hp = (BOSS_HP_BASE + BOSS_HP_PER_LV * level) if opt_boss_hp <= 0 else opt_boss_hp; e.speed = 46; e.r = 50; e.dmg = 20; e.xp = 0; e.cd = 2.5
	e.speed *= rng.randf_range(0.9, 1.1)
	if kind != K.BOSS:
		e.speed *= sm
		e.xp *= xm
	e.max_hp = e.hp
	enemies.append(e)
	return e


# ================= 敌人 =================
func _update_enemies(dt: float) -> void:
	var far2 := pow(vs.length() * 0.5 + 220, 2)
	for e in enemies:
		if not e.alive:
			continue
		e.flash -= dt
		e.phase += dt
		var to := ppos - e.pos
		var dist := to.length()
		var dir := to / dist if dist > 0.01 else Vector2.ZERO
		if e.freeze > 0 and e.kind != K.BOSS:
			e.freeze -= dt
			e.pos += e.vel * dt
			e.vel = e.vel.move_toward(Vector2.ZERO, 700 * dt)
			continue
		var mv := dir
		if e.kind == K.MILK:
			if dist > 230:
				mv = dir
			elif dist < 150:
				mv = -dir
			else:
				mv = dir.orthogonal() * (1.0 if int(e.phase) % 6 < 3 else -1.0) * 0.6
			e.cd -= dt
			if e.cd <= 0 and dist < 330:
				e.cd = 2.8
				_spit(e)
		elif e.kind == K.BOSS:
			mv = _boss_update(e, dt, dir)
			if e.state == "chase" and dist > 320.0:
				# 离得远就快步追上来，Boss 战不会变成满地图拉扯
				mv *= 1.0 + clamp((dist - 320.0) / 150.0, 0.0, 3.0)
		var slowf := 0.5 if e.slow > 0 else 1.0
		e.slow -= dt
		e.pos += mv * e.speed * slowf * dt + e.vel * dt
		e.vel = e.vel.move_toward(Vector2.ZERO, 700 * dt)
		if e.kind != K.BOSS and dist * dist > far2:
			# 走太远就绕到玩家前方重新出现
			var a := facing.angle() + rng.randf_range(-1.0, 1.0)
			e.pos = ppos + Vector2(cos(a), sin(a)) * (vs.length() * 0.5 + 20)
		if dist < e.r + PR - 2:
			_hurt(e.dmg)
	_separate()


func _separate() -> void:
	var cell := 32.0
	var grid := {}
	var n := enemies.size()
	for i in n:
		var e := enemies[i]
		var k := Vector2i(int(floorf(e.pos.x / cell)), int(floorf(e.pos.y / cell)))
		if grid.has(k):
			grid[k].append(i)
		else:
			grid[k] = [i]
	for i in n:
		var a := enemies[i]
		if a.kind == K.BOSS:
			continue
		var cx := int(floorf(a.pos.x / cell))
		var cy := int(floorf(a.pos.y / cell))
		for gx in range(cx - 1, cx + 2):
			for gy in range(cy - 1, cy + 2):
				var lst = grid.get(Vector2i(gx, gy))
				if lst == null:
					continue
				for j in lst:
					if j <= i:
						continue
					var b := enemies[j]
					var d := a.pos - b.pos
					var rr := (a.r + b.r) * 0.85
					var l2 := d.length_squared()
					if l2 < rr * rr and l2 > 0.0001:
						var l := sqrt(l2)
						var push := d / l * (rr - l) * 0.5
						if b.kind == K.BOSS:
							a.pos += push * 2.0
						else:
							a.pos += push
							b.pos -= push


func _boss_update(e: Enemy, dt: float, dir: Vector2) -> Vector2:
	match e.state:
		"chase":
			e.cd -= dt
			if e.cd <= 0:
				e.atk_i += 1
				if e.atk_i % 3 == 0:
					for i in 4:
						var a := TAU * i / 4.0
						_spawn(K.WORM, e.pos + Vector2(cos(a), sin(a)) * 80)
				if e.atk_i % 2 == 0:
					e.state = "tele_ring"
					e.cd = 0.9
				else:
					e.state = "tele_dash"
					e.cd = 0.85
					e.dash_dir = dir
			return dir
		"tele_ring":
			e.cd -= dt
			if e.cd <= 0:
				rings.append({"pos": e.pos, "r": e.r, "hit": false})
				e.state = "chase"
				e.cd = 3.0
			return Vector2.ZERO
		"tele_dash":
			e.cd -= dt
			if e.cd <= 0:
				e.state = "dash"
				e.cd = 0.6
			return Vector2.ZERO
		"dash":
			e.cd -= dt
			if e.cd <= 0:
				e.state = "chase"
				e.cd = 2.6
			return e.dash_dir * 12.0   # 46 * 12 ≈ 550 px/s
	return dir


func _spit(e: Enemy) -> void:
	var target := ppos + Vector2(rng.randf_range(-20, 20), rng.randf_range(-20, 20))
	var d := (target - e.pos)
	spits.append({"pos": e.pos, "vel": d.normalized() * 170.0, "target": target, "life": d.length() / 170.0})


func _hurt(dmg: float) -> void:
	if opt_god or iframes > 0 or mode != "play":
		return
	if shield > 0:
		shield -= 1
		shield_cd = _foam_cd()
		iframes = 0.5
		_float(ppos + Vector2(0, -36), "挡住！", Color("#4f9bc7"), 18)
		if skills.get("foam", 0) >= 3:
			for e in enemies:
				var d := e.pos - ppos
				if d.length() < 110 and e.kind != K.BOSS:
					e.vel += d.normalized() * 420
					_damage(e, 12.0)
		return
	hp -= dmg
	iframes = 0.8 if t < 120 else 0.6
	hurt_flash = 0.25
	if hp <= 0:
		hp = 0
		_end_run(false)


func _damage(e: Enemy, dmg: float, knock_dir := Vector2.ZERO, knock := 0.0) -> void:
	if not e.alive:
		return
	e.hp -= dmg
	e.flash = 0.08
	if e.kind != K.BOSS and knock > 0:
		e.vel += knock_dir * knock
	if floats.size() < MAX_FLOATS and _on_screen(e.pos, 0):
		_float(e.pos + Vector2(rng.randf_range(-6, 6), -e.r - 4), str(int(round(dmg))), C_CREAM, 13)
	if e.hp <= 0:
		_kill(e)


func _kill(e: Enemy) -> void:
	e.alive = false
	kills += 1
	if e.kind == K.BOSS:
		boss = null
		_end_run(true)
		return
	_drop_bean(e.pos, e.xp)
	var hc: float = lerpf(0.06, HEAL_DROP_CHANCE, clamp((t - 90.0) / 150.0, 0.0, 1.0))  # 前1.5分钟6%，到4分钟降到1.5%
	if rng.randf() < hc and heals.size() < 6:
		heals.append({"pos": e.pos + Vector2(8, 0)})
	if e.kind == K.GROUNDS:
		for s in [-1, 1]:
			var c := _spawn(K.SMALL, e.pos + Vector2(s * 10, 0))
			c.vel = Vector2(s * 160, rng.randf_range(-60, 60))


# ================= 武器 =================
func _foam_cd() -> float:
	return [5.0, 4.0, 4.0, 3.0, 3.0][skills.get("foam", 1) - 1]


func _update_weapons(dt: float) -> void:
	var am := _atk_mult()
	# 浓缩弹
	var lv: int = skills.get("espresso", 0)
	if lv > 0:
		esp_cd -= dt * am
		if esp_cd <= 0:
			var n: int = [1, 2, 2, 3, 3][lv - 1]
			var dmg: float = [10, 11, 17, 18, 20][lv - 1]
			var pierce := 1 if lv >= 5 else 0
			var tgt := _nearest(420.0)
			if jitter > 0 or tgt != null:
				esp_cd = 0.65
				var base := (tgt.pos - ppos).angle() if tgt != null else 0.0
				var shots := n
				if jitter > 0:
					# 手抖：失控但更猛——一圈散射 n+4 颗，方向带随机
					shots = n + 4
					base = rng.randf() * TAU
				for i in shots:
					var a := base + (i - (n - 1) * 0.5) * 0.16
					if jitter > 0:
						a = base + TAU * i / shots + rng.randf_range(-0.2, 0.2)
					if bullets.size() < MAX_BULLETS:
						bullets.append({"pos": ppos, "vel": Vector2(cos(a), sin(a)) * 430.0, "dmg": dmg, "pierce": pierce, "life": 1.1, "hits": []})
			else:
				esp_cd = 0.1
	# 手冲壶
	lv = skills.get("kettle", 0)
	if lv > 0:
		kettle_ang += dt * TAU * (0.6 + 0.4 * am)
		var n: int = [1, 2, 2, 3, 3][lv - 1]
		var dmg: float = [8, 8, 12, 12, 16][lv - 1]
		var rad: float = [64, 64, 64, 64, 84][lv - 1]
		for i in n:
			var a := kettle_ang + TAU * i / n
			var p := ppos + Vector2(cos(a), sin(a)) * rad
			for e in enemies:
				if e.alive and clock >= e.kettle_next and p.distance_squared_to(e.pos) < pow(e.r + 11, 2):
					e.kettle_next = clock + 0.45
					_damage(e, dmg, (e.pos - ppos).normalized(), 140)
	# 磨豆机
	lv = skills.get("grinder", 0)
	if lv > 0:
		grind_tick -= dt
		if grind_tick <= 0:
			grind_tick = 0.25
			var rad: float = _grind_r()
			var dps: float = [10, 10, 18, 18, 18][lv - 1]
			for e in enemies:
				if e.alive and ppos.distance_squared_to(e.pos) < pow(rad + e.r, 2):
					_damage(e, dps * 0.25 * (0.5 if e.kind == K.BOSS else 1.0))
					if lv >= 5:
						e.slow = 0.5
	# 冰块雨
	lv = skills.get("ice", 0)
	if lv > 0:
		ice_cd -= dt * am
		if ice_cd <= 0:
			ice_cd = 2.6
			var n: int = [1, 2, 2, 3, 3][lv - 1]
			var cands: Array = []
			for e in enemies:
				if e.alive and _on_screen(e.pos, -20):
					cands.append(e)
			for i in n:
				var p: Vector2
				if cands.size() > 0:
					p = cands[rng.randi() % cands.size()].pos
				else:
					p = ppos + Vector2(rng.randf_range(-150, 150), rng.randf_range(-250, 250))
				ice_drops.append({"pos": p, "t": 0.45, "boom": 0.0, "r": 54.0 if lv >= 5 else 40.0, "freeze": 2.2 if lv >= 3 else 1.2})
	# 拉花刀
	lv = skills.get("latte", 0)
	if lv > 0:
		latte_cd -= dt * am
		if latte_cd <= 0:
			latte_cd = 1.0 if lv >= 5 else 1.5
			var dir := facing
			if jitter > 0:
				var a := rng.randf() * TAU
				dir = Vector2(cos(a), sin(a))
			_slash(dir, lv)
			if lv >= 4:
				_slash(-dir, lv)
	# 奶泡盾
	lv = skills.get("foam", 0)
	if lv > 0:
		var mx := 2 if lv >= 5 else 1
		if shield < mx:
			shield_cd -= dt
			if shield_cd <= 0:
				shield += 1
				shield_cd = _foam_cd()


func _grind_r() -> float:
	return [50, 62, 62, 76, 76][skills.get("grinder", 1) - 1]


func _latte_range(lv: int) -> float:
	return 130.0 if lv >= 3 else 100.0


func _slash(dir: Vector2, lv: int) -> void:
	var rng_r := _latte_range(lv)
	var dmg: float = 30.0 if lv >= 2 else 22.0
	slashes.append({"dir": dir, "t": 0.3, "range": rng_r})
	for e in enemies:
		if not e.alive:
			continue
		var d := e.pos - ppos
		var l := d.length()
		if l < rng_r + e.r and (l < e.r + PR or abs(dir.angle_to(d)) < 1.2):
			_damage(e, dmg, d / max(l, 1.0), 220)


func _nearest(maxd: float) -> Enemy:
	var best: Enemy = null
	var bd := maxd * maxd
	for e in enemies:
		if not e.alive:
			continue
		var d := ppos.distance_squared_to(e.pos)
		if d < bd:
			bd = d
			best = e
	return best


func _update_projectiles(dt: float) -> void:
	for b in bullets:
		b["pos"] += b["vel"] * dt
		b["life"] -= dt
		for e in enemies:
			if not e.alive or b["hits"].has(e):
				continue
			if b["pos"].distance_squared_to(e.pos) < pow(e.r + 5, 2):
				_damage(e, b["dmg"], b["vel"].normalized(), 90)
				b["hits"].append(e)
				b["pierce"] -= 1
				if b["pierce"] < 0:
					b["life"] = 0
					break
	bullets = bullets.filter(func(b): return b["life"] > 0)
	for s in spits:
		s["pos"] += s["vel"] * dt
		s["life"] -= dt
		if s["pos"].distance_squared_to(ppos) < pow(PR + 7, 2):
			_hurt(8.0 * (1.0 + t / 600.0))
			s["life"] = -1.0
		elif s["life"] <= 0:
			if puddles.size() >= 14:
				puddles.pop_front()
			puddles.append({"pos": s["pos"], "t": 4.0, "r": 34.0})
	spits = spits.filter(func(s): return s["life"] > 0)
	for p in puddles:
		p["t"] -= dt
	puddles = puddles.filter(func(p): return p["t"] > 0)
	for d in ice_drops:
		if d["t"] > 0:
			d["t"] -= dt
			if d["t"] <= 0:
				d["boom"] = 0.25
				for e in enemies:
					if e.alive and d["pos"].distance_squared_to(e.pos) < pow(d["r"] + e.r, 2):
						if e.kind == K.BOSS:
							e.slow = d["freeze"]
						else:
							e.freeze = d["freeze"]
						_damage(e, 14.0)
		else:
			d["boom"] -= dt
	ice_drops = ice_drops.filter(func(d): return d["t"] > 0 or d["boom"] > 0)
	for s in slashes:
		s["t"] -= dt
	slashes = slashes.filter(func(s): return s["t"] > 0)
	for r in rings:
		r["r"] += 240.0 * dt
		var dd: float = ppos.distance_to(r["pos"])
		if not r["hit"] and abs(dd - r["r"]) < 14.0 + PR * 0.5:
			r["hit"] = true
			_hurt(18.0)
	rings = rings.filter(func(r): return r["r"] < 560.0)


# ================= 豆子 / 经验 =================
func _drop_bean(pos: Vector2, v: int) -> void:
	if beans.size() >= MAX_BEANS:
		var b = beans[rng.randi() % beans.size()]
		b["v"] += v
		return
	beans.append({"pos": pos + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 4)), "v": v, "pull": false})


func _update_beans(dt: float) -> void:
	var magnet: float = 95.0 * (1.0 + 0.1 * meta["magnet"])
	var hk: Array = []
	for h in heals:
		var dh: Vector2 = ppos - h["pos"]
		var lh := dh.length()
		if lh < magnet:
			h["pos"] += dh / max(lh, 0.01) * min(lh, 420.0 * dt)
		if lh < PR + 8:
			hp = min(max_hp, hp + HEAL_DROP_AMOUNT)
			_float(ppos + Vector2(0, -34), "+%d" % int(HEAL_DROP_AMOUNT), Color("#2e9e5b"), 18)
		else:
			hk.append(h)
	heals = hk
	var keep: Array = []
	for b in beans:
		var d: Vector2 = ppos - b["pos"]
		var l := d.length()
		if l < magnet:
			b["pull"] = true
		if b["pull"]:
			b["pos"] += d / max(l, 0.01) * min(l, 420.0 * dt)
		if l < PR + 6:
			xp += int(b["v"])
			_gain_caffeine()
			while xp >= _xp_need(level + pending_levels):
				xp -= _xp_need(level + pending_levels)
				pending_levels += 1
		else:
			keep.append(b)
	beans = keep


func _xp_need(l: int) -> int:
	return 10 + l * 3 + int(l * l * 0.08)  # 前几级更慢，后期比旧曲线快


func _open_picker() -> void:
	var pool: Array = []
	for id in SKILL_ORDER:
		if skills.get(id, 0) < MAX_LV:
			pool.append(id)
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	options = pool.slice(0, 3)
	if options.size() == 3 and hp < max_hp and rng.randf() < HEAL_OFFER_CHANCE:
		options[2] = "heal"
	if options.size() < 3:
		for x in ["heal", "coin"]:
			if options.size() < 3:
				options.append(x)
	mode = "levelup"
	picker_age = 0.0
	pointer_down = false
	print("COFFEE_LEVELUP level=", level + 1, " options=", options)


func _pick(i: int) -> void:
	if i < 0 or i >= options.size():
		return
	var id: String = options[i]
	if id == "heal":
		hp = min(max_hp, hp + 30)
	elif id == "coin":
		bonus_coins += 20
	else:
		skills[id] = skills.get(id, 0) + 1
		if id == "foam" and skills[id] == 1:
			shield = 1
			shield_cd = _foam_cd()
	level += 1
	pending_levels -= 1
	print("COFFEE_PICK ", id, " -> ", skills.get(id, 0), " level=", level)
	picker_gap = 4.0  # 升级之间至少隔 4 秒，积压的升级排队
	mode = "play"


func _float(pos: Vector2, text: String, col: Color, size: int) -> void:
	if floats.size() >= MAX_FLOATS:
		floats.pop_front()
	floats.append({"pos": pos, "text": text, "t": 0.6, "col": col, "size": size})


func _on_screen(p: Vector2, margin: float) -> bool:
	var d := p - ppos
	return abs(d.x) < vs.x * 0.5 + margin and abs(d.y) < vs.y * 0.5 + margin


# ================= 输入 =================
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		last_touch_ms = Time.get_ticks_msec()
		if event.pressed and touch_idx < 0:
			touch_idx = event.index
			_pointer(true, event.position)
		elif not event.pressed and event.index == touch_idx:
			touch_idx = -1
			_pointer(false, event.position)
	elif event is InputEventScreenDrag:
		last_touch_ms = Time.get_ticks_msec()
		if event.index == touch_idx:
			_pointer_move(event.position)
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT or event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if Time.get_ticks_msec() - last_touch_ms < 600:
			return
		_pointer(event.pressed, event.position)
	elif event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION or Time.get_ticks_msec() - last_touch_ms < 600:
			return
		if pointer_down:
			_pointer_move(event.position)


func _pointer(pressed: bool, pos: Vector2) -> void:
	if pressed:
		press_target = _target_at(pos)
		if mode == "play":
			pointer_down = true
			pointer_pos = pos
			anchor = pos
		elif mode == "pause":
			mode = "play"
	else:
		pointer_down = false
		var tg := _target_at(pos)
		if tg != "" and tg == press_target:
			_activate(tg)
		press_target = ""


func _pointer_move(pos: Vector2) -> void:
	pointer_pos = pos


func _target_at(pos: Vector2) -> String:
	for tg in targets:
		if (tg["rect"] as Rect2).has_point(pos):
			return tg["name"]
	return ""


func _activate(name: String) -> void:
	print("COFFEE_TAP ", name, " mode=", mode)
	match name:
		"start", "again":
			if mode == "title" or mode == "result":
				_start_run()
		"title":
			if mode == "result":
				mode = "title"
		"reroll":
			if mode == "levelup" and rerolls > 0 and picker_age > 0.3:
				rerolls -= 1
				_open_picker()
		_:
			if mode == "title" and name.begins_with("buy_"):
				_buy(name.substr(4))
			elif mode == "levelup" and name.begins_with("card") and picker_age > 0.3:
				_pick(int(name.substr(4)))


func _shop_price(it: Dictionary) -> int:
	return int(it["base"]) + int(it["step"]) * int(meta[it["id"]])


func _buy(id: String) -> void:
	for it in SHOP:
		if it["id"] != id:
			continue
		var lv: int = meta[id]
		if lv >= int(it["max"]):
			return
		var price := _shop_price(it)
		if total_coins < price:
			banner = "金币不够"
			banner_t = 1.0
			return
		total_coins -= price
		meta[id] = lv + 1
		_save()
		print("COFFEE_BUY ", id, " -> ", meta[id], " coins=", total_coins)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mode == "play" and not opt_auto:
		mode = "pause"
		pointer_down = false


# ================= 绘制 =================
func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	_draw_all()
	perf_draw = lerpf(perf_draw, float(Time.get_ticks_usec() - t0), 0.1)


func _draw_all() -> void:
	targets.clear()
	if mode == "title":
		_draw_title()
		return
	_draw_world()
	_draw_hud()
	match mode:
		"levelup":
			_draw_picker()
		"pause":
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.45))
			_text(vs * Vector2(0.5, 0.45), "暂停中", 34, C_CREAM)
			_text(vs * Vector2(0.5, 0.45) + Vector2(0, 46), "点一下继续", 20, C_CREAM)
		"result":
			_draw_result()


func _text(center: Vector2, s: String, size: int, col: Color, outline := 0, ocol := C_DARK) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := center + Vector2(-w * 0.5, size * 0.36)
	if outline > 0:
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, ocol)
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _text_left(p: Vector2, s: String, size: int, col: Color) -> void:
	draw_string(font, p + Vector2(0, size * 0.36), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _wrap(s: String, size: int, width: float) -> Array:
	var lines: Array = []
	var cur := ""
	for ch in s:
		var nxt := cur + ch
		if font.get_string_size(nxt, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and cur != "":
			# 标点不放行首
			if "，。！？、：；".contains(ch):
				lines.append(nxt)
				cur = ""
				continue
			lines.append(cur)
			cur = ch
		else:
			cur = nxt
	if cur != "":
		lines.append(cur)
	return lines


func _button(name: String, rect: Rect2, label: String, primary := true) -> void:
	draw_style_box(sb_btn if primary else sb_btn2, rect)
	_text(rect.get_center(), label, 26 if primary else 20, C_CREAM if primary else C_BROWN)
	targets.append({"name": name, "rect": rect})


func _draw_cup(c: Vector2, s: float) -> void:
	draw_arc(c + Vector2(s * 0.95, 0), s * 0.42, -1.2, 1.2, 12, C_BROWN, s * 0.18, true)
	draw_circle(c, s, C_CREAM)
	draw_arc(c, s, 0, TAU, 32, C_BROWN, max(2.0, s * 0.13), true)
	draw_circle(c, s * 0.7, Color("#7a4a26"))
	_heart(c + Vector2(0, -s * 0.05), Vector2.UP, s * 0.32, Color(1, 0.95, 0.88, 0.95))


func _draw_title() -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), C_BG)
	_draw_bg_dots(Vector2(clock * 20, clock * 8))
	var cx := vs.x * 0.5
	var cy := vs.y * 0.12
	_draw_cup(Vector2(cx, cy), 40)
	for i in 3:
		var x := cx - 18 + i * 18
		var y := cy - 60 - fmod(clock * 30 + i * 12, 24)
		draw_arc(Vector2(x, y), 6, PI * 0.5, PI * 1.5, 8, Color(0.42, 0.26, 0.15, 0.4), 3, true)
	_text(Vector2(cx, vs.y * 0.235), "咖啡割草", 50, C_DARK)
	_text(Vector2(cx, vs.y * 0.235 + 44), "拖动走位，自动开火，撑过十分钟", 17, C_BROWN)
	var r := Rect2(cx - 120, vs.y * 0.33, 240, 70)
	_button("start", r, "开始")
	var ly := r.end.y + 32
	_coin_icon(Vector2(cx - 52, ly), 11)
	_text_left(Vector2(cx - 34, ly), "金币 %d" % total_coins, 22, C_DARK)
	if best_time > 0:
		_text(Vector2(cx, ly + 28), "最久坚持 %s" % _fmt_time(best_time), 15, C_BROWN)
	# 局外强化
	var y0 := ly + 58
	_text(Vector2(cx, y0), "强化（永久）", 20, C_DARK)
	var rw := vs.x - 32
	var rh := 74.0
	for i in SHOP.size() + 1:
		var rr := Rect2(16, y0 + 22 + i * (rh + 10), rw, rh)
		if i == SHOP.size():
			# 预留：浓缩冲击（满槽爆发）以后在这里解锁
			draw_style_box(_sb(Color(1, 1, 1, 0.35), Color(0.42, 0.26, 0.15, 0.35), 16, 2), rr)
			_text_left(rr.position + Vector2(18, 24), "浓缩冲击", 20, Color(0.42, 0.26, 0.15, 0.55))
			_text_left(rr.position + Vector2(18, 52), "满槽改成清屏爆发，即将开放。", 15, Color(0.42, 0.26, 0.15, 0.55))
			continue
		var it: Dictionary = SHOP[i]
		var lv: int = meta[it["id"]]
		var maxed := lv >= int(it["max"])
		var price := _shop_price(it)
		var can := not maxed and total_coins >= price
		draw_style_box(sb_card, rr)
		targets.append({"name": "buy_" + it["id"], "rect": rr})
		var ic := rr.position + Vector2(36, rh * 0.5)
		draw_circle(ic, 22, Color(it["color"]))
		draw_arc(ic, 22, 0, TAU, 24, C_DARK, 2, true)
		_text(ic, it["icon"], 22, C_CREAM)
		_text_left(rr.position + Vector2(70, 22), "%s  Lv%d/%d" % [it["name"], lv, it["max"]], 19, C_DARK)
		_text_left(rr.position + Vector2(70, 50), it["desc"], 15, C_BROWN)
		var pr := Rect2(rr.end.x - 84, rr.position.y + 17, 72, 40)
		var pcol := C_BROWN if can else Color(0.42, 0.26, 0.15, 0.3)
		draw_style_box(_sb(pcol, Color(0, 0, 0, 0), 12, 0), pr)
		_text(pr.get_center(), "已满" if maxed else str(price), 18, C_CREAM)


func _coin_icon(c: Vector2, r: float) -> void:
	draw_circle(c, r, C_XP)
	draw_arc(c, r, 0, TAU, 20, Color("#a06a12"), 2, true)
	draw_circle(c, r * 0.45, Color("#f6cf6e"))


func _fmt_time(x: float) -> String:
	var s := int(x)
	return "%d:%02d" % [s / 60, s % 60]


func _draw_bg_dots(origin: Vector2) -> void:
	if bg_tile != null:
		# 平铺背景：48x96 世界单位一块（图是 3 倍）
		var o := Vector2(fposmod(origin.x, 48.0), fposmod(origin.y, 96.0))
		draw_set_transform(-o, 0.0, Vector2(1.0 / 3.0, 1.0 / 3.0))
		draw_texture_rect(bg_tile, Rect2(Vector2.ZERO, (vs + Vector2(96, 192)) * 3.0), true)
		draw_set_transform(Vector2.ZERO)
		return
	var step := 48.0
	var x0 := floorf(origin.x / step) * step
	var y0 := floorf(origin.y / step) * step
	var off := -origin
	var y := y0
	while y < origin.y + vs.y + step:
		var x := x0
		while x < origin.x + vs.x + step:
			var odd := int(round(y / step)) % 2 != 0
			draw_circle(Vector2(x + (step * 0.5 if odd else 0.0), y) + off, 3.0, C_BG_DOT)
			x += step
		y += step


func _heart(c: Vector2, dir: Vector2, s: float, col: Color, outline := Color(0, 0, 0, 0)) -> void:
	var pts := PackedVector2Array()
	var perp := dir.orthogonal()
	for i in 28:
		var a := TAU * i / 28.0
		var hx := 16.0 * pow(sin(a), 3)
		var hy := 13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a)
		pts.append(c + dir * (hy / 17.0 * s) + perp * (hx / 17.0 * s))
	draw_colored_polygon(pts, col)
	if outline.a > 0:
		pts.append(pts[0])
		draw_polyline(pts, outline, 3.0, true)


func _draw_world() -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), C_BG)
	var origin := ppos - vs * 0.5
	_draw_bg_dots(origin)
	draw_set_transform(-origin)
	# 地上：奶渍
	for p in puddles:
		var a: float = min(1.0, p["t"]) * 0.55
		draw_circle(p["pos"], p["r"], Color(0.78, 0.86, 0.6, a))
		draw_arc(p["pos"], p["r"], 0, TAU, 24, Color(0.6, 0.7, 0.4, a), 2, true)
	# 磨豆机范围
	var glv: int = skills.get("grinder", 0)
	if glv > 0:
		var gr := _grind_r()
		draw_circle(ppos, gr, Color(0.54, 0.42, 0.31, 0.13))
		for i in 8:
			var a := clock * 3.0 + TAU * i / 8.0
			draw_arc(ppos, gr, a, a + 0.35, 4, Color(0.54, 0.42, 0.31, 0.55), 3, true)
	# 冰块阴影
	for d in ice_drops:
		if d["t"] > 0:
			var k: float = 1.0 - d["t"] / 0.45
			draw_circle(d["pos"], d["r"] * (0.4 + 0.6 * k), Color(0.3, 0.55, 0.7, 0.18 + 0.2 * k))
			var h: float = d["t"] * 300.0
			draw_rect(Rect2(d["pos"] + Vector2(-9, -9 - h), Vector2(18, 18)), Color("#bfe6f5"))
			draw_rect(Rect2(d["pos"] + Vector2(-9, -9 - h), Vector2(18, 18)), Color("#5ea8c8"), false, 2)
		else:
			draw_circle(d["pos"], d["r"], Color(0.75, 0.92, 1.0, d["boom"] * 2.4))
	# 豆子
	for b in beans:
		if _on_screen(b["pos"], 20):
			_bean(b["pos"], int(b["v"]))
	for h in heals:
		if _on_screen(h["pos"], 20):
			draw_circle(h["pos"], 9, Color("#2e9e5b"))
			draw_arc(h["pos"], 9, 0, TAU, 16, C_CREAM, 2, true)
			draw_line(h["pos"] + Vector2(-5, 0), h["pos"] + Vector2(5, 0), C_CREAM, 3)
			draw_line(h["pos"] + Vector2(0, -5), h["pos"] + Vector2(0, 5), C_CREAM, 3)
	# 敌人
	for e in enemies:
		if _on_screen(e.pos, e.r + 30):
			_draw_enemy(e)
	# Boss 冲撞预警
	if boss != null and boss.state == "tele_dash":
		var a: float = 0.2 + 0.2 * sin(clock * 30)
		draw_line(boss.pos, boss.pos + boss.dash_dir * 520, Color(0.75, 0.15, 0.1, a), boss.r * 1.6)
	for r in rings:
		draw_arc(r["pos"], r["r"], 0, TAU, 72, Color(0.75, 0.15, 0.1, 0.75), 10, true)
	# 酸奶弹
	for s in spits:
		draw_circle(s["pos"], 7, Color("#d8e6a6"))
		draw_arc(s["pos"], 7, 0, TAU, 12, Color("#8aa04a"), 2, true)
	# 拉花刀
	for s in slashes:
		var k: float = s["t"] / 0.3
		var sz: float = s["range"] * 0.55
		_heart(ppos + s["dir"] * sz, s["dir"], sz, Color(1.0, 0.56, 0.64, 0.45 * k), Color(1, 1, 1, 0.8 * k))
	# 子弹
	for b in bullets:
		if atlas != null:
			_spr(S.BULLET, b["pos"], 1.0)
		else:
			draw_circle(b["pos"], 5.5, C_DARK)
			draw_arc(b["pos"], 5.5, 0, TAU, 10, C_CREAM, 1.5, true)
	# 手冲壶热水
	var klv: int = skills.get("kettle", 0)
	if klv > 0:
		var n: int = [1, 2, 2, 3, 3][klv - 1]
		var rad: float = [64, 64, 64, 64, 84][klv - 1]
		for i in n:
			var a := kettle_ang + TAU * i / n
			var p := ppos + Vector2(cos(a), sin(a)) * rad
			for j in 3:
				var ta := a - 0.12 * (j + 1)
				draw_circle(ppos + Vector2(cos(ta), sin(ta)) * rad, 8.0 - j * 2.0, Color(0.31, 0.61, 0.78, 0.35 - j * 0.1))
			draw_circle(p, 10, Color("#4f9bc7"))
			draw_circle(p + Vector2(-3, -3), 3.5, Color(1, 1, 1, 0.8))
	# 玩家
	var shake := Vector2.ZERO
	if jitter > 0:
		shake = Vector2(rng.randf_range(-2.5, 2.5), rng.randf_range(-2.5, 2.5))
	var vis := not (iframes > 0 and int(clock * 20) % 2 == 0)
	if vis:
		_draw_cup(ppos + shake, PR)
	if shield > 0:
		draw_arc(ppos, PR + 8, 0, TAU, 32, Color(1, 1, 1, 0.9), 4, true)
		if shield > 1:
			draw_arc(ppos, PR + 13, 0, TAU, 32, Color(1, 1, 1, 0.6), 3, true)
	# 玩家血条
	var hb := Rect2(ppos + Vector2(-20, PR + 8), Vector2(40, 6))
	draw_rect(hb, Color(0, 0, 0, 0.35))
	draw_rect(Rect2(hb.position, Vector2(40 * hp / max_hp, 6)), Color("#d9534f"))
	# 飘字
	for f in floats:
		_text(f["pos"], f["text"], f["size"], f["col"], 4)
	draw_set_transform(Vector2.ZERO)
	if hurt_flash > 0:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.8, 0.1, 0.05, hurt_flash * 0.6))
	# Boss 屏外指示
	if boss != null and not _on_screen(boss.pos, -10):
		var d := (boss.pos - ppos).normalized()
		var c := vs * 0.5 + d * Vector2(vs.x * 0.5 - 30, vs.y * 0.5 - 90).length() * 0.6
		c = c.clamp(Vector2(30, 120), vs - Vector2(30, 90))
		var pts := PackedVector2Array([c + d * 18, c + d.orthogonal() * 12 - d * 8, c - d.orthogonal() * 12 - d * 8])
		draw_colored_polygon(pts, C_RED)


func _bean(p: Vector2, v: int) -> void:
	if atlas != null:
		_spr(S.BEAN1 if v <= 1 else (S.BEAN2 if v <= 3 else S.BEAN3), p, 1.0)
		return
	var col := Color("#b07a4a") if v <= 1 else (Color("#7a4a26") if v <= 3 else Color("#4a2a14"))
	var s := 5.0 if v <= 1 else (6.5 if v <= 3 else 8.0)
	draw_set_transform(p - ppos + vs * 0.5, 0.5, Vector2(1.0, 0.72))
	draw_circle(Vector2.ZERO, s, col)
	draw_line(Vector2(-s * 0.6, -s * 0.3), Vector2(s * 0.6, s * 0.3), Color(1, 0.9, 0.75, 0.8), 1.5)
	draw_set_transform(vs * 0.5 - ppos)


func _draw_enemy(e: Enemy) -> void:
	var p := e.pos
	var fl := e.flash > 0
	var frozen := e.freeze > 0
	if atlas != null and e.kind != K.BOSS:
		var mod := Color(1.9, 1.9, 1.9) if fl else (Color(0.75, 0.92, 1.3) if frozen else Color.WHITE)
		match e.kind:
			K.WORM:
				_spr(S.WORM_Z if int(e.phase * 0.7) % 3 == 0 else S.WORM, p + Vector2(0, sin(e.phase * 6.0) * 1.2), 1.0, mod)
			K.GROUNDS:
				_spr(S.GROUNDS, p, 1.0, mod)
			K.SMALL:
				_spr(S.GROUNDS, p, 0.68, mod)
			K.MILK:
				_spr(S.MILK, p, 1.0, mod)
		if e.hp < e.max_hp and (e.kind == K.MILK or e.kind == K.GROUNDS):
			draw_rect(Rect2(p + Vector2(-12, e.r + 4), Vector2(24, 3)), Color(0, 0, 0, 0.3))
			draw_rect(Rect2(p + Vector2(-12, e.r + 4), Vector2(24 * e.hp / e.max_hp, 3)), C_RED)
		return
	match e.kind:
		K.WORM:
			var col := Color("#9d90bd") if not fl else Color.WHITE
			var d := (ppos - p).normalized()
			var wob := sin(e.phase * 6.0) * 2.0
			draw_circle(p - d * 9 + d.orthogonal() * wob, e.r * 0.75, col.darkened(0.12))
			draw_circle(p, e.r, col)
			# 闭着的眼睛
			draw_line(p + Vector2(-6, -2), p + Vector2(-2, -1), C_DARK, 2)
			draw_line(p + Vector2(2, -1), p + Vector2(6, -2), C_DARK, 2)
			if int(e.phase * 0.7) % 3 == 0:
				_text(p + Vector2(10, -16), "z", 12, Color(0.35, 0.3, 0.5, 0.8))
		K.GROUNDS, K.SMALL:
			var col := Color("#4a2e1d") if not fl else Color.WHITE
			for i in 6:
				var a := TAU * i / 6.0 + e.phase * 2.0
				draw_circle(p + Vector2(cos(a), sin(a)) * e.r * 0.8, e.r * 0.45, col)
			draw_circle(p, e.r * 0.9, col)
			draw_line(p + Vector2(-5, -3) * e.r / 12, p + Vector2(-2, -1) * e.r / 12, C_CREAM, 2)
			draw_line(p + Vector2(5, -3) * e.r / 12, p + Vector2(2, -1) * e.r / 12, C_CREAM, 2)
		K.MILK:
			var col := Color("#eef3e0") if not fl else Color.WHITE
			var rr := Rect2(p + Vector2(-11, -10), Vector2(22, 24))
			draw_rect(rr, col)
			draw_colored_polygon(PackedVector2Array([p + Vector2(-11, -10), p + Vector2(11, -10), p + Vector2(0, -20)]), Color("#9cc27a"))
			draw_rect(rr, Color("#6f8f4e"), false, 2)
			draw_rect(Rect2(p + Vector2(-11, 0), Vector2(22, 6)), Color("#9cc27a"))
			draw_line(p + Vector2(-6, -5), p + Vector2(-2, -4), C_DARK, 2)
			draw_line(p + Vector2(6, -5), p + Vector2(2, -4), C_DARK, 2)
			draw_arc(p + Vector2(0, 10), 4, PI * 1.15, PI * 1.85, 6, C_DARK, 2)
		K.BOSS:
			_draw_boss(e)
	if frozen:
		draw_circle(p, e.r + 3, Color(0.6, 0.85, 1.0, 0.45))
	if e.kind == K.MILK or e.kind == K.GROUNDS:
		if e.hp < e.max_hp:
			draw_rect(Rect2(p + Vector2(-12, e.r + 4), Vector2(24, 3)), Color(0, 0, 0, 0.3))
			draw_rect(Rect2(p + Vector2(-12, e.r + 4), Vector2(24 * e.hp / e.max_hp, 3)), C_RED)


func _draw_boss(e: Enemy) -> void:
	var p := e.pos
	var r := e.r
	if e.state == "tele_ring" or e.state == "tele_dash":
		p += Vector2(rng.randf_range(-4, 4), rng.randf_range(-3, 3))
	var face := Color("#fff1d6") if e.flash <= 0 else Color.WHITE
	# 铃铛
	for s in [-1, 1]:
		var bp := p + Vector2(s * r * 0.62, -r * 0.88)
		draw_circle(bp, r * 0.36, Color("#c0392b"))
		draw_arc(bp, r * 0.36, 0, TAU, 20, C_DARK, 3, true)
	draw_line(p + Vector2(-r * 0.6, -r * 1.12), p + Vector2(r * 0.6, -r * 1.12), C_DARK, 5)
	# 脚
	draw_line(p + Vector2(-r * 0.5, r * 0.8), p + Vector2(-r * 0.75, r * 1.15), C_DARK, 6)
	draw_line(p + Vector2(r * 0.5, r * 0.8), p + Vector2(r * 0.75, r * 1.15), C_DARK, 6)
	draw_circle(p, r, Color("#c0392b"))
	draw_circle(p, r * 0.84, face)
	for i in 12:
		var a := TAU * i / 12.0
		draw_line(p + Vector2(cos(a), sin(a)) * r * 0.7, p + Vector2(cos(a), sin(a)) * r * 0.8, C_DARK, 3)
	var ha := clock * 0.8
	var ma := clock * 6.0
	draw_line(p, p + Vector2(cos(ha), sin(ha)) * r * 0.42, C_DARK, 5)
	draw_line(p, p + Vector2(cos(ma), sin(ma)) * r * 0.62, C_DARK, 3)
	draw_circle(p, 4, C_DARK)
	if e.state == "tele_ring":
		_text(p + Vector2(0, -r * 1.55), "叮铃铃！", 20, C_RED, 5, C_CREAM)


func _draw_hud() -> void:
	# 咖啡因槽
	var bx := 16.0
	var bw := vs.x - 32.0
	var bar := Rect2(bx, 14, bw, 22)
	var sbg := _sb(Color(0.23, 0.14, 0.09, 0.25), C_DARK, 11, 2)
	draw_style_box(sbg, bar)
	var k := caf / CAF_MAX
	if k > 0.01:
		var fc := C_CAF
		if jitter > 0:
			fc = C_RED if int(clock * 10) % 2 == 0 else C_CAF
		draw_style_box(_sb(fc, Color(0, 0, 0, 0), 11, 0), Rect2(bx, 14, max(22.0, bw * k), 22))
	var label := "咖啡因  攻速×%.1f" % _atk_mult()
	if jitter > 0:
		label = "手抖！子弹乱飞"
	_text(bar.get_center(), label, 14, C_CREAM, 3, C_DARK)
	# 经验条
	var need := _xp_need(level + pending_levels)
	draw_rect(Rect2(bx, 42, bw, 6), Color(0, 0, 0, 0.18))
	draw_rect(Rect2(bx, 42, bw * clamp(float(xp) / need, 0.0, 1.0), 6), C_XP)
	# 时间 / 等级 / 击倒
	var tt := _fmt_time(min(t, RUN_LEN))
	_text(Vector2(vs.x * 0.5, 70), tt, 28, C_RED if t >= RUN_LEN else C_DARK, 4, C_CREAM)
	_text_left(Vector2(bx, 68), "Lv %d" % level, 18, C_DARK)
	var ks := "击倒 %d" % kills
	var kw := font.get_string_size(ks, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_text_left(Vector2(vs.x - 16 - kw, 68), ks, 18, C_DARK)
	# Boss 血条
	if boss != null:
		var br := Rect2(30, 96, vs.x - 60, 14)
		draw_rect(br, Color(0, 0, 0, 0.3))
		draw_rect(Rect2(br.position, Vector2(br.size.x * boss.hp / boss.max_hp, 14)), C_RED)
		_text(Vector2(vs.x * 0.5, 122), "周一早晨", 16, C_RED, 3, C_CREAM)
	# 技能栏
	var x := 16.0
	for id in SKILL_ORDER:
		var lv: int = skills.get(id, 0)
		if lv <= 0:
			continue
		var c := Vector2(x + 20, vs.y - 34)
		_icon(c, id, 18)
		_text(c + Vector2(14, 14), str(lv), 13, C_CREAM, 4, C_DARK)
		x += 48
	# 开局提示
	if hint_t > 0:
		var a: float = min(1.0, hint_t)
		_text(Vector2(vs.x * 0.5, vs.y * 0.72), "按住屏幕任意处拖动来走位", 20, Color(0.23, 0.14, 0.09, a), 4, Color(1, 0.96, 0.9, a))
	if tip_t > 0:
		var ta: float = min(1.0, tip_t)
		var tr := Rect2(16, vs.y * 0.36 - 24, vs.x - 32, 48)
		draw_style_box(_sb(Color(0.23, 0.14, 0.09, 0.8 * ta), Color(0, 0, 0, 0), 14, 0), tr)
		_text(tr.get_center(), tip_text, 18, Color(1, 0.96, 0.9, ta))
	if banner_t > 0:
		var a: float = min(1.0, banner_t)
		_text(Vector2(vs.x * 0.5, vs.y * 0.3), banner, 28, Color(0.75, 0.15, 0.1, a), 5, Color(1, 0.96, 0.9, a))
	# 拖动指示（淡淡的圈）
	if pointer_down and mode == "play":
		draw_arc(anchor, 36, 0, TAU, 32, Color(0.23, 0.14, 0.09, 0.25), 3, true)
		draw_circle(anchor + (pointer_pos - anchor).limit_length(36), 12, Color(0.23, 0.14, 0.09, 0.25))


func _icon(c: Vector2, id: String, r: float) -> void:
	var d: Dictionary = SKILLS[id] if SKILLS.has(id) else EXTRA[id]
	draw_circle(c, r, Color(d["color"]))
	draw_arc(c, r, 0, TAU, 24, C_DARK, 2, true)
	_text(c, d["icon"], int(r * 1.05), C_CREAM)


func _draw_picker() -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.1, 0.06, 0.03, 0.6))
	_text(Vector2(vs.x * 0.5, vs.y * 0.17), "升级！选一个", 32, C_CREAM, 5, C_DARK)
	var cw := vs.x - 40
	var ch := 138.0
	var gap := 16.0
	var y0 := vs.y * 0.17 + 44
	for i in options.size():
		var id: String = options[i]
		var r := Rect2(20, y0 + i * (ch + gap), cw, ch)
		draw_style_box(sb_card, r)
		targets.append({"name": "card%d" % i, "rect": r})
		_icon(r.position + Vector2(40, 40), id, 24)
		var lv: int = skills.get(id, 0)
		var d: Dictionary = SKILLS[id] if SKILLS.has(id) else EXTRA[id]
		_text_left(r.position + Vector2(76, 32), d["name"], 26, C_DARK)
		var desc: String
		if SKILLS.has(id):
			# 等级小圆点
			for j in MAX_LV:
				var pc := r.position + Vector2(cw - 110 + j * 19, 32)
				var filled := j < lv
				var is_new := j == lv
				draw_circle(pc, 7, C_XP if is_new else (C_BROWN if filled else Color(0, 0, 0, 0.12)))
			var tag := "新技能" if lv == 0 else "Lv%d→%d" % [lv, lv + 1]
			_text_left(r.position + Vector2(76, 62), tag, 15, C_XP.darkened(0.25) if lv == 0 else C_BROWN)
			desc = d["desc"] if lv == 0 else d["ups"][lv - 1]
		else:
			desc = d["desc"]
		var lines := _wrap(desc, 21, cw - 40)
		for li in min(2, lines.size()):
			_text_left(r.position + Vector2(20, 92 + li * 28), lines[li], 21, C_DARK)
	if rerolls > 0:
		var rb := Rect2(vs.x * 0.5 - 100, y0 + 3 * (ch + gap) + 4, 200, 54)
		draw_style_box(_sb(C_CREAM, C_BROWN, 16, 2), rb)
		_text(rb.get_center(), "重随（剩%d次）" % rerolls, 20, C_BROWN)
		targets.append({"name": "reroll", "rect": rb})


func _draw_result() -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.1, 0.06, 0.03, 0.6))
	var pw := vs.x - 48
	var pr := Rect2(24, vs.y * 0.18, pw, 470)
	draw_style_box(sb_panel, pr)
	var cx := vs.x * 0.5
	var y := pr.position.y
	if run_win:
		_text(Vector2(cx, y + 56), "打败了周一早晨！", 32, C_BROWN)
	else:
		_text(Vector2(cx, y + 56), "困倒了……", 34, C_DARK)
	var rows := [["坚持时间", _fmt_time(t)], ["击倒", str(kills)], ["等级", "Lv %d" % level], ["获得金币", "+%d" % run_coins]]
	for i in rows.size():
		var ry := y + 130 + i * 52
		_text_left(Vector2(pr.position.x + 36, ry), rows[i][0], 22, C_BROWN)
		var vw := font.get_string_size(rows[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		_text_left(Vector2(pr.end.x - 36 - vw, ry), rows[i][1], 26, C_DARK)
		draw_line(Vector2(pr.position.x + 30, ry + 24), Vector2(pr.end.x - 30, ry + 24), Color(0.42, 0.26, 0.15, 0.15), 1)
	_text(Vector2(cx, y + 352), "金币总数 %d" % total_coins, 16, C_BROWN)
	_button("again", Rect2(cx - 120, y + 378, 240, 70), "再来一局")
	_button("title", Rect2(cx - 70, pr.end.y + 18, 140, 48), "回标题", false)


# ================= 图集烘焙 =================
func _bake() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var vp := _bake_vp(Vector2i(CELL * 4, CELL * 2), true, _bake_sprites)
	var vb := _bake_vp(Vector2i(144, 288), false, _bake_bg)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		atlas = ImageTexture.create_from_image(img)
	var img2 := vb.get_texture().get_image()
	if img2 != null and not img2.is_empty():
		bg_tile = ImageTexture.create_from_image(img2)
	vp.queue_free()
	vb.queue_free()
	print("COFFEE_BAKED atlas=", atlas != null, " bg=", bg_tile != null)


func _bake_vp(size: Vector2i, transparent: bool, fn: Callable) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = transparent
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var b := Node2D.new()
	b.set_script(load("res://scripts/baker.gd"))
	b.fn = fn
	vp.add_child(b)
	add_child(vp)
	return vp


func _bake_bg(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(0, 0, 144, 288), C_BG)
	ci.draw_circle(Vector2(36, 36), 9.0, C_BG_DOT, true, -1, true)
	ci.draw_circle(Vector2(108, 180), 9.0, C_BG_DOT, true, -1, true)


func _bake_sprites(ci: CanvasItem) -> void:
	for i in 8:
		ci.draw_set_transform(Vector2((i % 4) * CELL + CELL * 0.5, (i / 4) * CELL + CELL * 0.5), 0.0, Vector2(ATLAS_SCALE, ATLAS_SCALE))
		match i:
			S.WORM, S.WORM_Z:
				var col := Color("#9d90bd")
				ci.draw_circle(Vector2(-8, 5), 9, col.darkened(0.12), true, -1, true)
				ci.draw_circle(Vector2.ZERO, 12, col, true, -1, true)
				ci.draw_line(Vector2(-6, -2), Vector2(-2, -1), C_DARK, 2, true)
				ci.draw_line(Vector2(2, -1), Vector2(6, -2), C_DARK, 2, true)
				if i == S.WORM_Z:
					ci.draw_string(font, Vector2(9, -10), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.35, 0.3, 0.5, 0.85))
			S.GROUNDS:
				var col := Color("#4a2e1d")
				for k in 6:
					var a := TAU * k / 6.0
					ci.draw_circle(Vector2(cos(a), sin(a)) * 9.6, 5.4, col, true, -1, true)
				ci.draw_circle(Vector2.ZERO, 10.8, col, true, -1, true)
				ci.draw_line(Vector2(-5, -3), Vector2(-2, -1), C_CREAM, 2, true)
				ci.draw_line(Vector2(5, -3), Vector2(2, -1), C_CREAM, 2, true)
			S.MILK:
				var rr := Rect2(Vector2(-11, -10), Vector2(22, 24))
				ci.draw_rect(rr, Color("#eef3e0"))
				ci.draw_colored_polygon(PackedVector2Array([Vector2(-11, -10), Vector2(11, -10), Vector2(0, -20)]), Color("#9cc27a"))
				ci.draw_rect(Rect2(Vector2(-11, 0), Vector2(22, 6)), Color("#9cc27a"))
				ci.draw_rect(rr, Color("#6f8f4e"), false, 2)
				ci.draw_line(Vector2(-6, -5), Vector2(-2, -4), C_DARK, 2, true)
				ci.draw_line(Vector2(6, -5), Vector2(2, -4), C_DARK, 2, true)
				ci.draw_arc(Vector2(0, 10), 4, PI * 1.15, PI * 1.85, 6, C_DARK, 2, true)
			S.BEAN1, S.BEAN2, S.BEAN3:
				var col: Color = [Color("#b07a4a"), Color("#7a4a26"), Color("#4a2a14")][i - S.BEAN1]
				var sz: float = [5.0, 6.5, 8.0][i - S.BEAN1]
				ci.draw_set_transform(Vector2((i % 4) * CELL + CELL * 0.5, (i / 4) * CELL + CELL * 0.5), 0.5, Vector2(ATLAS_SCALE, ATLAS_SCALE * 0.72))
				ci.draw_circle(Vector2.ZERO, sz, col, true, -1, true)
				ci.draw_line(Vector2(-sz * 0.6, -sz * 0.3), Vector2(sz * 0.6, sz * 0.3), Color(1, 0.9, 0.75, 0.85), 1.5, true)
			S.BULLET:
				ci.draw_circle(Vector2.ZERO, 5.5, C_DARK, true, -1, true)
				ci.draw_arc(Vector2.ZERO, 5.5, 0, TAU, 16, C_CREAM, 1.5, true)


func _spr(i: int, c: Vector2, sc: float, mod := Color.WHITE) -> void:
	var h := CELL * 0.5 / ATLAS_SCALE * sc
	draw_texture_rect_region(atlas, Rect2(c.x - h, c.y - h, h * 2, h * 2), Rect2((i % 4) * CELL, (i / 4) * CELL, CELL, CELL), mod)


# ================= 测试用状态导出 =================
func _export_state() -> void:
	var tg: Array = []
	for x in targets:
		var r: Rect2 = x["rect"]
		tg.append({"name": x["name"], "rect": [r.position.x, r.position.y, r.size.x, r.size.y]})
	var counts := [0, 0, 0, 0, 0]
	for e in enemies:
		counts[e.kind] += 1
	var st := {
		"mode": mode, "t": snappedf(t, 0.1), "hp": snappedf(hp, 0.1), "level": level, "xp": xp, "kills": kills,
		"enemies": enemies.size(), "kinds": counts, "beans": beans.size(), "caf": snappedf(caf, 0.1), "jitter": jitter > 0,
		"ppos": [snappedf(ppos.x, 0.1), snappedf(ppos.y, 0.1)], "skills": skills, "options": options,
		"boss_hp": boss.hp if boss != null else -1, "boss_state": boss.state if boss != null else "", "total_coins": total_coins, "meta": meta, "rerolls": rerolls, "max_hp": max_hp, "heals": heals.size(), "run_coins": run_coins, "win": run_win,
		"fps": Engine.get_frames_per_second(), "us_update": int(perf_update), "us_draw": int(perf_draw), "vw": vs.x, "vh": vs.y, "targets": tg,
	}
	JavaScriptBridge.eval("window.__coffee=" + JSON.stringify(st) + ";", true)
