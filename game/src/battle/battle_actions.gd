class_name BattleActions
extends RefCounted
## Battle mechanics + their on-map presentation (docs/rules.md §4–§9).

var st: BattleStage
var _counter_depth := 0
var tracing := false              # tests: record each Attack as [attacker slot, defender slot, strikes] in `trace`
var trace: Array = []
var _strikes_done := 0

## Sound ids from the engine (wave player 0x47467a call sites): hit 0x23 / critical 0x24 (0x40437b),
## no-damage 0x1e / 0x1f (0x4043fa), level-up 0x0b (0x4074ff), equipment level-up 0x0d (0x4084db),
## retreat 0x10 (0x441814), vanish 0x11 (0x441be8), appear 0x2a / 0x0f (0x4570ee).
const SE_LEVELUP := "se11"
const SE_EQUIP_UP := "se13"


func _init(s: BattleStage) -> void:
	st = s


func view() -> BattleView:
	return st.view


## t seconds of animation (none under autoplay, or once the stage has left the tree: 回到标题 / a load mid-way).
func wait(t: float) -> void:
	if Game.instant or t <= 0 or not is_instance_valid(st) or not st.is_inside_tree():
		return
	await st.get_tree().create_timer(t).timeout


# ------------------------------------------------------------------ ranges
## Attack range code with unit overrides (0x43f8be, mod 0x4d3417): 怯 → none; 张善相 (204) 枪母子 → 12 and
## 张公瑾 (25) as 神羿骑 (41) 飞将军 → 4, except while a 绝招 runs, which gives 秦琼 (8) range 6 and 伍云召,
## 雄阔海, 姜松, 罗成 (5, 26, 14, 19) the four adjacent cells.
func attack_range_code(u: BUnit) -> int:
	if u.status & BUnit.ST_FEAR:
		return 11
	if not Rules.special_running():
		if Skills.holds("qiangmuzi", u.pid):
			return Skills.num("qiangmuzi", "range")
		if Skills.holds("feijiangjun", u.pid, u):
			return Skills.num("feijiangjun", "range")
	elif Skills.holds("special_range_6", u.pid):
		return Skills.num("special_range_6", "range")
	elif Skills.holds("special_range_adjacent", u.pid):
		return Skills.num("special_range_adjacent", "range")
	if u.has_effect(42):
		return u.effect_value(42)
	var c := u.cls()
	if u.has_effect(21) and c >= 15 and c <= 17:
		return [7, 8, 8][c - 15]
	return int(Game.cls(c).get("attack_range", 0))


func attack_cells(u: BUnit, from: Vector2i) -> Array[Vector2i]:
	return Shapes.range_cells(attack_range_code(u), from, view().map_w, view().map_h)


func can_attack(att: BUnit, def: BUnit, from := Vector2i(-1, -1)) -> bool:
	if from.x < 0:
		from = att.pos
	return attack_cells(att, from).has(def.pos)


func attackable_targets(u: BUnit, from: Vector2i) -> Array[BUnit]:
	var out: Array[BUnit] = []
	for c in attack_cells(u, from):
		var t := st.unit_at(c)
		if t and t.is_enemy_of(u) and t.active():
			out.append(t)
	return out


# ------------------------------------------------------------------ movement
func in_zoc(u: BUnit, c: Vector2i) -> bool:
	if u.has_effect(33):
		return false
	for d in Grid.DIRS:
		var o := st.unit_at(c + d)
		if o and o.is_enemy_of(u):
			return true
	return false


## {cell: remaining_mp} reachable by u; `parents` gets the path tree.
func reachable(u: BUnit, parents: Dictionary = {}, occupied := false) -> Dictionary:
	var w := view().map_w
	var h := view().map_h
	if u.status & BUnit.ST_PARALYSIS:
		return {u.pos: 0}
	var cost := func(c: Vector2i) -> int:
		return Rules.move_cost(u, view().terrain_at(c))
	# 0x438308 floods only when the unit could stand on its own cell (0x43f7cf ≠ 0xff): one a script put on
	# impassable terrain stays where it is
	if cost.call(u.pos) >= 999:
		return {u.pos: u.move_points()}
	var blocked := func(c: Vector2i) -> bool:
		var o := st.unit_at(c, u)
		return o != null and o.is_enemy_of(u) and not (u.flags & BUnit.F_PASS)
	var stop := func(c: Vector2i) -> bool:
		return in_zoc(u, c)
	var r := Grid.reachable(u.pos, u.move_points(), w, h, cost, blocked, stop, parents)
	if occupied:
		return r                 # the whole flood, cells held by other units included (0x438308's move map)
	# cannot end the move on a cell occupied by another unit
	var out := {}
	for c in r:
		var o := st.unit_at(c, u)
		if o == null:
			out[c] = r[c]
	return out


func move_unit(u: BUnit, path: Array[Vector2i]) -> void:
	if path.is_empty():
		return
	var n := u.node
	if n == null:
		u.pos = path[-1]
		return
	n.set_pose(UnitSprite.Pose.WALK, u.dir)
	# 0x44201b: a cell takes 48 / s frames of 50 ms by 武将移动速度 and the family; the walk picture changes
	# halfway through the cell; then the step sound
	var t := Settings.cell_time(u.family())
	n.walk_speed = 2.0 / t
	for c in path:
		var d := Grid.dir_of(c - u.pos)
		u.dir = d
		n.dir = d
		n.queue_redraw()
		if Game.instant:
			n.position = view().cell_pos(c)
		else:
			var tw := n.create_tween()
			tw.tween_property(n, "position", view().cell_pos(c), t)
			await tw.finished
			Audio.se(step_se(u.family(), view().terrain_at(c)))
		u.pos = c
	n.walk_speed = 4.0
	n.set_pose(UnitSprite.Pose.STAND, u.dir)
	u.moved = true
	st.refresh_units()


## The step sound of a cell (0x43f38b): by the terrain entered (2 → SE 27, 7 → 26, 9 / 13 → 29, 10 → 28), else by
## the family: 0 3 7 11 12 13 15 16 17 20 24 → SE 24, 21..23 → SE 25, the others SE 23.
static func step_se(family: int, terrain: int) -> int:
	match terrain:
		2:
			return 27
		7:
			return 26
		9, 13:
			return 29
		10:
			return 28
	if family in [0, 3, 7, 11, 12, 13, 15, 16, 17, 20, 24]:
		return 24
	if family in [21, 22, 23]:
		return 25
	return 23


func face(u: BUnit, target: Vector2i) -> void:
	if target == u.pos:
		return
	u.dir = Grid.dir_of(target - u.pos)
	if u.node:
		u.node.dir = u.dir
		u.node.queue_redraw()


# ------------------------------------------------------------------ attack (§4)
## The combat object's strike counter (0x4927f0 + 0x608): 1 after a strike sequence that ended on its second
## strike. The attack wrapper skips the techniques while it is set.
const STRIKE := 0x492df8

## 【技】 attack techniques (0x4d76d0): the attacker's person, the flag it sets and the banner (0x4d78e2).
const T_LONGYIN := 0x55ac1c      # 龙吟 (杨林): −1 weapon or armour level
const T_FENGWU := 0x55ac20       # 凤舞九天 (宇文成都): area code 2, full damage
const T_FIRST := 0x55ac24        # the defender strikes first: 1 双雷引 (定彦平, 东方伯), 2 抽屉枪 (姜松)
const T_HENGTUI := 0x55ac2c      # 横推八马倒 (新文礼): area code 10
const T_GAIMA := 0x55ac30        # 盖马三锤 (李元霸): three blows around him
const T_GUIMEN := 0x55ac38       # 鬼门刀 (魏文通): 移动 to 0 and 怯
const T_NUMU := 0x55ac4c         # 怒目 (单雄信): drains all MP
const T_SHA := 0x55ac50          # 煞 (尉迟恭): up to three attacks
const T_SHUANGLEI := 0x55ac54    # 双雷引 attacking (定彦平, 东方伯): the target strikes first, then a double counter
const T_DOUBLE := 0x55ac68       # byte: 抽屉枪's forced second strike
## The flag each technique sets; who has it is the skill record's holder (data/skills.json, "technique").
const TECHNIQUES := {"hengtui": T_HENGTUI, "gaima": T_GAIMA, "fengwu": T_FENGWU, "longyin": T_LONGYIN,
	"guimen": T_GUIMEN, "numu": T_NUMU, "sha": T_SHA}
const BANNERS := [[T_LONGYIN, 1, "龙吟"], [T_FENGWU, 1, "凤舞九天"], [T_FIRST, 1, "双雷引"], [T_GAIMA, 1, "盖马三锤"],
	[T_HENGTUI, 1, "横推八马倒"], [T_GUIMEN, 1, "鬼门刀"], [T_NUMU, 1, "怒目"], [T_SHA, 1, "煞"], [T_FIRST, 2, "抽屉枪"]]


## The attack of a command (mod wrapper 0x4d7808; the player's 攻击 0x43db49, the AI's 0x43ac3f / 0x43acf5).
## Unless the last strike sequence ended on a second strike, the attacker may trigger its technique (0x4d76d0,
## chance min(50·士气 / target's 士气, 100) %). Without one (or with 双雷引) the target may strike first instead
## (0x4d74e4, as for 围攻). Then the attack; under 煞 it repeats while both stand and the target countered, up to
## three attacks.
func attack_cmd(att: BUnit, def: BUnit) -> void:
	Mem.w32(T_FIRST, 0)
	Mem.w32(T_DOUBLE, 0)
	if Mem.r8(STRIKE) == 0:
		var trig := _trigger(att, def)
		if not trig or Mem.r32(T_SHUANGLEI) != 0:
			if st.commands._siege_break(def, att):
				var m := BattleCommands.siege_counter(def.pid)
				if m != 0:
					Mem.w32(T_FIRST, m)
				await attack(def, att)
				Mem.w32(T_SHA, 0)
				Mem.w32(T_SHUANGLEI, 0)
				return
	var n := 0
	while true:
		await attack(att, def)
		if n >= 2:
			break
		n += 1
		if Mem.r32(T_SHA) == 0 or att.hp == 0 or def.hp == 0:
			break
		Mem.w32(T_SHA, Mem.r32(T_SHA) + 1)
	Mem.w32(T_SHA, 0)
	Mem.w32(T_SHUANGLEI, 0)


## 0x4d76d0: the attacker's technique, on chance min(50·士气 / target's 士气, 100) % (0x4d75d2).
func _trigger(att: BUnit, def: BUnit) -> bool:
	var flag := 0
	for id in TECHNIQUES:
		if Skills.holds(id, att.pid):
			flag = TECHNIQUES[id]
	if flag == 0 and not Skills.holds("shuanglei", att.pid):
		return false
	if not Rules.chance(mini(att.morale() * 50 / maxi(def.morale(), 1), 100)):
		return false
	Mem.w32(T_SHUANGLEI if flag == 0 else flag, 1)
	return true


