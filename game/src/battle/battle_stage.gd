class_name BattleStage
extends ScriptHost
## Battle (S_xx) runner.
## Scene 0 of an S file = deployment + pre-battle events (change_scene mode 3 creates the field),
## scene 1 = event loop polled at battle checkpoints while the turn loop runs,
## later scenes = aftermath (linear). See docs/rules.md §9-§10 and docs/eex.md §4.

signal unit_died(u: BUnit)

const PH_PLAYER := 0
const PH_FRIEND := 1
const PH_ENEMY := 2
## 暗杀 (strategy 21): per-slot countdown, per-slot assassin, and the "it hit" toggle (0x43c058).
const ASSASSIN_MARK := 0x569f00
const ASSASSIN_LINK := 0x569f73
const ASSASSIN_HIT := 0x569fe7
## The unit the player commands: its pid, set each time its move UI opens (mod 0x4d2865 in 0x43d538).
const CMD_PID := 0x4cf310
## 1 while a 绝招 runs (0x4d3007).
const SPECIAL_RUNNING := 0x4cf314
## The player's last move (0x43da45 → 0x4d8f1f, 0x409120): the step count, and the cells as x | y << 8,
## path[0] = start … path[n] = end, then 0xffff. The count is cleared after each command (0x43e21c).
const PATH_LEN := 0x4cfbfc
const PATH := 0x4cfc00
## 连续策略: set after a first cast by a unit with effect 83; strategies then cost double (0x4d0d71, 0x425ad0).
const SECOND_CAST := 0x4d0d61
## The enemy commander (u16 R+0x3d06 of the script reader 0x492f90, from op 0x45; 0xffff = none): double
## experience for its defeat, and 狂澜 cannot hit it (0x43b73f).
const BOSS := 0x496c96

var view: BattleView
var hud: BattleHUD
var minimap: Minimap
var units: Array[BUnit] = []
var deploy: Array = []            # 115 deployment entries (R+0x2044)
var sortie: Array[int] = []       # persons chosen to sortie (0x48b350 list)
var turn := 0
var turn_limit := 0
var ended_by_49 := false        # op 0x49 ended the battle (result 2)
var level_offset := 0
var boss_pid: int:
	get:
		var v := Mem.r16(BOSS)
		return -1 if v == 0xffff else v
	set(v): Mem.w16(BOSS, 0xffff if v < 0 else v)
var leader_pid := -1
var climate := 0
var weather_level := 1
var phase := PH_PLAYER
var field_ready := false
var battle_over := false
var victory := false
var map_id := -1
var victory_text := ""
var goal_text := ""
var actions: BattleActions
var ai: BattleAI
var input: BattleInput
var commands: BattleCommands
## The opcode handlers and rules kept in classes of their own (the VM looks for op_<name> there too, EexVM.handlers).
var deployment: BattleDeploy
var phase_fx: BattlePhase
var unit_ops: BattleUnitOps
var field_ops: BattleFieldOps
var _restore: Dictionary = {}
var _in_checkpoint := false
var current_unit: BUnit
var range_unit: BUnit        # [0x4dc7dd]: the unit whose move range the player opened last (0x43d5f3)
var terrain_changes: Array = []
var _occ: Dictionary = {}    # cell → unit, see unit_at
var _occ_gen := -1
var _resumed := false        # loaded from a save made during the player phase: its start already happened
## The weather of each climate's six levels (0x48e100, read from memory; rules.md "Weather"): 0 晴 1 阴 2 雨 3 暴雨 4 雪.
const WEATHER_ROWS := 0x48e100
const WEATHER_NAMES := ["晴", "阴", "雨", "暴雨", "雪"]


func _init() -> void:
	deployment = BattleDeploy.new(self)
	phase_fx = BattlePhase.new(self)
	unit_ops = BattleUnitOps.new(self)
	field_ops = BattleFieldOps.new(self)


func op_handlers() -> Array[Object]:
	return [deployment, unit_ops, field_ops]


func _ready() -> void:
	super._ready()
	boss_pid = -1
	view = BattleView.new()
	add_child(view)
	view.long_press_ok = func(c: Vector2i) -> bool: return unit_at(c) != null
	view.input_enabled = false
	view.show_cursor = false
	hud = BattleHUD.new()
	hud.stage = self
	ui.add_child(hud)
	ui.move_child(hud, 0)
	minimap = Minimap.new()
	minimap.st = self
	ui.add_child(minimap)
	ui.move_child(minimap, 1)
	actions = BattleActions.new(self)
	ai = BattleAI.new(self)
	input = BattleInput.new(self)
	commands = BattleCommands.new(self)
	for s in 115:
		var u := BUnit.at(s)
		units.append(u)
	for i in 115:
		deploy.append({"person": 0xffff})