## Attack (0x4064f1): the attacker's strikes, then the defender's counterattack (0x40639a). 盖马三锤 replaces the
## strikes and leaves no counterattack.
func attack(att: BUnit, def: BUnit) -> void:
	var counter := _counter_depth > 0
	var whole := await strikes(att, def, true)
	if tracing:
		trace.append([att.slot, def.slot, _strikes_done])
	if whole:
		await counter_attack(att, def)
	if not counter:
		_counter_depth = 0
	st.refresh_units()


## The strikes of one attack, without the counterattack (0x433540; 0x4d2f1e for each unit of a 围攻): a second
## strike on a double. While a 绝招 runs, one strike (0x4335a0). Area and piercing weapons also hit the units of
## the other side that area_code() adds around or behind the target (0x4061fc). `step` = the strike step of
## Attack (0x433373), which shows a technique's banner and clears the technique flags after the first strike.
## Returns false when 盖马三锤 took the strike's place.
func strikes(att: BUnit, def: BUnit, step := false) -> bool:
	var counter := _counter_depth > 0
	var special := Rules.special_running()
	# combat object 0x4927f0 (0x4061fc, for a counterattack too): attacker and defender slot, read by the scripts'
	# 攻防 tests, and the target list at +0x10 (0xff after the last)
	Mem.w8(0x4927f0, att.slot)
	Mem.w8(0x4927f1, def.slot)
	var code := area_code(att)
	var targets: Array[BUnit] = [def]
	targets.append_array(secondary_targets(att, def, code))
	for i in targets.size():
		Mem.w8(Addr.TARGETS + i, targets[i].slot)
	Mem.w8(Addr.TARGETS + targets.size(), 0xff)
	await view().ensure_visible(def.pos)
	face(att, def.pos)
	face(def, att.pos)
	var best_exp := 0
	var weapon_exp := 0
	var total_damage := 0
	var fallen: Array[BUnit] = []
	if not special:
		Mem.w8(STRIKE, 0)
	_strikes_done = 0
	for strike in 2:
		if not def.active() or not att.active():
			break
		_strikes_done += 1
		# 0x405e03: hit and damage for each target; the first one rolls the critical, the others share it
		var hits: Array[bool] = []
		var dmgs: Array[int] = []
		var mps: Array[int] = []
		var alive: Array[bool] = []
		var crit := false
		for i in targets.size():
			var t := targets[i]
			alive.append(t.active())
			var mode := 1 if counter else 0
			if i > 0 and _halved(att, code):
				mode += 2
			var hit := t.active() and Rules.chance(Rules.hit_rate(att, t))
			var dmg := 0
			if hit:
				dmg = Rules.calc_damage(att, t, view().terrain_at(att.pos), view().terrain_at(t.pos), true, mode)
			else:
				dmg = Rules.damage_post(att, t, 0)      # 智将 adds to a miss as well (0x4dc9e0)
			if i == 0:
				if t.hp > 0 and Rules.chance(_crit_rate(att, t, hit)):
					crit = true
					if t.has_effect(57) and not special:
						dmg = 0     # 化解攻击效果; a 绝招's critical is not cancelled (0x4d34c9)
					else:
						dmg = dmg * 3 / 2
			elif crit:
				dmg = dmg * 3 / 2
			if strike == 1 and t.has_effect(57):
				dmg = 0
			dmg = mini(dmg, t.hp)
			hits.append(hit or dmg > 0)
			dmgs.append(dmg)
			mps.append(t.mp if Mem.r32(T_NUMU) == 1 else 0)     # 怒目: the whole MP, hit or not (0x4d8150)
			Mem.w32(Rules.PREV_TARGET, i)
		if step:
			await _technique_banner()
			if Mem.r32(T_GAIMA) == 1:
				await _gaima(att)
				return false
		if crit:
			await _crit_shout(att)
		await _anim_strike(att, targets, hits, dmgs, crit)
		# 0x405889: apply, target by target
		for i in targets.size():
			var t := targets[i]
			await _technique_hit(targets[maxi(i - 1, 0)])
			if (dmgs[i] != 0 or mps[i] != 0) and not t.has_effect(57):
				_on_hit_effects(att, t, targets)
			if Skills.holds("zhang_poison", att.pid) and Mem.r8(Skills.MAP_NO) <= Skills.num("zhang_poison", "map_max"):
				t.status |= BUnit.ST_POISON      # 张善相 (0x4d568d): hit or miss
			var killed := t.hp - dmgs[i] <= 0
			var armor_exp := 0
			if alive[i]:
				# every target, hit or miss (0x406068..0x406160 in 0x405e03): the attacker's experience (0x40379b) and
				# the weapon's (0x40397d) keep their largest values for the end of the attack; the armour of a red
				# wearer gets 0x403a85's at each strike (0x405b7d)
				var damaged := dmgs[i] != 0 or mps[i] != 0
				if att.slot < 15:
					best_exp = maxi(best_exp, _phys_exp(att, t, killed))
					weapon_exp = maxi(weapon_exp, _weapon_gain(att, t, damaged))
				if t.colour == 0:
					armor_exp = _armor_gain(t, att, damaged)
				# the change box before the HP goes (0x405ab8), held longer on a one-target attack (ctx+0x424 = 0)
				await st.hud.gauge(t, att, dmgs[i] if hits[i] else 0, mps[i], 0, 0, armor_exp, code == 0)
			if mps[i] > 0:
				t.mp = maxi(t.mp - mps[i], 0)
			if armor_exp > 0:
				await add_equip_exp(t.person, false, armor_exp)
			if not hits[i]:
				continue
			total_damage += dmgs[i] if i == 0 else 0
			_apply_damage(t, dmgs[i])
			if killed:
				fallen.append(t)
			elif dmgs[i] > 0:
				if Skills.holds("guanshi", t.pid) and Mem.r8(Mem.EV + 4 * Skills.num("guanshi", "ev")) >= Skills.num("guanshi", "min"):
					# 谢映登's 贯石 (0x4da0a7): the damage also comes off his MP (its low byte)
					Mem.w8(t.addr + 0x14, maxi((t.mp & 0xff) - dmgs[i], 0))
				# 笼屉 (effect 62 使用馒头) once the unit is 100 or more below its maximum (mod 0x4d681c)
				if t.hp + 100 <= t.max_hp() and t.has_effect(62):
					await eat_bun(t)
		if step:
			# [T_LONGYIN .. T_GUIMEN], T_NUMU and 0x55ac58 (no technique of this mod uses 0x55ac28 / 0x55ac34 / 0x55ac58)
			for f in range(T_LONGYIN, T_GUIMEN + 4, 4) + [T_NUMU, 0x55ac58]:
				Mem.w32(f, 0)
			if Mem.r32(T_SHA) == 1:
				Mem.w32(T_SHA, 2)
		var again := not special and strike == 0 and _double_check(att, def, counter)
		if step and Mem.r32(T_SHUANGLEI) == 1:
			Mem.w32(T_SHUANGLEI, 2)
		if not again:
			break
		Mem.w8(STRIKE, 1)
		if not def.active() or not att.active():
			break
		if not Game.instant:
			st.hud.popup_number("连击！", att.pos, Color(1, 0.9, 0.3))
	for t in fallen:
		await unit_fell(t)
	# 0x405c6c (mod 0x4d7e01): the attacker's box with the 吸血 heal and the experience, held long, then the HP,
	# the experience (SetExp, 0x405cad) and the weapon's (0x405cc2), once
	var drain := 0
	if att.has_effect(81) and total_damage > 0:
		drain = mini(total_damage / 2, maxi(att.max_hp() - att.hp, 0))
	if att.slot >= 15:
		weapon_exp = 0
	if att.active():
		await st.hud.gauge(att, _last_target(targets), -drain, 0, best_exp, weapon_exp, 0, true)
	att.hp += drain
	if best_exp > 0:
		await gain_exp(att, best_exp, false)
	if weapon_exp > 0:
		await add_equip_exp(att.person, true, weapon_exp)
	return true


## The unit the combat object points at when the attack ends (ctx+1): the last target the apply loop handled.
static func _last_target(targets: Array[BUnit]) -> BUnit:
	return targets[targets.size() - 1] if not targets.is_empty() else null


## DoubleCheck (0x406181 as the mod patches it): 双雷引's second phase forces it on a first strike; no second
## strike after the second; else chance(DoubleRate); else 抽屉枪's flag forces it (the flag is then cleared).
func _double_check(att: BUnit, def: BUnit, counter: bool) -> bool:
	if Mem.r32(T_SHUANGLEI) == 2:
		return true
	if Rules.chance(Rules.double_rate(att, def, counter)):
		return true
	var forced := Mem.r8(T_DOUBLE) == 1
	Mem.w8(T_DOUBLE, 0)
	return forced


## 0x4d78e2: the banner of the technique that is set, over the darkened field.
func _technique_banner() -> void:
	for b in BANNERS:
		if Mem.r32(b[0]) == b[1]:
			await _banner(b[2])
			return


func _banner(name: String) -> void:
	await view().set_dim(true)
	await st.ui.skill_banner(name)
	await view().set_dim(false)


## 龙吟 / 鬼门刀 at the head of the apply loop (0x4d72e0), on the unit the combat object points at, i.e. the
## previous target (the first target twice), unless it has effect 57. 龙吟: chance 50 % the weapon level, else
## the armour level, one lower (a maxed one may gain experience again). 鬼门刀: 移动 to 0, and 怯.
func _technique_hit(t: BUnit) -> void:
	if t.has_effect(57):
		return
	if Mem.r32(T_LONGYIN) == 1:
		var b := t.person.base + (0x2f if Rules.chance(50) else 0x32)
		if Mem.r8(b) != 0:
			Mem.w8(b, Mem.r8(b) - 1)
			if Mem.r8(b + 1) == 0xff:
				Mem.w8(b + 1, 0)
	elif Mem.r32(T_GUIMEN) == 1:
		await st.commands.change_unit(t, 5, 0)
		t.status |= BUnit.ST_FEAR