func _exit_tree() -> void:
	if hud and is_instance_valid(hud):
		hud.queue_free()
	if minimap and is_instance_valid(minimap):
		minimap.queue_free()
	if duel and is_instance_valid(duel):
		duel.queue_free()     # it lives in the UI layer, which outlasts the stage


# ------------------------------------------------------------------ main loop
func run_file(file: String) -> void:
	vm = EexVM.new()
	vm.host = self
	vm.handlers = op_handlers()
	if not vm.load_script(file):
		return
	if not _restore.is_empty():
		await _apply_restore()
	# scene 0: deployment & opening events
	while vm.active and vm.scene == 0:
		var ran: bool = await vm.poll()
		if not ran:
			break
	if vm.active and vm.scene == 1 and field_ready:
		if Game.hooks.skip_battle(self):
			vm.scene = mini(2, vm.scene_count() - 1)
		else:
			await battle_loop()
	# aftermath scenes
	while vm.active:
		var ran2: bool = await vm.poll()
		if not ran2:
			break
	hud.visible = false
	minimap.visible = false
	SoundMap.stop_loop()


func battle_loop() -> void:
	if turn == 0:
		turn = 1
	Game.hooks.battle_start(self)
	view.input_enabled = true
	view.show_cursor = true
	hud.visible = true
	# 0x44f053: 战斗时，自动显示战场缩小图
	minimap.setup(self)
	if Settings.on(Settings.MINIMAP) and not Game.instant:
		minimap.open()
	while not _battle_finished():
		# 0x44eec5: once the rounds reach the turn limit the battle is lost before another one starts
		if turn > turn_limit and not _resumed:
			await _time_over()
			break
		# ---- player phase
		phase = PH_PLAYER
		Mem.w8(BattleInput.FIND_INDEX, 0)        # 检索未执行部队 starts over each turn (0x44efac)
		await hud.phase_banner(phase_banner_text(PH_PLAYER))
		if _resumed:
			_resumed = false
		else:
			await checkpoint()
			if _battle_finished(): break
			await remove_dead()
			await phase_fx._phase_start_effects(0, 35)
			if _battle_finished(): break
		await input.player_phase()
		if _battle_finished(): break
		# ---- friend phase (AI-controlled units among 0..34); its events run even without such units (0x44e851)
		phase = PH_FRIEND
		var friends := _has_ai_units(0, 35)
		await checkpoint()
		if _battle_finished(): break
		if friends:
			await ai.run_phase(0, 35)
			if _battle_finished(): break
		# ---- enemy phase
		phase = PH_ENEMY
		await hud.phase_banner(phase_banner_text(PH_ENEMY))
		await checkpoint()
		if _battle_finished(): break
		await remove_dead()
		await phase_fx._phase_start_effects(35, 115)
		if _battle_finished(): break
		await ai.run_phase(35, 115)
		if _battle_finished(): break
		# ---- next round
		for u in units:
			if u.exists():
				u.moved = false
				u.acted = false
				if u.node:
					u.node.greyed = false
		turn += 1
		Mem.w8(0x4b3d0a, turn - 1)   # ctx+2 (0x44e851) holds turn − 1; ctx+1 is the battle-over flag
		if await Game.hooks.round_end(self):
			break
		await set_weather(6)
	view.input_enabled = false
	view.show_cursor = false
	view.clear_highlights()


func trace_info() -> String:
	return "turn %d phase %d" % [turn, phase]


func _battle_finished() -> bool:
	return battle_over or not vm.active or vm.scene != 1 or not is_inside_tree()


func _has_ai_units(a: int, b: int) -> bool:
	for i in range(a, b):
		var u := units[i]
		if u.active() and u.mode != 7:
			return true
	return false


## Time over (0x44eec5): "因为战斗时间过长，撤退。" (a timed box), 管毅's unit (person 0) among slots 0..34 leaves the
## map, or slot 0's when there is none; the result is 3, which the scene loop 0x42c223 ends the game with (0x20).
func _time_over() -> void:
	await ui.message("因为战斗时间过长，撤退。")
	var gone := false
	for s in 35:
		if units[s].exists() and units[s].pid == 0:
			await unit_ops.remove_unit(units[s], false)
			gone = true
	if not gone and units[0].state == BUnit.STATE_ON_MAP:
		await unit_ops.remove_unit(units[0], false)
	battle_over = true
	await Game.main.game_over()
	vm.abort = true
	vm.active = false


## The phase banner (0x44ac28): "我军阶段" with "第%2u回合", or "最终回合" from the turn limit on, at the player
## phase (0x44ed93); "敌军阶段" at the enemy phase (0x44e851); the friendly phase has none.
func phase_banner_text(ph: int) -> String:
	if ph == PH_ENEMY:
		return "敌军阶段"
	if turn_limit > 0 and turn >= turn_limit:
		return "我军阶段\n最终回合"
	return "我军阶段\n第%2d回合" % turn