## 盖马三锤 (0x4d83fe): three blows (0x4d2f1e) at random units of the other side on the 8 cells around the
## attacker (the same one may be hit again), then 怯 and 穷 on the units of the other side within 4 cells
## (0x4d8632), except those with effect 57. The original gathers those into a 15-entry list, the cells on the
## axes twice, and overruns it when more are around; the port stops at 15.
func _gaima(att: BUnit) -> void:
	var around: Array[BUnit] = []
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx != 0 or dy != 0:
				var o := st.unit_on(att.pos + Vector2i(dx, dy))
				if o and (o.slot < 35) != (att.slot < 35):
					around.append(o)
	if not around.is_empty():
		for k in 3:
			await strikes(att, around[Rules.rand(around.size())])
	var enemy_side := att.colour >= 2
	var hit: Array[BUnit] = []
	for dx in 5:
		for dy in 5 - dx:
			for c in [Vector2i(dx, dy), Vector2i(dx, -dy), Vector2i(-dx, -dy), Vector2i(-dx, dy)]:
				var o := st.unit_on(att.pos + c)
				if o and (o.slot < 35) == enemy_side and hit.size() < 15:
					hit.append(o)
	for o in hit:
		if not o.has_effect(57):
			o.status |= BUnit.ST_FEAR | BUnit.ST_SEAL
	Mem.w32(T_GAIMA, 0)
	st.refresh_units()


## AreaAttackCode (0x407818): which other cells an attack hits (the area codes of 0x435d6c). The class table at
## 0x409191 (矛手 classes 6-8 and 锦骑 10-11: the cell behind the target; 无影剑 17: the four around it) is read
## from memory because 秦琼's 回旋杀手锏 patches it for one strike. Then the technique flags, 文士弘 (178) and the
## effects 21 and 43.
func area_code(u: BUnit) -> int:
	if Mem.r32(T_FENGWU) == 1:
		return 2                      # 凤舞九天
	var a := Mem.r8(0x409191 + u.cls())
	if Mem.r8(T_HENGTUI) == 1:
		a = 10                        # 横推八马倒
	elif Mem.r8(Addr.TAPO) == 1:
		a = 12                        # 踏破连营
	if Skills.holds("changying", u.pid):
		a = Skills.num("changying", "area")     # 文士弘 长缨奔破
	if a < 4 and u.has_effect(21) and u.cls() in [15, 16, 17]:
		return 2 if u.cls() == 17 else 1
	if u.has_effect(43):
		a = u.effect_value(43)
	return a


## A secondary target takes half damage (mode bit 2) for the area codes 1-3 and 12 only, the lines and sweeps
## hitting in full; 宇文成都 (33) only for code 1 (mod 0x4d93e5 / 0x4d93af).
func _halved(att: BUnit, code: int) -> bool:
	if Skills.holds("yuwen_halved", att.pid):
		return code == 1
	return (code >= 1 and code <= 3) or code == 12


## The units of the other side an attack on `def` also hits (0x435d6c kind 0), in the original's order: the
## neighbours of the target up, right, down, left, then the diagonals; lines away from the attacker (code 12 to
## the first cell without such a unit); squares row by row; the sweep's two cells beside both; the attacker's own
## neighbours (11).
const NB8 := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1)]
const SWEEP := [[Vector2i(-1, 0), Vector2i(1, 0)], [Vector2i(0, -1), Vector2i(0, 1)], [Vector2i(-1, 0), Vector2i(1, 0)], [Vector2i(0, 1), Vector2i(0, -1)], [Vector2i(-1, 0), Vector2i(0, 1)], [Vector2i(0, -1), Vector2i(-1, 0)], [Vector2i(1, 0), Vector2i(0, -1)], [Vector2i(0, 1), Vector2i(1, 0)]]


func secondary_targets(att: BUnit, def: BUnit, code: int) -> Array[BUnit]:
	var out: Array[BUnit] = []
	var add := func(c: Vector2i) -> bool:
		var t := st.unit_at(c)
		if t and t != def and t.is_enemy_of(att) and not out.has(t):
			out.append(t)
			return true
		return false
	match code:
		1:
			for k in 4:
				add.call(def.pos + NB8[k])
		2, 3, 7:
			for k in 8:
				add.call(def.pos + NB8[k])
		4, 5, 6, 12:
			var d := Vector2i(signi(def.pos.x - att.pos.x), signi(def.pos.y - att.pos.y))
			var c := def.pos
			for k in {4: 1, 5: 5, 6: 2, 12: 0x27}[code]:
				c += d
				if not add.call(c) and code == 12:
					break
		8, 9:
			var r := 4 if code == 8 else 2
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx != 0 or dy != 0:
						add.call(def.pos + Vector2i(dx, dy))
		10:
			var k := NB8.find(def.pos - att.pos)
			if k >= 0:
				for o in SWEEP[k]:
					add.call(def.pos + o)
		11:
			for k in 8:
				add.call(att.pos + NB8[k])
	return out


## Critical rate (0x405d69), rolled for the first target while it stands, hit or not; not while a 绝招 runs
## (0x4d34c9). The mod's side effects (0x4d1d30): 并蒂's hit counters, and 管毅's 轩辕神枪 paralysing an adjacent
## attacker that missed him. 并蒂 (0x4dc7fd): outside a counter, the person in dynamic slot 2 (王君珂) always crits
## while 管毅 is the unit whose move range the player opened last — as a helper in 管毅's 围攻.
func _crit_rate(att: BUnit, t: BUnit, hit: bool) -> int:
	var r := Rules.crit_rate(att, t)
	if Rules.special_running():
		return r
	_bingdi_count(t)
	if not hit and _xuanyuan(att, t):
		att.status |= BUnit.ST_PARALYSIS
	if r < 100 and _counter_depth != 1 and att.pid == Skills.holder("bingdi") \
			and st.range_unit != null and st.range_unit.pid == Skills.num("bingdi", "partner"):
		return 100
	return r


## 并蒂's counters (0x4d1d30): while 王君珂 (dynamic slot 2) and 管毅 are both on the map, a strike on 王君珂
## counts in byte [0x55ee04], one on 管毅 in [0x55ee06]. The phase start copies them to 0x55ee00 (0x4d1e21), and
## a player unit's regeneration clears them (0x43cf75).
func _bingdi_count(t: BUnit) -> void:
	var w := Skills.unit_on_map(Skills.holder("bingdi"))
	var g := Skills.unit_on_map(Skills.num("bingdi", "partner"))
	if w == null or g == null or Skills.distance(w.pos, g.pos) >= 0x9a:
		return
	if t.slot == w.slot:
		Mem.w8(Addr.BINGDI, (Mem.r8(Addr.BINGDI) + 1) & 0xff)
	elif t.slot == g.slot:
		Mem.w8(Addr.BINGDI_GUANYI, (Mem.r8(Addr.BINGDI_GUANYI) + 1) & 0xff)


## 轩辕神枪 (hit check 0x43b504 → 0x4dc924): an attacker on one of the 8 cells around 管毅 that missed him is
## paralysed, once EV[3184] ≥ 1, with chance EV[2700] (doubled from EV[3184] ≥ 3), while he carries the spear (23).
## No script sets EV[2700], so it never happens in the shipped game.
func _xuanyuan(att: BUnit, t: BUnit) -> bool:
	if not Skills.holds("xuanyuan", t.pid) or absi(t.pos.x - att.pos.x) > 1 or absi(t.pos.y - att.pos.y) > 1:
		return false
	var lv := Mem.r8(Mem.EV + 4 * Skills.num("xuanyuan", "ev"))
	if lv == 0 or not Rules.chance(Mem.ev(Skills.num("xuanyuan", "chance_ev")) * (2 if lv >= 3 else 1)):
		return false
	return t.person.weapon == Skills.num("xuanyuan", "weapon")


## Counterattack (0x40639a): a defender left standing and not confused hits back when the attacker is in its
## range and lacks effect 44; a counter is answered once more only when the one it hits (the defender of the
## counter, ctx+1: the first attacker, or 围攻's leader) has effect 40. In 双雷引's second phase the banner comes
## first (0x4d7a11). Without a counter, 煞 stops repeating (0x433610).
func counter_attack(att: BUnit, def: BUnit) -> void:
	var depth := _counter_depth
	if not (depth == 0 or (depth == 1 and def.has_effect(40))):
		return
	Mem.w8(PREFERRED, att.slot)      # 0x406431, for the range test 0x436586
	if def.active() and att.active() and not (def.status & BUnit.ST_CONFUSION) and not att.has_effect(44) \
			and can_attack(def, att):
		_counter_depth += 1
		if Mem.r32(T_SHUANGLEI) == 2:
			await _banner("双雷引")
		await attack(def, att)
		_counter_depth -= 1
	else:
		Mem.w32(T_SHA, 0)


## [0x4b2c28]: the unit 0x436586 returns when it is among the units it collects (the AI's choice target; the
## attacker in the counterattack's range test, 0x406431; the striker in 0x4d7551).
const PREFERRED := 0x4b2c28


## 引导攻击 (effect 46) after a kill: the next target in reach of the attacker's cell (0x436586 with the attack range
## code): of the living units of the other side group on the range's cells in its order, the one in [0x4b2c28]
## if it is there, else the last; null if none.
func guided_target(u: BUnit) -> BUnit:
	var found: BUnit = null
	for c in Shapes.range_seq(attack_range_code(u), u.pos, view().map_w, view().map_h):
		var x := st.unit_on(c)
		if x == null or (x.slot < 35) == (u.slot < 35) or x.hp == 0:
			continue
		found = x
		if x.slot == Mem.r8(PREFERRED):
			break
	return found


## The attacker's line before a critical strike (0x405821): with chance 25 %, while a 绝招 runs always, except
## 程咬金 (pid 1) never. The 21 persons of table 0x48b230 have their own line (text 700 + index); the others
## one of three lines of their group (person +0x26): text 721 + 3·group + rand(3). Said in a portrait window.
const SHOUT_PIDS := [0, 1, 2, 5, 7, 8, 9, 13, 14, 15, 16, 17, 19, 22, 24, 32, 33, 34, 67, 86, 116]


func _crit_shout(att: BUnit) -> void:
	var roll := Rules.chance(25)
	if Rules.special_running():
		if Skills.holds("sanbanfu", att.pid):
			return
	elif not roll:
		return
	var k := SHOUT_PIDS.find(att.pid)
	if k < 0:
		k = 21 + 3 * Mem.r8(att.person.base + 0x26) + Rules.rand(3)
	await st.unit_say(att.pid, Game.text(700 + k).replace("\\n", "\n"))


func _phys_exp(a: BUnit, t: BUnit, killed: bool) -> int:
	var la := a.level()
	var lt := t.level()
	var e := 0
	if killed:
		e = Rules.kill_exp(la, lt)
		if t.pid == st.boss_pid:
			e *= 2
	else:
		e = mini((lt - la) * 2 + 8, 100) if la < lt else maxi(Rules.sat_sub(8, la - lt), 1)
	return e * exp_mult(a) / 100


func exp_mult(u: BUnit) -> int:
	return 100 + u.person.equip_bonus(8)