## Battle checkpoint (0x44c601): up to as many polls (0x4180c1) of the event scene as it has sections (0x410990),
## while the scene stays (0x44f7b0 reads the reader's offset, which only a new selection or a scene change resets).
## Each poll runs the last section whose conditions hold, so every section that qualifies runs within the
## checkpoint, and one that still qualifies afterwards (S_17's always-true 暗杀) runs again at each remaining poll.
## A poll that executed only memory ops (EexVM.PURE_OPS: no roll, nothing shown or waited for) and left memory as
## it was would be repeated exactly by every remaining one, so the loop stops there.
func checkpoint() -> void:
	if _in_checkpoint or not vm.active or vm.scene != 1:
		return
	_in_checkpoint = true
	var sc := vm.scene
	for i in vm.sections(sc).size():
		if not vm.active or vm.scene != sc:
			break
		var before := Mem.state_copy()
		vm.impure = 0
		await vm.poll()
		var after := Mem.state_copy()
		if vm.impure == 0 and after == before:
			break
	refresh_units()
	_in_checkpoint = false


## 0x413661 → 0x45965d in a battle: a person's line shows only when their first unit (slots 0..114, 0x45f670) is on
## the map; otherwise nothing is shown.
func speaks_now(pid: int) -> bool:
	if not in_battle():
		return true
	var s := BUnit.slot_of(pid)
	return s >= 0 and units[s].state == BUnit.STATE_ON_MAP


## 0x45b5fe(i), after a command or AI action: unit i becomes the current unit (the selectors 0x400..0x402; the
## original also hands the scripts its pid and cell) and, if it is still on the map (any HP) and the battle goes on,
## the event scene is polled.
func actor_poll(u: BUnit) -> void:
	current_unit = u
	if u.state == BUnit.STATE_ON_MAP and not _battle_finished():
		await checkpoint()


## op 0x4b: player deployment entry k → position (x, y), dir.
func op_op_4b(ins: Dictionary) -> void:
	if Mem.r32(Addr.TOWN_DEPLOY_ON) != 0:
		super.op_op_4b(ins)
		return
	var k := arg(ins, 0)
	if k < 0 or k >= 15:
		return
	var d: Dictionary = deploy[k]
	if int(d.get("person", 0xffff)) == 0xffff or int(d.get("flags", 0)) & 3 != 0:
		return
	d["x"] = arg(ins, 1)
	d["y"] = arg(ins, 2)
	d["dir"] = arg(ins, 3)
	d["hidden"] = arg(ins, 4) not in [0, 0xffff]
	d["flags"] = 4 if d["hidden"] else 0
	deploy[k] = d
	Mem.w8(BattleDeploy.DEPLOY + 64 * k + 4, arg(ins, 1) & 0xff)      # 0x415ef6: the entry's x, y stay for later battles
	Mem.w8(BattleDeploy.DEPLOY + 64 * k + 5, arg(ins, 2) & 0xff)


# ------------------------------------------------------------------ battlefield creation
## Touch shell: at the player phase's top level (no unit selected) its 菜单 is the right click there.
func menu_ready() -> bool:
	return input != null and input.idle


func open_menu() -> void:
	if menu_ready():
		view.right_from_pointer = false
		view.cell_clicked.emit(view.cursor_cell, MOUSE_BUTTON_RIGHT)


func op_change_scene(ins: Dictionary) -> void:
	var mode := arg(ins, 0)
	Mem.w8(Addr.SCENE_MODE, mode)        # scene object {mode, value}: mode 3 = the battlefield (0x40b922)
	if mode == 3:
		var v := arg(ins, 4)
		if v == 0xffff:
			v = 0
		await deployment.create_battlefield(v)
	else:
		# story-style picture inside a battle file (rare): show it full screen
		var val := 0
		match mode:
			0: val = arg(ins, 1)
			1: val = arg(ins, 2)
			2: val = arg(ins, 3)
		var entry := val + ({0: 0, 1: 114, 2: 40}.get(mode, 0) as int)
		hud.show_picture(Assets.tex("gfx/backgrounds/%03d.png" % entry))


## The active unit on cell c (the lowest slot if several), other than `exclude`. Looked up in a cell → unit
## table that is rebuilt only after a unit moved, appeared, left or fell (BUnit.gen), since the AI asks a lot.
func unit_at(c: Vector2i, exclude: BUnit = null) -> BUnit:
	if _occ_gen != BUnit.gen:
		_occ.clear()
		for u in units:
			if u.active() and not _occ.has(u.pos):
				_occ[u.pos] = u
		_occ_gen = BUnit.gen
	var hit: BUnit = _occ.get(c)
	if hit == null or hit != exclude:
		return hit
	for u in units:      # `exclude` stands there; is anyone else on the same cell?
		if u != exclude and u.active() and u.pos == c:
			return u
	return null