## The statuses a strike with damage gives target `def` (0x405889; not to a target with effect 57, 0x4d724c), in
## the original's order, which is that of its rolls: effect 35 and 玄术骑 (50) 混乱, effect 36 中毒, 力士 (45) 麻痹,
## effect 37's six statuses, 李世民's 梦魇 (67, 0x4d8caf: 迷失 on the targets of the strike in order, up to the
## first of a higher level), 震天骑 (38) 迷失, effect 34 麻痹 (cave 0x40913d), effect 38 穷计.
func _on_hit_effects(att: BUnit, def: BUnit, targets: Array[BUnit]) -> void:
	var c := att.cls()
	if att.has_effect(35) and Rules.chance(60):
		def.status |= BUnit.ST_CONFUSION
	if c == 50 and Rules.chance(60):
		def.status |= BUnit.ST_CONFUSION
	if att.has_effect(36):
		def.status |= BUnit.ST_POISON
	if c == 45 and Rules.chance(60):
		def.status |= BUnit.ST_PARALYSIS
	if att.has_effect(37):
		_random_statuses(att, def)
	if Skills.holds("mengyan", att.pid):
		for t in targets:
			if t.level() > att.level():
				break
			t.status |= BUnit.ST_LOST
	if c == 38 and Rules.chance(60):
		def.status |= BUnit.ST_LOST
	if att.has_effect(34) and Rules.chance(60):
		def.status |= BUnit.ST_PARALYSIS
	if att.has_effect(38):
		def.status |= BUnit.ST_SEAL


## Effect 37 随机属性攻击 (mod 0x4d0c6e): six rolls, each on (L·a + b) mod 256 % with L the attacker's weapon level:
## 麻痹 5L+15, 穷计 4L+4, 混乱 L+1, 中毒 L+6, 怯力 2L+2, 迷失 3L+3 (tables 0x4d0b60 / 0x4d0b68 / 0x4d0b70).
func _random_statuses(att: BUnit, def: BUnit) -> void:
	var lv := att.person.weapon_lvl
	for k in 6:
		if Rules.chance((lv * [5, 4, 1, 1, 2, 3][k] + [15, 4, 1, 6, 2, 3][k]) & 0xff):
			def.status |= [BUnit.ST_PARALYSIS, BUnit.ST_SEAL, BUnit.ST_CONFUSION, BUnit.ST_POISON, BUnit.ST_FEAR, BUnit.ST_LOST][k]


func _apply_damage(u: BUnit, dmg: int) -> void:
	u.hp = maxi(u.hp - dmg, 0)
	if u.hp == 0:
		u.extra["dying"] = true     # keeps the sprite for the defeat animation
	st.refresh_units()


## The map attack animation (0x4044e9): 23 steps of one tick (50 ms), each running a case of the switch at
## 0x40465d; steps 0..21 take their case from a table (0x42beae): attacker 管毅 (0) or 张善相 (204) → 0x42bef2 (a
## wind-up shake first), else while 尽命三锤 runs ([0x4d352e] = 1) → 0x42bf08 (three strikes), else 0x40572e.
## Cases: 0 the standing frame, 1 / 3 attack frame 0 / 1, 2 the wind-up (frame 0, an archer frame 1 and 8 ticks
## more; on a critical SE 33 and 6 ticks of growing glow), 10 the swing sound (SE 37 − table 0x4400df[family]),
## 4 the strike (frame 2; the target flashed, SE 35 / 30 for damage / none, +1 on a critical), 5 frame 3 with the
## target flashed again (yellow on a critical, 0x43053e), 6 and 7 frame 3 with the target's plain reaction, 8 the
## end, 9 nothing. The numbers and the reaction poses are the port's.
const ANIM_TABLE := 0x40572e
const ANIM_TABLE_WINDUP := 0x42bef2
const ANIM_TABLE_TRIPLE := 0x42bf08
const TRIPLE_STRIKE := 0x4d352e
const ANIM_TICK := 0.05


static func anim_table(att: BUnit) -> int:
	if Skills.holds("windup", att.pid):
		return ANIM_TABLE_WINDUP
	return ANIM_TABLE_TRIPLE if Mem.r8(TRIPLE_STRIKE) == 1 else ANIM_TABLE


## 0x4400a2: table 0x4400df by family (0 for the archers 弓兵, 弓骑兵 and 箭车; 0 past family 26).
static func swing_kind(att: BUnit) -> int:
	var f := att.family()
	return Mem.r8(0x4400df + f) if f >= 0 and f <= 0x1a else 0


func _anim_strike(att: BUnit, targets: Array[BUnit], hits: Array[bool], dmgs: Array[int], crit: bool) -> void:
	if Game.instant:
		return
	var table := anim_table(att)
	var archer := swing_kind(att) == 0
	var damaged := not targets.is_empty() and hits[0] and dmgs[0] > 0
	var shown := false
	for i in 23:
		var c := Mem.r8(table + i) if i < 22 else 9
		var n := att.node
		match c:
			0:
				if n:
					n.attack_frame(att.dir, -1)
			1, 3:
				if n:
					n.attack_frame(att.dir, 0 if c == 1 else 1)
			2:
				if n:
					n.attack_frame(att.dir, 1 if archer else 0)
				if crit:
					Audio.play_se("se33")
					for k in 6:
						await wait(ANIM_TICK)
						if n:
							n.flash = (k / 2 + 1) / 15.0     # 0x4303c0 levels 1, 1, 2, 2, 3, 3
				if archer:
					await wait(ANIM_TICK * 8)
			10:
				Audio.play_se("se%d" % (37 - swing_kind(att)))
			4:
				if n:
					n.attack_frame(att.dir, 2)
				Audio.play_se("se%d" % ((35 if damaged else 30) + (1 if crit else 0)))
				for k in targets.size():
					var t := targets[k]
					if t.node == null:
						continue
					t.node.set_pose(UnitSprite.Pose.HURT if hits[k] else UnitSprite.Pose.DEFEND, t.dir)
					t.node.flash_color = Color.WHITE
					t.node.flash = 0.8 if hits[k] and dmgs[k] > 0 else 0.0
					if not shown:
						# the numbers are the change box's (after the animation, 0x405ab8)
						if hits[k] and crit:
							st.hud.popup_number("暴击", t.pos, Color(1, 0.3, 0.2))
						elif not hits[k]:
							st.hud.popup_number("格挡", t.pos, Color(0.6, 0.9, 1))
				shown = true
			5:
				if n:
					n.attack_frame(att.dir, 3)
				for k in targets.size():
					var t := targets[k]
					if t.node and hits[k] and dmgs[k] > 0:
						t.node.flash_color = Color(1, 1, 4.0 / 15) if crit else Color.WHITE
						t.node.flash = 0.8
			6, 7:
				if n:
					n.attack_frame(att.dir, 3)
				for t in targets:
					if t.node:
						t.node.flash = 0.0
			8:
				if n:
					n.set_pose(UnitSprite.Pose.STAND, att.dir)
				for t in targets:
					if t.node:
						t.node.flash = 0.0
						t.node.flash_color = Color.WHITE
						t.node.set_pose(UnitSprite.Pose.STAND, t.dir)
		await wait(ANIM_TICK)


## End of a unit's action (0x442718 with 6): moved and finished, shown greyed. Then the path skills of the
## commanded unit (mod 0x4d90bf), on the units on the cells its last move went through, the last first (path[n−1]
## down to path[0], n ≥ 2 steps): 罗士信's 【术】波若 (15, once [0x55ac48] is set) and 齐国远's 【术】锻造 (16, once
## [0x55ac60] is set).
func end_action(u: BUnit) -> void:
	u.flags = u.flags | 6
	st.refresh_units()
	if u.pid != Mem.r32(BattleStage.CMD_PID):
		return
	var n := Mem.r8(BattleStage.PATH_LEN)
	var skill := 0
	if Skills.holds("boruo", u.pid) and Mem.r8(Skills.num("boruo", "flag")) != 0:
		skill = 15
	elif Skills.holds("duanzao", u.pid) and Mem.r8(Skills.num("duanzao", "flag")) != 0:
		skill = 16
	if skill == 0 or n < 2:
		return
	var c := 10 / (n - 1)
	for k in range(n - 1, -1, -1):
		var w := Mem.r16(BattleStage.PATH + 2 * k)
		var x := st.unit_on(Vector2i(w & 0xff, w >> 8))
		if x == null:
			continue
		if skill == 15:
			if not await _boruo(x, c):
				c = 0
		else:
			await _duanzao(x)


## 波若 (0x4d921d): a random one of the five stats gets the strong buff (ChangeUnit to 6), and with chance c·f / 100
## its stat word grows by one, f = 100 up to 300, 400 − w up to 400, else 0. The original computes 400 − w on the
## double word, so between 301 and 400 the chance overflows and the growth always happens. A failure ends c.
func _boruo(x: BUnit, c: int) -> bool:
	var s := Rules.rand(5)
	await st.commands.change_unit(x, s, 6)
	var a := x.person.base + 0x11 + 2 * s
	var raw := Mem.r32(a)
	var w := Mem.r16s(a)
	var f := 0
	if w <= 300:
		f = 100
	elif w <= 400:
		f = (400 - raw) & 0xffffffff
	var pct := ((c * f) & 0xffffffff) / 100
	if Rules.rand(100) < pct:
		Mem.w16(a, (Mem.r16(a) + 1) & 0xffff)
		return true
	return false


## 锻造 (0x4d94c9): the armour (chance 50 %) or else the weapon gains one experience point: up to 99 (a treasure
## 149, at level 9 even 249), past that a level, 0xff at the maximum (3, a treasure 10). Shown with pose 1 and SE 30.
func _duanzao(x: BUnit) -> void:
	var p := x.person
	var armour := Rules.chance(50)
	var off := 0x31 if armour else 0x2e
	var iid := Mem.r8(p.base + off)
	if iid == 0xff:
		return
	var treasure := bool(Game.item(iid).get("treasure", false))
	var m := 149 if treasure else 99
	var maxl := 10 if treasure else 3
	var e := Mem.r8(p.base + off + 2)
	if e == 0xff:
		return
	var lvl := Mem.r8(p.base + off + 1)
	if e < m or (lvl == 9 and e < 249):
		Mem.w8(p.base + off + 2, e + 1)
	else:
		lvl = (lvl + 1) & 0xff
		Mem.w8(p.base + off + 1, lvl)
		Mem.w8(p.base + off + 2, 0xff if lvl >= maxl else 0)
		await equip_notice(p, not armour)
	await st.unit_ops.op_unit_status({"args": [x.pid, 1, 0xff, 0]})
	Audio.play_se("se30")