## The unit in the occupancy grid at c (0x435884): on the map, fallen ones too until they are removed.
func unit_on(c: Vector2i) -> BUnit:
	for u in units:
		if u.exists() and u.state == BUnit.STATE_ON_MAP and u.pos == c:
			return u
	return null


func unit_by_pid(pid: int) -> BUnit:
	for u in units:
		if u.exists() and u.pid == pid:
			return u
	return null


## Person selectors (UnitAt 0x45b371): 0x400 any unit, 0x401 a player-side unit (index < 35),
## 0x402 an enemy unit, else a person id. Only units on the map with HP > 0 count.
func units_for(pid: int) -> Array[BUnit]:
	var out: Array[BUnit] = []
	for u in units:
		if not u.active():
			continue
		if pid == 0x400 or (pid == 0x401 and u.slot < 35) or (pid == 0x402 and u.slot >= 35) or u.pid == pid:
			out.append(u)
	return out


## Side codes (0x44c8e6): 0 player, 1 friend, 2 enemy, 3 enemy-kind3, 4 player+friend, 5 all enemies, 6 all.
func side_match(u: BUnit, side: int) -> bool:
	var k := u.colour
	match side:
		0: return k == 0
		1: return k == 1
		2: return k == 2
		3: return k == 3
		4: return k <= 1
		5: return k >= 2
	return true


# ------------------------------------------------------------------ sprites
func refresh_units() -> void:
	for u in units:
		# a unit defeated in combat keeps its sprite until it has been removed, so the defeat animation can play
		var show: bool = u.exists() and u.state == BUnit.STATE_ON_MAP and (u.hp > 0 or u.extra.get("dying", false))
		if show and u.node == null:
			var n := UnitSprite.new()
			view.units_layer.add_child(n)
			u.node = n
		if u.node:
			if not show:
				u.node.queue_free()
				u.node = null
				continue
			if u.node.entry != u.sprite_entry() or u.node._mov == null:
				u.node.set_entry(u.sprite_entry())
			u.node.position = view.cell_pos(u.pos)
			# a frame of a scripted action stays only until the units are drawn again (as the map redraw does)
			if u.node.pose in [UnitSprite.Pose.STAND, UnitSprite.Pose.WEAK, UnitSprite.Pose.FIXED]:
				var weak := u.hp * 5 < u.max_hp() * 2   # below 40%: kneeling frames
				u.node.set_pose(UnitSprite.Pose.WEAK if weak else UnitSprite.Pose.STAND, u.dir)
			u.node.greyed = u.acted and u.is_player_side() and phase == PH_PLAYER
	hud.queue_redraw()


func _after_poke(addr: int) -> void:
	if addr >= Mem.UNITS and addr < Mem.UNITS + 115 * Mem.UNIT_SIZE:
		BUnit.gen += 1
		refresh_units()


func on_field_written(_field: int, _id: int) -> void:
	BUnit.gen += 1
	refresh_units()


func unit_hp_written(pid: int) -> void:
	var s := BUnit.slot_of(pid)
	if s >= 0 and Mem.r32s(Mem.unit_addr(s) + 0x10) <= 0:
		await actions.unit_defeated(units[s])


## 0x40b922: the scene object (0x4ac63c) is in mode 3, i.e. from change_scene 3 (the battlefield) on. Before it
## (deployment) and after a later change_scene (aftermath pictures) a battle file counts as story mode.
func in_battle() -> bool:
	return Mem.r8(Addr.SCENE_MODE) == 3


## Record the player's move (start cell, then each step) as the original does while walking.
func record_path(start: Vector2i, steps: Array[Vector2i]) -> void:
	var cells: Array[Vector2i] = [start]
	cells.append_array(steps)
	for i in cells.size():
		Mem.w16(PATH + 2 * i, cells[i].x | (cells[i].y << 8))
	Mem.w16(PATH + 2 * cells.size(), 0xffff)
	Mem.w8(PATH_LEN, steps.size())


## The recorded move, start first; empty when the count is 0.
func move_path() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var n := Mem.r8(PATH_LEN)
	if n == 0:
		return out
	for i in n + 1:
		var w := Mem.r16(PATH + 2 * i)
		out.append(Vector2i(w & 0xff, w >> 8))
	return out


## 0x44cc03: every unit still on the map at HP 0 leaves it (RemoveUnit). Run after each command and AI
## action, and at a phase start after the event poll (also op 0x54).
func remove_dead() -> void:
	for u in units:
		if u.exists() and u.state == BUnit.STATE_ON_MAP and u.hp <= 0:
			await unit_ops.remove_unit(u, false)
			unit_died.emit(u)


# ------------------------------------------------------------------ weather
func weather() -> int:
	return Mem.r8(WEATHER_ROWS + climate * 6 + clampi(weather_level, 0, 5))


## 0x449f91: the weather level becomes `w` when it is below 6, else takes a random step (c = level + 1 moves one
## towards rand(8), which is drawn either way; 0 wraps to level 5, 7 to level 0). When the weather shown changes,
## its picture (Xben.wa 0x34 + weather) plays in the middle of the screen.
func set_weather(w: int) -> void:
	var r := Rules.rand(8)
	var shown := weather()
	if w < 6:
		weather_level = w
	else:
		var c := weather_level + 1
		if c > r:
			c -= 1
		elif c < r:
			c += 1
		weather_level = 5 if c == 0 else (0 if c == 7 else c - 1)
	hud.queue_redraw()
	if weather() != shown and not Game.instant:
		var e := EffectPlayer.create("xben", 0x34 + weather())
		if e:
			e.position = ui.vsize() / 2
			ui.add_child(e)
			await e.done


## 0x44a1f9: the level a weather strategy sets, by its record's "weather" (the kind 0x44a1f9 is called with): 0
## 晴明 the climate's first level that is 晴, 1 叆叇 its first that is 阴, 2 阴雨 its last that is 雨, 暴雨 or 雪 (6
## when there is none: set_weather then steps at random).
func weather_strategy_level(s: int) -> int:
	var row := WEATHER_ROWS + climate * 6
	var kind := int(Game.strategy_rule(s).get("weather", 2))
	if kind < 2:
		var want := kind
		for b in 6:
			if Mem.r8(row + b) == want:
				return b
		return 6
	for b in range(5, -1, -1):
		if Mem.r8(row + b) in [2, 3, 4]:
			return b
	return 0


# ------------------------------------------------------------------ battle-time tests
func op_test_turn(ins: Dictionary) -> bool:
	return Game.compare(turn, arg(ins, 0), arg(ins, 1))


func op_test_side(ins: Dictionary) -> bool:
	return phase == arg(ins, 0)


## op 0x42 (0x411d63 → 0x44c658): default victory. The boss (op 0x45 a5) is among units 35..115 in state 3 or 4 (a
## boss not on the field, or still at HP 0 on it, is not enough), or no enemy-coloured unit (2, 3) is on the map
## (0x44c8e6 side 5; hidden 伏兵 not yet out do not count).
func op_test_event5(_ins: Dictionary) -> bool:
	if not field_ready:
		return false
	if boss_pid >= 0:
		for i in range(35, units.size()):
			if units[i].state in [3, 4] and units[i].pid == boss_pid:
				return true
	for u in units:
		if u.state == BUnit.STATE_ON_MAP and side_match(u, 5):
			return false
	return true


## op 0x43 (0x411d8e → 0x44c74d): default defeat. The protected leader (op 0x45 a7) is among units 0..35 in state 3
## or 4; or nobody is left: with 管毅 in unit 0 (its person dword 0), no unit 0..15 hidden or on the map (state 1 or
## 2, whatever its HP, so allies in slot 15 count); else no unit of colour 0 on the map (0x44c8e6 side 0). Or the
## turn limit has passed.
func op_test_event6(_ins: Dictionary) -> bool:
	if not field_ready:
		return false
	if leader_pid >= 0:
		for i in 36:
			if units[i].state in [3, 4] and units[i].pid == leader_pid:
				return true
	var any := false
	if Mem.r32(units[0].addr) == 0:
		for i in 16:
			if units[i].state in [BUnit.STATE_HIDDEN, BUnit.STATE_ON_MAP]:
				any = true
	else:
		for i in 115:
			if units[i].state == BUnit.STATE_ON_MAP and side_match(units[i], 0):
				any = true
	if not any:
		return true
	return turn_limit > 0 and turn > turn_limit


func op_test_unit_at(ins: Dictionary) -> bool:
	var c := Vector2i(arg(ins, 1), arg(ins, 2))
	for u in units_for(arg(ins, 0)):
		if u.pos == c:
			return true
	return false


func op_test_unit_in_area(ins: Dictionary) -> bool:
	var x0 := mini(arg(ins, 1), arg(ins, 3))
	var x1 := maxi(arg(ins, 1), arg(ins, 3))
	var y0 := mini(arg(ins, 2), arg(ins, 4))
	var y1 := maxi(arg(ins, 2), arg(ins, 4))
	for u in units_for(arg(ins, 0)):
		if u.pos.x >= x0 and u.pos.x <= x1 and u.pos.y >= y0 and u.pos.y <= y1:
			if OS.get_environment("WG_TRACE_BATTLE") != "":
				print("    in_area %s: slot %d %s at %s" % [ins["args"], u.slot, u.person.name, u.pos])
			return true
	return false