## After each command, carried out or cancelled (0x43e1be → 0x4dcb09), the enemy units lying on the map at HP 0
## count: each is worth 1 (generic), 3, or the value of table 0x4dcc40 (6, 8 or 10 for named officers), and per
## point chance 10 % gives one 辰屑 (EV[3007..3009], a random one of the three). From EV[3183] ≥ 4 尉迟恭 (3) gets 5
## MP per fallen enemy, up to his base MP (+15 with 逍遥巾, +30 with 诸葛巾) — capped even when none fell.
func kill_rewards() -> void:
	var points := 0
	var count := 0
	for i in range(35, 115):
		var e := st.units[i]
		if e.state != BUnit.STATE_ON_MAP or Mem.r16(e.addr + 0x10) != 0:
			continue
		var pid := Mem.r32(e.addr)
		var v := 1
		if pid < 0xd2:
			v = 3
			for k in 100:
				if Mem.r16(0x4dcc40 + 4 * k) == pid:
					v = Mem.r8(0x4dcc43 + 4 * k)
					break
		points += v
		count += 1
	for k in points:
		if Rules.chance(10):
			var j := 3007 + Rules.rand(3)
			Mem.set_ev(j, Mem.ev(j) + 1)
	if Mem.ev(Skills.num("kill_mp", "ev")) >= Skills.num("kill_mp", "min"):
		var s := BUnit.slot_of(Skills.holder("kill_mp"))
		if s >= 0:
			var p3 := Game.person(Skills.holder("kill_mp"))
			var acc := Mem.r8(p3.base + 0x34)
			var cap := p3.mp_base + (15 if acc == 0x43 else 30 if acc == 0x44 else 0)
			var a := st.units[s].addr + 0x14
			Mem.w8(a, mini(Mem.r8(a) + Skills.num("kill_mp", "per_kill") * count, cap))


## A unit's HP reached 0 in an attack or a strategy: EV[10] = 1 for the scripts (mod 0x4d67b8, called at
## 0x405bb7 / 0x422c87). The unit stays on the map at HP 0 until the command is over: the player and AI
## loops then remove it (BattleStage.remove_dead, 0x44cc03) and poll the event scene.
## Nothing is played here: SE 16 and the blinks are RemoveUnit's (0x441814), when the unit leaves.
func unit_fell(u: BUnit) -> void:
	u.hp = 0
	u.extra["dying"] = true
	Mem.set_ev(10, 1)
	if false:
		await wait(0)


## A script brought a unit's HP to 0 (0x4121b0: EV[10] = 1, then RemoveUnit at once, whose SE 16 and blinks are
## the only ones).
func unit_defeated(u: BUnit) -> void:
	Mem.set_ev(10, 1)
	await st.unit_ops.remove_unit(u, false)
	st.unit_died.emit(u)


# ------------------------------------------------------------------ experience (§8)
## `show`: the change box with the gain first (0x4498e0's call after a duel); the callers that show their own box
## with the other changes pass false.
func gain_exp(u: BUnit, e: int, show := true) -> void:
	var p := u.person
	if p.level >= 70 or e <= 0:
		return
	if show:
		await st.hud.gauge(u, null, 0, 0, e, 0, 0, true)
	await set_exp(p, p.exp + e)


## SetExp (0x408950) with show, as the battle calls it: from a level under 70, a level-up per 100 points, also
## past 70 while the rest is 100 or more (the mod's option [0x55e1c0] == 4 gives each the +1 grade bonus,
## 0x4d0331); then the rest is the experience, or 0xff (MAX) from level 70.
func set_exp(p: Person, total: int) -> void:
	if p.level >= 70:
		return
	while total >= 100:
		if Mem.r8(0x55e1c0) == 4:
			p.bonus_counter = 5
		var g := p.level_up(1)
		await _show_level_up(p, g)
		total -= 100
	p.exp = 0xff if p.level >= 70 else total


## LevelUp's show part (0x4074cf): in a battle the unit's pose 11 (0x45778f(pid, 0xb, 0, 0)), SE 11, the report.
func _show_level_up(p: Person, g: Array) -> void:
	if st.in_battle():
		await st.unit_ops.op_unit_status({"args": [p.id, 11, 0, 0]})
	Audio.play_se(SE_LEVELUP)
	# "X升为N级。" and "学会了策略「…」！" are timed boxes (style 2); the detailed report of 升级显示能力成长 is an
	# OK box (style 0, 0x4dbe57)
	var detail := Mem.r8(Settings.LEVEL_DETAIL) != 0
	var texts := p.level_up_texts(g)
	for i in texts.size():
		if i == 0 and detail:
			await st.ui.popup(texts[i], 1.2 if Game.auto_input else 0.0)
		else:
			await st.ui.message(texts[i])


## 0x40397d: the weapon experience a strike at target `t` is worth: 3 when it took HP or MP damage, 2 when the
## attacker's level is the higher, else 1; times the attacker's EXP bonus, and 1 from weapon level 9 (mod 0x4e00a5).
func _weapon_gain(att: BUnit, t: BUnit, damaged: bool) -> int:
	var g := (2 if att.level() > t.level() else 3) if damaged else 1
	g = g * exp_mult(att) / 100
	return 1 if att.person.weapon_lvl >= 9 else g


## 0x403a85: the armour experience of target `t` (its own colour 0 only, 0x43ff54) for a strike by `att`: 4 when it
## took HP or MP damage, 3 when the attacker's level is the lower, else 1; times the wearer's EXP bonus, and 1 from
## armour level 9 (mod 0x4e01a5).
func _armor_gain(t: BUnit, att: BUnit, damaged: bool) -> int:
	var g := (3 if att.level() < t.level() else 4) if damaged else 1
	g = g * exp_mult(t) / 100
	return 1 if t.person.armor_lvl >= 9 else g


## 0x4082d6: `amount` experience for the weapon or the armour. 100 a level, 150 for a treasure (250 from its level
## 9), up to level 3, a treasure's 10; the threshold is that of the starting level. At the top the experience is
## 0xff (MAX).
func add_equip_exp(p: Person, weapon: bool, amount: int) -> void:
	var iid := p.weapon if weapon else p.armor
	if iid < 0:
		return
	var lvl := p.weapon_lvl if weapon else p.armor_lvl
	var cur := p.weapon_exp if weapon else p.armor_exp
	var it := Game.item(iid)
	var treasure := bool(it.get("treasure", false))
	var maxl := 10 if treasure else 3
	var thr := 100 + (50 if treasure else 0) + (100 if treasure and lvl == 9 else 0)
	var total := cur + amount
	while total >= thr and lvl < maxl:
		lvl += 1
		total -= thr
		# 0x409620 writes the level, then the notice runs once per level (0x4083ef)
		if weapon:
			p.weapon_lvl = lvl
		else:
			p.armor_lvl = lvl
		await equip_notice(p, weapon)
	if weapon:
		p.weapon_lvl = lvl
		p.weapon_exp = 0xff if lvl >= maxl else total
	else:
		p.armor_lvl = lvl
		p.armor_exp = 0xff if lvl >= maxl else total


## A weapon or armour level gained (0x4083ef). In a battle the unit turns once (12), then a weapon swings twice (7)
## and cheers (1), armour defends twice (2 with its wait, 0, 2 ticks, 2, 0) and cheers; SE 13 and "武器等级上升！" /
## "护具等级上升！". Then, always, the panel with the item, its new level, the wearer and the value before → after.
func equip_notice(p: Person, weapon: bool) -> void:
	if st.in_battle():
		await st.unit_ops.op_unit_status({"args": [p.id, 12, 0, 0]})
		if weapon:
			await st.unit_ops.op_unit_status({"args": [p.id, 7, 0, 0]})
		else:
			await st.unit_ops.op_unit_status({"args": [p.id, 2, 0, 1]})
			await st.unit_ops.op_unit_status({"args": [p.id, 0, 0, 0]})
			await st.wait(0.1)
			await st.unit_ops.op_unit_status({"args": [p.id, 2, 0, 1]})
			await st.unit_ops.op_unit_status({"args": [p.id, 0, 0, 1]})
		await st.unit_ops.op_unit_status({"args": [p.id, 1, 0, 0]})
		Audio.play_se(SE_EQUIP_UP)
		await st.ui.message("武器等级上升！" if weapon else "护具等级上升！")
	var iid := p.weapon if weapon else p.armor
	var lvl := p.weapon_lvl if weapon else p.armor_lvl
	if iid >= 0:
		await st.hud.equip_panel(iid, lvl, p, weapon)


# ------------------------------------------------------------------ strategies (§5)
## The strategies whose learn level for the person's class is reached, by id: the AI's usable-strategy list
## (0x43844a, before its MP test) and the 武将情报 page (0x4658c0).
func learned_strategies(u: BUnit) -> Array[int]:
	var out: Array[int] = []
	for sd in Game.strategies_db:
		if not sd.get("loaded_by_exe", true):
			continue
		var lv := int(sd.get("learn_level_by_class", {}).get(str(u.cls()), 0))
		if lv > 0 and lv <= u.level():
			out.append(int(sd["id"]))
	return out


## The battle 策略 list (0x465a40): the strategies whose learn level for the class is reached, by id. 秦琼 (8) as
## 统军 (43) learns the strategies from 0x29 on by class 35's table (mod 0x4da280), which adds 补给 and 救护. With
## 策略模仿 (effect 51) also those that the units on the 4 cells beside the caster (any side, 0x4359f5 / 0x435884)
## have learned for their own class and level.
func known_strategies(u: BUnit) -> Array[int]:
	var out: Array[int] = []
	var copied := {}
	if u.has_effect(51):
		for d in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
			var o := Skills.unit_in_cell(u.pos + d)
			if o != null:
				for s in learned_strategies(o):
					copied[s] = true
	var c := str(u.cls())
	for sd in Game.strategies_db:
		if not sd.get("loaded_by_exe", true):
			continue
		var lv: Dictionary = sd.get("learn_level_by_class", {})
		var k := c
		if u.cls() == 43 and (u.pid & 0xff) == 8 and int(sd["id"]) >= 0x29:
			k = "35"
		if (lv.has(k) and int(lv[k]) > 0 and int(lv[k]) <= u.level()) or copied.has(int(sd["id"])):
			out.append(int(sd["id"]))
	return out


## MP cost (0x425ad0): double while a 连续策略 second cast is open ([0x4d0d61]).
func strategy_mp(s: int) -> int:
	var mp := int(Game.strategy(s).get("mp", 0))
	return mp * 2 if Mem.r8(BattleStage.SECOND_CAST) != 0 else mp


## What a cast costs u (0x4664b9 in the 策略 list, 0x422f0d when it is paid): strategy_mp, less 节约MP's percentage
## (effect 49), then halved (at least 1) while 房玄龄 (179, 【术】房谋) stands next to u on its side (mod 0x4d4a05).
func strategy_cost(u: BUnit, s: int) -> int:
	var cost := strategy_mp(s)
	if u.has_effect(49):
		cost -= cost * u.effect_value(49) / 100
	if Skills.near("fangmou", u):
		cost = maxi(cost >> 1, 1)
	return cost