## op 0x2e (0x411a54 → 0x45afca): p2's unit in one of the 8 cells around p1's; loose == 0 also needs mutual attack
## ability. p1 is a person, never a selector: 0x400 and above match nothing (S_27's "1025 212 1" is never true).
## A selector p2 (≥ 0x200) ignores `loose`.
func op_test_adjacent(ins: Dictionary) -> bool:
	var loose := arg(ins, 2)
	if arg(ins, 0) >= 0x400:
		return false
	if arg(ins, 1) >= 0x200:
		loose = 1
	for ua in units_for(arg(ins, 0)):
		for ub in units_for(arg(ins, 1)):
			if ua == ub:
				continue
			var d := ub.pos - ua.pos
			if absi(d.x) <= 1 and absi(d.y) <= 1:
				if loose != 0:
					return true
				if actions.can_attack(ua, ub) and actions.can_attack(ub, ua):
					return true
	return false


## op 0x41 (0x41149d → 0x44c8e6): number of units of `side` in state 2, whatever their HP (rect_flag 1 → inside
## x1..x2, y1..y2 as given, a reversed rectangle counting nobody; else the whole map) compared with n. Sides 0–6
## as side_match; any other counts nobody.
func op_test_units_in_area(ins: Dictionary) -> bool:
	var side := arg(ins, 0)
	if side == 0xffff:
		side = 6
	var rect := arg(ins, 3) == 1
	var x0 := arg(ins, 4)
	var x1 := arg(ins, 6)
	var y0 := arg(ins, 5)
	var y1 := arg(ins, 7)
	var cnt := 0
	if side <= 6:
		for u in units:
			if u.state != BUnit.STATE_ON_MAP or not side_match(u, side):
				continue
			if rect and (u.pos.x < x0 or u.pos.x > x1 or u.pos.y < y0 or u.pos.y > y1):
				continue
			cnt += 1
	return Game.compare(cnt, arg(ins, 1), arg(ins, 2))


## op 0x36: attribute test of a person/unit (attr ids per op 0x38 table).
func op_test_attr(ins: Dictionary) -> bool:
	var v := BattleAttrs.get_attr(self, arg(ins, 0), arg(ins, 1))
	if v < 0:
		return false
	return Game.compare(v, arg(ins, 2), arg(ins, 3))


func op_set_attr(ins: Dictionary) -> void:
	await BattleAttrs.set_attr(self, arg(ins, 0), arg(ins, 1), arg(ins, 2), arg(ins, 3))
	refresh_units()


# ------------------------------------------------------------------ texts / UI ops
## op 0x3d's flag in a battle (0x45991b): the person's unit (on the map with HP; 0x400.. = the current unit)
## cheers (SE 8), SE 14, and the item's icon rises over it for 8 ticks; 5 more ticks.
func get_item_show(pid: int, iid: int) -> void:
	var u: BUnit = current_unit if pid >= 0x400 and pid <= 0x403 else (unit_by_pid(pid) if pid < 0x200 else null)
	if u == null or u.state != BUnit.STATE_ON_MAP or u.hp <= 0 or Game.instant:
		return
	await unit_ops.op_unit_status({"args": [u.pid, 1, 0, 0]})
	Audio.se(14)
	var tex := Assets.tex("gfx/icons/items/large/%03d.png" % int(Game.item(iid).get("icon", 0)))
	for i in 8:
		hud.icon_over = {"tex": tex, "cell": u.pos, "off": Vector2(8, 7 - i)}
		hud.queue_redraw()
		await wait(0.05)
	await wait(0.25)
	hud.icon_over = {}
	refresh_units()


## op 0x12 in a battle (0x411db9): the minimap is shown for the choice and hidden again if it was not open.
func op_choice(ins: Dictionary) -> void:
	var was := minimap.visible
	if field_ready and not Game.instant:
		minimap.open()
	await super.op_choice(ins)
	if not was:
		minimap.visible = false


## op 0x19 (0x413bd1): only stores the text (Reader+0x3d10) that the menu's 胜利条件 shows.
func op_victory_cond_text(ins: Dictionary) -> void:
	victory_text = sarg(ins, 0)


## 胜利条件 (menu 106, 0x449cec): the stored text in an OK box titled 胜利条件 ("现在无法显示" when it is empty or
## longer than 249 bytes); then the area of the last op 0x5b blinks again if that op had flag 0.
func show_victory() -> void:
	var t := victory_text
	if t == "" or t.to_multibyte_char_buffer("GBK").size() > 249:
		t = "现在无法显示"
	await MsgBox.ok(ui, t, "胜利条件")
	await field_ops.blink_goal(false)


func op_battle_goal_text(ins: Dictionary) -> void:
	goal_text = sarg(ins, 0)
	await hud.goal_sequence(goal_text, turn_limit)