## 0x4d0d71 after a cast: the first cast by a unit with 连续策略 (effect 83) sets [0x4d0d61], so the next cast
## costs double, and the caster may cast again (true); any other cast clears it. The AI's casts run through it
## too, so an AI caster with 83 leaves the next cast of anyone at double cost.
func second_cast(u: BUnit) -> bool:
	if Mem.r8(BattleStage.SECOND_CAST) == 0 and u.has_effect(83):
		Mem.w8(BattleStage.SECOND_CAST, 1)
		return true
	Mem.w8(BattleStage.SECOND_CAST, 0)
	return false


## The cells a strategy can be cast on. 苏烈 (35, 【术】逐影随行咒, mod 0x5281c0) casts every strategy that is not
## map-wide within 4 cells (range 13), the self-cast ones included.
func strategy_cast_cells(u: BUnit, s: int) -> Array[Vector2i]:
	var sd := Game.strategy(s)
	var ally := int(sd.get("target", 0)) == 1
	var r := int(sd.get("range", 0))
	if r != 10 and Skills.holds("zhuying", u.pid):
		r = Skills.num("zhuying", "range")
	# range 11: cast on the caster's own cell (weather 58-60, 飓风, the self buffs)
	return Shapes.range_cells(r, u.pos, view().map_w, view().map_h, ally or r == 11)


## 【术】烈魔 (the persons in EV[3985..3988]): every strategy they cast covers more (mod 0x528200): area 0 → 1,
## 1 → 2, 2 → 3, any other → 6.
func lie_mo(u: BUnit) -> bool:
	return Skills.holds("liemo", u.pid)


func strategy_area(u: BUnit, s: int, target: Vector2i) -> Array[Vector2i]:
	return Shapes.area_cells(strategy_area_code(u, s), u.pos, target, view().map_w, view().map_h)


## The area code of a cast (ctx+0x2ca): the record's, widened for 烈魔.
func strategy_area_code(u: BUnit, s: int) -> int:
	var a := int(Game.strategy(s).get("area", 0))
	if lie_mo(u):
		a = [1, 2, 3][a] if a <= 2 else 6
	return a


## Units affected by casting s at `target` (side filter 0 enemy, 1 ally).
func strategy_targets(u: BUnit, s: int, target: Vector2i) -> Array[BUnit]:
	var side := int(Game.strategy(s).get("target", 0))
	var out: Array[BUnit] = []
	if Rules.handler(s) == "storm":
		# 飓风 (0x42423a): every opposing unit on the map where the strategy is usable
		for t in st.units:
			if t.active() and t.is_enemy_of(u) and usable_on(u, s, t):
				out.append(t)
		return out
	if Rules.handler(s) == "xuanwu":
		# 玄武 (0x424810): every unit on the map, of either side (0x42097a passes for strategies >= 0x14)
		for t in st.units:
			if t.active():
				out.append(t)
		return out
	# the unit on the target cell must pass 0x420422, else nothing happens; the others in the area only need a
	# fitting terrain for element strategies (0x425349 → 0x42097a)
	var main := st.unit_at(target)
	if main == null or not _side_ok(u, side, main) or not usable_on(u, s, main):
		return out
	for c in strategy_area(u, s, target):
		var t := st.unit_at(c)
		if t == null or not t.active() or not _side_ok(u, side, t):
			continue
		if t == main or Rules.strat_terrain_ok(s, u, view().terrain_at(t.pos)):
			out.append(t)
	if Rules.handler(s) in REPEATED_HANDLERS and Skills.holds("ruosha", u.pid):
		# 【术】弱杀 (0x528270): every unit on the map with a status joins, of either side (no script hands it out)
		for t in st.units:
			if t.exists() and t.state == BUnit.STATE_ON_MAP and (t.status & 0x7e) and not out.has(t):
				out.append(t)
	return out


func _side_ok(u: BUnit, side: int, t: BUnit) -> bool:
	if side == 0:
		return t.is_enemy_of(u)
	if side == 1:
		return not t.is_enemy_of(u)
	return true


## Can u use strategy s on t (0x420422, see Rules.strat_usable)?
func usable_on(u: BUnit, s: int, t: BUnit) -> bool:
	return Rules.strat_usable(s, u, t, view().terrain_at(t.pos))


func can_cast(u: BUnit, s: int) -> bool:
	if u.status & BUnit.ST_SEAL:
		return false
	return u.mp >= strategy_cost(u, s)


## Why u cannot cast s right now (0x41fec9), or "".
func cast_refusal(u: BUnit, s: int) -> String:
	return Rules.strat_castable(s, u, st.weather())


## The handlers whose strategies 烈魔 runs twice and 弱杀 extends: damage 0x42313e and status 0x423549.
const REPEATED_HANDLERS := ["damage", "status"]


func cast(u: BUnit, s: int, target: Vector2i) -> void:
	var sd := Game.strategy(s)
	var cost := strategy_cost(u, s)
	face(u, target)
	var targets := strategy_targets(u, s, target)
	for t in targets:
		t.extra.erase("mp_taken")
		t.extra.erase("hp_taken")
	if Rules.handler(s) == "again" and not targets.is_empty():
		Mem.w8(Rules.ZHANBEI_USED + u.slot, 1)     # 0x423960: once per turn (0x41fec9)
	await view().ensure_visible(target)
	if not Game.instant:
		if u.node:
			u.node.set_pose(UnitSprite.Pose.CHEER, u.dir)
		# 0x4218d6, once a cast (0x4214bf; 青龙 calls it itself at 0x424f3c before its strikes): 8 ticks, SE 8 with
		# the caster in its casting pose, then SE 39 and the strategy's name in a timed box (0x42f699 style 2), at
		# least 20 ticks in all
		var t0 := Time.get_ticks_msec()
		await wait(8 * 0.05)
		Audio.se(8)
		Audio.se(39)
		await st.ui.message(str(sd.get("name", "")))
		await wait(maxf(1.0 - (Time.get_ticks_msec() - t0) / 1000.0, 0.0))
		await _play_strategy_effect(s, target, targets)
		if u.node:
			u.node.set_pose(UnitSprite.Pose.STAND, u.dir)
	var best_exp := 0
	var weapon_exp := 0
	if Rules.handler(s) == "weather":
		# 0x423b2f: no hit roll. The climate gives the level (0x44a1f9); the level there is already fails (Xben.wa
		# 0x2d at the caster), any other is set after SE 134 and 1.5 s (0x449f91). 20 EXP either way (0x420efb).
		var w := st.weather_strategy_level(s)
		if w == st.weather_level:
			if not Game.instant:
				var e := EffectPlayer.create("xben", 0x2d)
				if e:
					e.position = view().cell_center(u.pos)
					view().fx_layer.add_child(e)
					await e.done
		else:
			if not Game.instant:
				Audio.se_m(34)
				await wait(1.5)
			await st.set_weather(w)
		best_exp = 20
		weapon_exp = _strat_weapon_gain(u, u, s)
		targets.clear()
	var single := strategy_area_code(u, s) == 0       # 0x4224a8 holds each box long for area 0 (ctx+0x2ca)
	for t in targets:
		weapon_exp = maxi(weapon_exp, _strat_weapon_gain(u, t, s))
		var e := await _apply_strategy(u, s, t, single)
		best_exp = maxi(best_exp, e)
	if lie_mo(u) and Rules.handler(s) in REPEATED_HANDLERS:
		# 烈魔 (0x528100 / 0x528160): the same targets once more, with new rolls
		for t in targets:
			if t.active():
				weapon_exp = maxi(weapon_exp, _strat_weapon_gain(u, t, s))
				var e := await _apply_strategy(u, s, t, single)
				best_exp = maxi(best_exp, e)
	# 0x422f7c: the cost is paid after the effect; 暗鬼 (22) gives the caster the MP it took and 暗算 the HP the
	# first target lost, each up to the maximum. The caster's box comes first (held long), then the HP and MP,
	# the experience (SetExp) and the weapon's. Both experiences need a player-controlled caster (code 7,
	# ctx+0x4a8 set at 0x425279; 0x420efb / 0x42128b give 0 otherwise).
	var mp := Rules.sat_sub(u.mp, cost)
	var hp := u.hp
	if not targets.is_empty():
		if Rules.strat_mp_damage(s):
			mp += clampi(int(targets[0].extra.get("mp_taken", 0)), 0, maxi(u.max_mp() - mp, 0))
		if Game.strategy_rule(s).get("absorb_hp", false):
			hp += clampi(int(targets[0].extra.get("hp_taken", 0)), 0, maxi(u.max_hp() - hp, 0))
	if u.mode != 7:
		best_exp = 0
		weapon_exp = 0
	best_exp = best_exp * exp_mult(u) / 100
	await st.hud.gauge(u, _last_target(targets), u.hp - hp, u.mp - mp, best_exp, weapon_exp, 0, true)
	u.hp = hp
	u.mp = mp
	if best_exp > 0:
		await gain_exp(u, best_exp, false)
	if weapon_exp > 0:
		await add_equip_exp(u.person, true, weapon_exp)
	st.refresh_units()


## 0x42128b: the caster's weapon experience for target t: 3, or 2 when the caster's level is the higher, for a
## strategy on either side (record +0xb 0 / 1); 3 for one on none (weather, 2). No EXP bonus: the mod drops the
## product (0x42139c) and the test for a weapon of type 2 (0x4212ea).
func _strat_weapon_gain(u: BUnit, t: BUnit, s: int) -> int:
	match int(Game.strategy(s).get("target", 0)):
		0, 1:
			return 2 if u.level() > t.level() else 3
		2:
			return 3
	return 0


## 0x4213a3: the armour experience of target t of a strategy (its own colour 0 only, 0x43ff54): on a strategy
## against the enemy side (record +0xb = 0) that changed its HP or MP (ctx+0x84 ≠ 0), 4, 3 when the caster's level
## is the lower; times the wearer's EXP bonus; else 0.
func _strat_armor_gain(u: BUnit, t: BUnit, s: int, amount: int) -> int:
	if t.colour != 0 or int(Game.strategy(s).get("target", 0)) != 0 or amount == 0:
		return 0
	return (3 if u.level() < t.level() else 4) * exp_mult(t) / 100


func _strat_exp(u: BUnit, t: BUnit, killed: bool, damage_strat: bool) -> int:
	var la := u.level()
	var lt := t.level()
	if t.is_enemy_of(u) and damage_strat and killed:
		var e := Rules.kill_exp(la, lt)
		return e * (2 if t.pid == st.boss_pid else 1)
	return Rules.strategy_exp(la, lt)