## op 0x49: the battle is over (both outcomes) — leave the turn loop. Result 2: after the file main asks
## "保存进度吗？" (0x44ebfd).
func op_ui_49(_ins: Dictionary) -> void:
	battle_over = true
	ended_by_49 = true


## op 0x0e: battle lost → game over.
func op_ui_0e(_ins: Dictionary) -> void:
	battle_over = true
	if OS.get_environment("WG_TRACE_BATTLE") != "":
		print("GAME OVER at turn %d" % turn)
	await Game.main.game_over()
	vm.abort = true
	vm.active = false


func op_ui_5a(_ins: Dictionary) -> void:
	await hud.start_banner()


## op 0x54 (0x415771): in a battle, units at HP 0 leave the map (0x44cc03).
func op_ui_54(_ins: Dictionary) -> void:
	await remove_dead()


func op_scroll_to(ins: Dictionary) -> void:
	await view.center_on(Vector2i(arg(ins, 0), arg(ins, 1)))


func _dialog_top(pid: int) -> bool:
	var u := unit_by_pid(pid)
	if u and u.active():
		var sp := view.cell_pos(u.pos) - view.camera.position
		return sp.y > 260
	return false


func on_speaker(pid: int) -> void:
	var u := unit_by_pid(pid)
	if u and u.active():
		await view.ensure_visible(u.pos)


## op 0x69 (0x4335d0): a "|name" banner is shown over the darkened field (0x4d64ea … 0x4d6576).
func op_popup(ins: Dictionary) -> void:
	if sarg(ins, 0).begins_with("|") and field_ready:
		await view.set_dim(true)
		await super(ins)
		await view.set_dim(false)
		return
	await super(ins)


## A unit's line in a portrait window (0x45965d / 0x459777), as the scripts' battle dialogue shows it.
func unit_say(pid: int, text: String) -> void:
	await on_speaker(pid)
	await ui.dialog.talk(speaker_face(pid), Game.person(pid).name, text, _dialog_top(pid))


# ------------------------------------------------------------------ save / restore
func save_state() -> Dictionary:
	return {"kind": "battle", "scene": vm.scene if vm else 0, "turn": turn, "phase": phase, "map": map_id,
		"turn_limit": turn_limit, "boss": boss_pid, "leader": leader_pid, "climate": climate,
		"weather_level": weather_level, "deploy": deploy, "field_ready": field_ready,
		"victory_text": victory_text, "goal_text": goal_text, "bgm": Audio.current_track,
		"terrain_changes": terrain_changes.map(func(e: Dictionary) -> Dictionary:
			var c := e.duplicate()
			c.erase("node")
			return c)}


func restore_state(d: Dictionary) -> void:
	_restore = d


func _apply_restore() -> void:
	var d := _restore
	_restore = {}
	if d.get("kind", "") != "battle":
		return
	BUnit.gen += 1      # the units came back with the memory: the occupancy caches (Skills, unit_at) are stale
	vm.scene = int(d.get("scene", 0))
	turn = int(d.get("turn", 1))
	if bool(d.get("field_ready", false)):
		Mem.w32(Skills.MAP_NO, int(d.get("map", 0)) & 0xff)
	_resumed = vm.scene == 1 and int(d.get("phase", PH_PLAYER)) == PH_PLAYER and bool(d.get("field_ready", false))
	turn_limit = int(d.get("turn_limit", 0))
	boss_pid = int(d.get("boss", -1))
	leader_pid = int(d.get("leader", -1))
	climate = int(d.get("climate", 0))
	weather_level = int(d.get("weather_level", 1))
	deploy = d.get("deploy", deploy)
	victory_text = str(d.get("victory_text", ""))
	goal_text = str(d.get("goal_text", ""))
	if OS.get_environment("WG_SAVETEST") != "":
		print("SAVETEST restoring battle turn %s scene %s" % [d.get("turn"), d.get("scene")])
	if bool(d.get("field_ready", false)) and int(d.get("map", -1)) >= 0:
		map_id = int(d["map"])
		ui.clear_strips()            # as create_battlefield: a load from a town leaves no town panes up
		ui.meter.visible = false
		view.load_map(map_id, false)
		# the terrain bytes came back with the memory; redraw the changed tiles
		terrain_changes = []
		for e: Dictionary in d.get("terrain_changes", []):
			var c := Vector2i(int(e["x"]), int(e["y"]))
			var patch := int(e["patch"])
			var node: Node = null
			if patch == 0xff:
				pass                 # a patch left undrawn (EV[0] = 1)
			elif patch >= 4:
				node = view.add_patch(2 * patch - 8, c)
			else:
				view.add_mark(patch, c)
			var e2 := e.duplicate()
			e2["node"] = node
			terrain_changes.append(e2)
		field_ready = true
		refresh_units()
		var lead := units[0]
		if lead.active():
			view.center_on(lead.pos, false)
	if int(d.get("bgm", -1)) >= 0:
		Audio.play_bgm(int(d["bgm"]))
	ui.set_black(false)


## op 0x52 (battle): selectors 0x400..0x402 mean the current unit.
func op_op_52(ins: Dictionary) -> void:
	var pid := arg(ins, 0)
	if pid >= 0x400 and pid <= 0x402 and current_unit:
		ins = ins.duplicate(true)
		ins["args"][0] = current_unit.pid
	super.op_op_52(ins)
	refresh_units()


func wait(sec: float) -> void:
	if fast or sec <= 0 or Game.instant:
		return
	await get_tree().create_timer(sec).timeout


# ------------------------------------------------------------------ duel (单挑) ops 0x5f-0x68
var duel: DuelLayer

func _duel() -> DuelLayer:
	if duel == null:
		duel = DuelLayer.new()
		duel.stage = self
		ui.add_child(duel)
		# under the dialog box / menus, above the map HUD
		ui.move_child(duel, ui.dialog.get_index())
	return duel


## 0x68 (0x44999f): duel between two persons on the map, 3rd arg = GHAI backdrop; plays the intro.
func op_duel_setup(ins: Dictionary) -> void:
	await _duel().setup(arg(ins, 0), arg(ins, 1), arg(ins, 2))


## 0x60 (0x449480): fighter appears (fade from white), optional action, then speaks.
func op_duel_say(ins: Dictionary) -> void:
	await _duel().appear_say(arg(ins, 0), sarg(ins, 1), arg(ins, 2))


## 0x61 (0x448ff5, parser name misleading): start of the fight ("胜 负").
func op_duel_end(_ins: Dictionary) -> void:
	await _duel().open()


## 0x5f (0x4498e0, parser name misleading): close the duel; restores BGM, gives the winner's EXP.
func op_duel_start(_ins: Dictionary) -> void:
	if duel:
		await duel.close()


## 0x63 (0x4431af): speech bubble (empty text erases it).
func op_duel_say2(ins: Dictionary) -> void:
	await _duel().say2(arg(ins, 0), sarg(ins, 1), arg(ins, 2))


## 0x64 (0x448524): single-fighter action 0..15.
func op_duel_action(ins: Dictionary) -> void:
	await _duel().action(arg(ins, 0), arg(ins, 1))


## 0x65 (0x448394): one blow with a scripted outcome.
func op_duel_action2(ins: Dictionary) -> void:
	await _duel().exchange(arg(ins, 0), arg(ins, 1), arg(ins, 2))


## 0x66 (0x44847b): special attack.
func op_duel_action3(ins: Dictionary) -> void:
	await _duel().special(arg(ins, 0), arg(ins, 1), arg(ins, 2))


## 0x62 (0x4490da): result — arg = winner side; loser greyed, EXP computed.
func op_duel_62(ins: Dictionary) -> void:
	await _duel().result(arg(ins, 0))


## op 0x6d (0x410cfc): move (or, last arg 1, re-enter) a unit to the position of another person's
## unit offset by (dx, dy) (values > 40 mean −(v−40)).
func op_op_6d(ins: Dictionary) -> bool:
	var sel := arg(ins, 0)
	if sel == 0xffff:
		sel = 0
	var reenter := arg(ins, 7) == 1
	var pid := 0xffff
	if sel == 1 and arg(ins, 2) < 15:
		var su := units[arg(ins, 2)]
		if su.exists() and su.state == (3 if reenter else 2):
			pid = su.pid
	elif sel == 0:
		pid = arg(ins, 1)
	if pid >= 0x400:
		return false
	var ref := unit_by_pid(arg(ins, 3))
	if ref == null:
		return false
	var dx := arg(ins, 4)
	var dy := arg(ins, 5)
	var x := ref.pos.x + dx if dx < 0x29 else maxi(ref.pos.x - (dx - 0x28), 0)
	var y := ref.pos.y + dy if dy < 0x29 else maxi(ref.pos.y - (dy - 0x28), 0)
	var u := unit_by_pid(pid)
	if u == null:
		return false
	if reenter:
		# 0x4591a1: a retreated unit with a deployment entry re-enters (SE 15, the map centres on it)
		if u.state == 3 and not unit_ops._entry_of(u).is_empty():
			deployment._unit_reenter(u, x, y, arg(ins, 6) if arg(ins, 6) != 0xffff else 2)
			refresh_units()
			Audio.play_se("se15")
			await view.center_on(u.pos)
	elif u.state == BUnit.STATE_ON_MAP:
		await unit_ops._script_move(u, Vector2i(x, y), arg(ins, 6))
	return true