## One target of a cast, by the strategy's record (Rules.handler and the fields of data/strategy_rules.json).
## The changes go through 0x4224a8: the target's box (held long when `hold`), then the HP and MP, then its armour
## experience (0x4213a3, ctx+0x2d8).
func _apply_strategy(u: BUnit, s: int, t: BUnit, hold := true) -> int:
	var r := Game.strategy_rule(s)
	var h := Rules.handler(s)
	if h in ["bazhen", "xuanwu"]:
		return await _apply_random_strategy(u, s, t, hold)
	var damage_set: bool = Rules.strat_hp_damage(s) or Rules.strat_mp_damage(s) or r.get("assassinate", false)
	# heals (0x42378d) have no hit roll: the amount is capped by what is missing
	var hit := h == "heal" or Rules.chance(Rules.strat_hit(u, t, s, view().terrain_at(t.pos), st.weather()))
	if not hit:
		if not Game.instant:
			st.hud.popup_number("失败", t.pos, Color(0.7, 0.7, 0.7))
		return _strat_exp(u, t, false, false)
	if r.get("assassinate", false):
		# 暗杀 (0x43c058): no damage; the target is marked (0x569f00[t] = 2, assassin 0x569f73[t]) and drops
		# to 1 HP two phase starts later (BattleStage._assassination_countdown). The hit still counts as one
		# (0x569fe7 toggles, 0x42322d), and the EXP is that of a strategy that kills nothing.
		Mem.w8(BattleStage.ASSASSIN_MARK + t.slot, 2)
		Mem.w8(BattleStage.ASSASSIN_LINK + t.slot, u.slot)
		Mem.w8(BattleStage.ASSASSIN_HIT, Mem.r8(BattleStage.ASSASSIN_HIT) ^ 1)
		if not Game.instant:
			st.hud.popup_number("暗杀", t.pos, Color(0.8, 0.5, 1))
		return _strat_exp(u, t, false, false)
	if damage_set:
		var dmg := Rules.strat_damage(u, t, s, false)
		var ae := _strat_armor_gain(u, t, s, dmg)
		if Rules.strat_mp_damage(s):
			await st.hud.gauge(t, u, 0, mini(dmg, t.mp), 0, 0, ae, hold)
			t.mp = maxi(t.mp - dmg, 0)
			t.extra["mp_taken"] = dmg
			await _armor_exp(t, ae)
			return _strat_exp(u, t, false, true)
		var killed := dmg >= t.hp
		if not Game.instant and t.node:
			t.node.set_pose(UnitSprite.Pose.HURT, t.dir)
		await st.hud.gauge(t, u, mini(dmg, t.hp), 0, 0, 0, ae, hold)
		if not Game.instant and t.node:
			t.node.set_pose(UnitSprite.Pose.STAND, t.dir)
		_apply_damage(t, dmg)
		t.extra["hp_taken"] = dmg       # 暗算 gives the caster the first target's at the end (0x422f7c)
		if killed:
			await unit_fell(t)
		else:
			t.status |= _status_bit(r)      # 毒烟 / 瘴雾 中毒, 陷阱 / 濠壑 麻痹: only on a target that survives
			await _strategy_bun(t, dmg)
		await _armor_exp(t, ae)
		return _strat_exp(u, t, killed, true)
	t.status |= _status_bit(r)              # 伪书 / 伪令 混乱, 封印 封策
	if r.has("cure"):
		t.status &= ~int(r["cure"])         # 棒喝 / 超脱
	for c in r.get("stat_codes", []):
		_stat_code(t, int(c))               # the stat strategies (0x42335b) and 聚气 / 豪气 (0x423cc0)
	match r.get("heal"):
		"hp":
			var h2 := mini(Rules.heal_amount(u, t, s, false), maxi(t.max_hp() - t.hp, 0))
			await st.hud.gauge(t, u, -h2, 0, 0, 0, 0, hold)
			t.hp += h2
		"mp":
			var m := mini(Rules.heal_amount(u, t, s, false), maxi(t.max_mp() - t.mp, 0))
			await st.hud.gauge(t, u, 0, -m, 0, 0, 0, hold)
			t.mp += m
	match h:
		"again":                            # 战备 (0x423960)
			t.moved = false
			t.acted = false
		"meditate":
			# 暝思 (0x423d6c): 50 HP, or all but 1 from 50 down, for half that in MP (rounded toward 0) up to
			# what is missing; through 0x4224a8's case 0x3e (HP ctx+0x88, MP ctx+0x84)
			var hp_cost := 50 if t.hp > 50 else t.hp - 1
			var gain := mini(hp_cost / 2, maxi(t.max_mp() - t.mp, 0))
			await st.hud.gauge(t, u, hp_cost, -gain, 0, 0, 0, hold)
			t.hp -= hp_cost
			t.mp += gain
	st.refresh_units()
	return _strat_exp(u, t, false, false)


## 0x4082d6(target, armour) at the end of a target in 0x4224a8.
func _armor_exp(t: BUnit, ae: int) -> void:
	if ae > 0 and t.exists():
		await add_equip_exp(t.person, false, ae)


## The status a strategy's record gives ("status": confusion, poison, paralysis, seal), or 0.
static func _status_bit(r: Dictionary) -> int:
	match r.get("status"):
		"confusion": return BUnit.ST_CONFUSION
		"poison": return BUnit.ST_POISON
		"paralysis": return BUnit.ST_PARALYSIS
		"seal": return BUnit.ST_SEAL
	return 0


## 八阵 (0x423edc) and 玄武 (0x424810): no hit roll; each target gets one random outcome. 八阵 draws rand(8):
## 0 八阵 damage, 1 混乱, 2 麻痹, 3 封策, 4 毒烟 damage + 中毒, 5 爆发/士气/攻击/防御↓ (code 0x6f),
## 6 the same ↑ (0xaf), 7 兵力 to full (0x43c548: MaxHP − HP). 玄武 draws rand(7) of 混乱, 麻痹, 封策, 中毒,
## 0x6f, 0xaf, full 兵力. 八阵's statuses only stick if the target survives the damage (0x4224a8). EXP (0x420efb):
## 八阵 is a damage strategy, so its kill formula applies when the stored amount is not below the target's
## 兵力 (a heal is stored negated and compares as a huge unsigned value); 玄武 always gives the small one.
func _apply_random_strategy(u: BUnit, s: int, t: BUnit, hold := true) -> int:
	var bazhen := Rules.handler(s) == "bazhen"
	var k: int = Rules.rand(8) if bazhen else Rules.rand(7) + 1
	var amount := 0       # damage, or −heal
	match k:
		0, 4:
			if bazhen:
				var hs := s if k == 0 else 33
				if Rules.chance(Rules.strat_hit(u, t, hs, view().terrain_at(t.pos), st.weather())):
					amount = Rules.strat_damage(u, t, hs, false)
		7:
			amount = -(t.max_hp() - t.hp)
	var stored := amount if amount >= 0 else 0x100000000 + amount
	var e := _strat_exp(u, t, bazhen and stored >= t.hp, bazhen)
	var survives := amount < t.hp
	match k:
		1:
			if survives: t.status |= BUnit.ST_CONFUSION
		2:
			if survives: t.status |= BUnit.ST_PARALYSIS
		3:
			if survives: t.status |= BUnit.ST_SEAL
		4:
			if survives: t.status |= BUnit.ST_POISON
		5:
			for c in [0x17, 0x19, 0x1b, 0x1d]:
				_stat_code(t, c)
		6:
			for c in [0x31, 0x33, 0x35, 0x37]:
				_stat_code(t, c)
	var ae := _strat_armor_gain(u, t, s, amount)
	if amount > 0:
		var dmg := mini(amount, t.hp)
		await st.hud.gauge(t, u, dmg, 0, 0, 0, ae, hold)
		_apply_damage(t, dmg)
		if t.hp == 0:
			await unit_fell(t)
		else:
			await _strategy_bun(t, dmg)
	elif amount < 0:
		await st.hud.gauge(t, u, amount, 0, 0, 0, ae, hold)
		t.hp -= amount
	await _armor_exp(t, ae)
	st.refresh_units()
	return e


## Stat change codes of 0x420cb2: 0x17 爆发↓ 0x19 士气↓ 0x1b 攻击↓ (精神 for caster families, 0x43ffed)
## 0x1d 防御↓; 0x30 移动↑ 0x31 爆发↑ 0x33 士气↑ 0x37 防御↑; 0x35 (mod 0x4d8985): classes 24-26 and 50 raise
## both 攻击 and 精神, others 精神 if a caster family, else 攻击.
func _stat_code(t: BUnit, code: int) -> void:
	var magic := t.family() in [8, 9, 10, 18]
	match code:
		0x17, 0x18: _buff(t, 3, false)
		0x19, 0x1a: _buff(t, 4, false)
		0x1b, 0x1c: _buff(t, 2 if magic else 0, false)
		0x1d, 0x1e: _buff(t, 1, false)
		0x30: _buff(t, 5, true)
		0x31, 0x32: _buff(t, 3, true)
		0x33, 0x34: _buff(t, 4, true)
		0x35, 0x36:
			if t.cls() == 50 or (t.cls() >= 24 and t.cls() <= 26):
				_buff(t, 2, true)
				_buff(t, 0, true)
			else:
				_buff(t, 2 if magic else 0, true)
		0x37, 0x38: _buff(t, 1, true)


func _buff(t: BUnit, i: int, up: bool) -> void:
	t.set_buff(i, Rules.buff_step(t.buff(i), up))
	if not Game.instant:
		var names := ["攻击", "防御", "精神", "爆发", "士气", "移动"]
		st.hud.popup_number(names[i] + ("↑" if up else "↓"), t.pos, Color(1, 0.9, 0.4) if up else Color(0.7, 0.6, 1))


## The Xben effect 0x4214bf plays on the targets after an MCALL strategy's animation: 炼狱 1, 海啸 3, 龙挂 5,
## 地裂 7, 青龙 0x16, 朱雀 0x39, 白虎 10; 玄武 none; 八阵 (0x421ce5) plays each target's outcome effect, which the
## port does not (it rolls the outcomes after the animation).
const MCALL_FOLLOW := {3: 1, 8: 3, 13: 5, 18: 7, 64: 0x16, 65: 0x39, 67: 10}


func _play_strategy_effect(s: int, target: Vector2i, targets: Array[BUnit]) -> void:
	var tbl: Array = EffectPlayer.index().get("strategy_effect_table", {}).get("values", [])
	if s < 0 or s >= tbl.size():
		return
	var v := int(tbl[s])
	if v == 255:
		return
	if v >= 100:
		# MCALL animations are centred on the target point (0x402cb5), like the small effects; then 0x4214bf plays
		# the strategy's Xben effect on the targets (its remap of the MCALL strategies)
		var e := EffectPlayer.create("mcall", v - 100)
		if e:
			e.position = view().cell_center(target)
			e.z_index = 10
			view().fx_layer.add_child(e)
			await e.done
		v = int(MCALL_FOLLOW.get(s, 255))
		if v == 255:
			return
	var cells: Array[Vector2i] = []
	for t in targets:
		cells.append(t.pos)
	if cells.is_empty():
		cells.append(target)
	var last: EffectPlayer = null
	for c in cells:
		var e2 := EffectPlayer.create("xben", v)
		if e2 == null:
			return
		e2.position = view().cell_center(c)
		view().fx_layer.add_child(e2)
		last = e2
	if last:
		await last.done


# ------------------------------------------------------------------ items
## 馒头, the item 笼屉 (effect 62 使用馒头) eats.
const BUN := 0x57


## 笼屉 after strategy damage (0x4224a8, mod 0x4dca83): a unit that survives a loss eats a 馒头, a red one only once
## it is 100 or more below its maximum, any other at once.
func _strategy_bun(t: BUnit, dmg: int) -> void:
	if dmg > 0 and t.hp > 0 and t.has_effect(62) and (t.colour != 0 or t.hp + 100 <= t.max_hp()):
		await eat_bun(t)


## 笼屉's 馒头 (0x41dc43(0x57, slot, 0, free)): a red unit eats one from the bag if there is one (0x40db3e, removed
## by 0x40d955), any other unit one for free. It heals as the item does (0x43c42e).
func eat_bun(t: BUnit) -> void:
	var free := t.colour != 0
	if not free and Game.stack_count(BUN) <= 0:
		return
	var h := heal_value(BUN, t)
	await _use_anim(t, t, BUN, 0xff)        # through the HP item handler 0x41ccdf
	await st.hud.gauge(t, t, -h, 0, 0, 0, 0, true)
	t.hp += h
	if not free:
		Game.remove_item_id(BUN)
	st.refresh_units()


## What a 恢复HP / 恢复MP item (types 63 / 64) restores (0x43c42e): its value, at most what is missing; a value of
## 0xff fills it.
func heal_value(iid: int, t: BUnit) -> int:
	var it := Game.item(iid)
	var v := int(it.get("value", 0))
	if Game.item_rule(iid).get("kind") == "heal_mp":
		var mm := t.max_mp() - t.mp
		return mm if v == 0xff or (mm >= 0 and mm < v) else v
	var mh := t.max_hp() - t.hp
	return mh if v == 0xff or (mh >= 0 and mh < v) else v


func usable_items() -> Array:
	var out := []
	for e in Game.bag_entries():
		var it := Game.item(int(e["id"]))
		if String(it.get("category", "")) == "consumable":
			out.append(e)
	return out


## Whether a consumable's handler takes `t`, by the kind of its type (data/item_rules.json).
func item_usable_on(iid: int, t: BUnit) -> bool:
	var r := Game.item_rule(iid)
	match r.get("kind"):
		"heal_hp": return t.hp < t.max_hp()
		"heal_mp": return t.mp < t.max_mp()
		"cure": return t.status & int(r["mask"]) != 0
		"promote": return t.cls() <= 38 and t.cls() % 3 < 2 and t.level() >= (20 if t.cls() % 3 == 0 else 40)
	return true


## Fruits, 仙人果 and 印绶 take any unit of one's own and refuse afterwards (_item_check).
static func item_checked_after(iid: int) -> bool:
	return Game.item_rule(iid).get("kind") in ["fruit", "level_up", "promote"]


## Use a consumable on t; false when the handler refuses (the item stays and the unit keeps its turn).
func use_item(u: BUnit, entry: Dictionary, t: BUnit) -> bool:
	var iid := int(entry["id"])
	var it := Game.item(iid)
	var v := int(it.get("value", 0))
	var p := t.person
	var r := Game.item_rule(iid)
	face(u, t.pos)
	if item_checked_after(iid):
		if not await _item_check(r, p):
			return false
	match r.get("kind"):
		"heal_hp":
			# 0x41ccdf / 0x41ce3d: the use animation without an effect, then the heal
			await _use_anim(u, t, iid, 0xff)
			var h := heal_value(iid, t)
			await st.hud.gauge(t, u, -h, 0, 0, 0, 0, true)
			t.hp += h
		"heal_mp":
			await _use_anim(u, t, iid, 0xff)
			var m := heal_value(iid, t)
			await st.hud.gauge(t, u, 0, -m, 0, 0, 0, true)
			t.mp += m
		"cure":
			await _use_anim(u, t, iid, 44)          # 0x41cf61 (types 65..69): Xben 44 over the target
			t.status &= ~int(r["mask"])
		"all_up":
			await _use_anim(u, t, iid, 44)
			# 太保令 (mod 0x4d2d5a): the five stat words +2 (at most 9999) and the abilities +2 (at most 100), no buff;
			# the unit's poses 11 and 7 (0x45778f)
			for i in 5:
				p.set_stat_word(i, Person._min_add(p.get_stat_word(i), 2, 9999))
			for i in 5:
				p.set_raw(i, Person._min_add(p.get_raw(i), 2, 100))
			await st.unit_ops.op_unit_status({"args": [p.id, 11, 0xff, 0xff]})
			await st.unit_ops.op_unit_status({"args": [p.id, 7, 0, 0]})
		"fruit":
			# fruits (0x41d080): word and ability up, the stat-up effect, the battle level of that stat one step up;
			# no message
			var si := int(r["stat"])
			var word := mini(p.get_stat_word(si) + v, 9999)
			var raw := mini(p.get_raw(si) + v, 100)
			await _use_anim(u, t, iid, int(r["fx"]))
			p.set_stat_word(si, word)
			p.set_raw(si, raw)
			t.set_buff(si, Rules.buff_step(t.buff(si), true))
		"level_up":
			# 仙人果 (0x41d3d9): counted per person (0x55a400), the +1 grade bonus for the next five stats, its value as
			# experience through SetExp, then 兵力 and 策略 to full
			await _use_anim(u, t, iid, 0xff)
			Mem.w8(0x55a400 + p.id, (Mem.r8(0x55a400 + p.id) + 1) & 0xff)
			p.bonus_counter = 5
			await set_exp(p, p.exp + v)
			t.hp = t.max_hp()
			t.mp = t.max_mp()
		"promote":
			await _promote(u, t, iid)
	_consume(entry)
	st.refresh_units()
	return true


## The refusals of 0x41c4e9 / 0x40934d (timed boxes) for fruits, 仙人果 and 印绶.
func _item_check(r: Dictionary, p: Person) -> bool:
	var why := ""
	if r.get("kind") == "fruit":
		if p.get_raw(int(r["stat"])) >= 100:
			why = "该项能力已经达到100，不能再提升了。"
	elif r.get("kind") == "level_up":
		if p.level >= 70:
			why = "不能再升级了。"
	elif p.cls > 38:
		why = "这是不能提升兵种的部队。"
	elif p.cls % 3 == 2:
		why = "不能再提升兵种了。"
	elif p.level < (p.cls % 3 + 1) * 20:
		why = "下一个兵种需要等级%d以上。" % ((p.cls % 3 + 1) * 20)
	if why == "":
		return true
	await st.ui.message(why)
	return false


## The use animation every battle item handler shares (0x41c762): the user, standing, holds the item's icon (5 ticks),
## SE 41, raises it while cheering (10 ticks); then the icon fades in over the target (16 ticks) and the Xben
## effect `xben` plays there (0xff none).
func _use_anim(u: BUnit, t: BUnit, iid: int, xben: int) -> void:
	if Game.instant or u.node == null:
		return
	var tex := Game.item_picture(iid)
	await view().ensure_visible(u.pos)
	u.node.show_frame(UnitSprite.Sheet.MOV, 6)
	st.hud.icon_over = {"tex": tex, "cell": u.pos, "off": Vector2(8, 16)}
	await st.wait(0.25)
	Audio.se(41)
	u.node.show_frame(UnitSprite.Sheet.SPC, 4)
	st.hud.icon_over = {"tex": tex, "cell": u.pos, "off": Vector2(8, 0)}
	await st.wait(0.5)
	st.hud.icon_over = {}
	for i in 16:
		st.hud.icon_over = {"tex": tex, "cell": t.pos, "off": Vector2(8, 0), "alpha": (i + 1) / 16.0}
		st.hud.queue_redraw()
		await st.wait(0.05)
	st.hud.icon_over = {}
	if xben != 0xff:
		var e := EffectPlayer.create("xben", xben)
		if e:
			e.position = view().cell_center(t.pos)
			e.z_index = 10
			view().fx_layer.add_child(e)
			await e.done


## 印绶 (0x41d4db): the HP and MP bases grow by twice the old class's growth (one byte each), both to full, the
## unit spins and cheers; the class goes up with the old sprite whitening (SE 33) and the new one coming back from
## white (SE 12); "%s的兵种提升为%s！", then "学会了「%s」策略！" for each strategy the new class has and the old one
## had not, at a level already reached.
func _promote(u: BUnit, t: BUnit, iid: int) -> void:
	var p := t.person
	await _use_anim(u, t, iid, 0xff)
	var old := p.cls
	var g: Dictionary = Game.cls(old).get("growth", {})
	p.add_stat(5, (2 * int(g.get("hp", 0))) & 0xff)
	p.add_stat(6, (2 * int(g.get("mp", 0))) & 0xff)
	t.hp = t.max_hp()
	t.mp = t.max_mp()
	await st.unit_ops.op_unit_status({"args": [p.id, 11, 0, 0]})
	p.cls = old + 1
	if t.node and not Game.instant:
		Audio.se(0x21)
		for i in 16:
			t.node.flash = ((i >> 1) + 1) / 15.0
			await st.wait(0.05)
		t.node.set_entry(t.sprite_entry())
		t.node.show_frame(UnitSprite.Sheet.SPC, 4)
		Audio.se(0x0c)
		for i in 16:
			t.node.flash = ((16 - i) >> 1) / 15.0
			await st.wait(0.05)
		t.node.flash = 0.0
	await st.ui.message("%s的兵种提升为%s！" % [InfoWindow.display_name(p), p.class_name_str()])
	for s in 68:
		var lv: Dictionary = Game.strategy(s).get("learn_level_by_class", {})
		var a := int(lv.get(str(old), 0))
		var b := int(lv.get(str(old + 1), 0))
		if a == 0 and b != 0 and b <= p.level:
			await st.ui.message("学会了「%s」策略！" % str(Game.strategy(s).get("name", "?")))


func _consume(entry: Dictionary) -> void:
	var iid := int(entry["id"])
	if int(entry.get("slot", -1)) >= 0:
		Game.remove_bag_slot(int(entry["slot"]))
	else:
		Game.remove_item_id(iid)
