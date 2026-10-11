class_name BattleInput
extends RefCounted
## Player-phase interaction (CCZ-style): select a unit → show move range → move → command menu.

var st: BattleStage
var end_turn := false
var idle := false              # the player phase waits at its top level (no unit selected; touch shell's 菜单)
var _bot: InputBot


func _init(s: BattleStage) -> void:
	st = s


func _player_units() -> Array[BUnit]:
	var out: Array[BUnit] = []
	for i in range(0, 35):
		var u := st.units[i]
		if u.active() and u.mode == 7:
			out.append(u)
	return out


## No player unit left that can act: confused (乱) units do not count (0x44e0d9).
func _all_done() -> bool:
	for u in _player_units():
		if not u.acted and not (u.status & BUnit.ST_CONFUSION):
			return false
	return true


func _click() -> Array:
	var r: Array = await st.view.cell_clicked
	return r


func player_phase() -> void:
	end_turn = false
	if not st.view.cell_hovered.is_connected(st.hud.set_hover):
		st.view.cell_hovered.connect(st.hud.set_hover)
	var pu := _player_units()
	if not pu.is_empty():
		await st.view.center_on(pu[0].pos)
		st.view.cursor_cell = pu[0].pos
	var botdir := OS.get_environment("WG_INPUTBOT")
	if botdir != "":
		if _bot == null:
			_bot = InputBot.new(st, botdir)
			st.add_child(_bot)
		if st.turn > int(OS.get_environment("WG_BOTTURNS") if OS.get_environment("WG_BOTTURNS") != "" else "2"):
			st.get_tree().quit()
			return
		_bot.run_phase()
	elif Game.autoplay or Game.demo:
		var fx := OS.get_environment("WG_FXTEST")
		if fx != "":
			# debug: cast these strategies with autoplay (dialogue skipped) and print each target's outcome
			if _bot == null:
				_bot = InputBot.new(st, "")
				st.add_child(_bot)
			await _bot.fx_test(fx.split(","))
			return
		await _auto_player_phase()
		return
	if pu.is_empty():
		return      # no unit to command (0x44e0d9)
	while not end_turn and not st._battle_finished():
		idle = true
		var r := await _click()
		idle = false
		if st._battle_finished():
			break
		var cell: Vector2i = r[0]
		var btn: int = r[1]
		if btn == MOUSE_BUTTON_RIGHT:
			# 0x44e0d9: a right click on any unit opens 武将情报; elsewhere (and Esc / 菜单) the system menu
			var ru := st.unit_at(cell) if st.view.right_from_pointer else null
			if ru:
				await InfoWindow.open_unit(st.ui, st, ru)
			else:
				await system_menu()
			continue
		var u := st.unit_at(cell)
		if u == null:
			continue
		if u.mode == 7 and u.slot < 115 and not u.acted:     # mod 0x4d6268: any slot (no script gives an enemy code 7)
			var did := await select_unit(u)
			await after_command()
			if did and _all_done():
				break       # checked after each action only, so units all under 乱 do not end the phase
		else:
			await show_unit_ranges(u)
	st.view.clear_highlights()


## Autoplay: let the AI drive player units (for headless smoke tests).
func _auto_player_phase() -> void:
	for u in _player_units():
		if st._battle_finished():
			return
		if u.active() and not u.acted:
			await st.ai.act(u)
			await after_command()


## After a command (0x44e0d9): units left at HP 0 leave the map (0x44cc03), then the event scene is polled.
func after_command() -> void:
	await st.remove_dead()
	if not st._battle_finished():
		await st.checkpoint()


func show_unit_ranges(u: BUnit) -> void:
	_show_ranges(u, st.actions.reachable(u))
	await _click()
	st.view.clear_highlights()


## Returns true when a unit finished its action.
func select_unit(u: BUnit) -> bool:
	Audio.play_se("se00")
	Mem.w32(BattleStage.CMD_PID, u.pid)      # mod 0x4d2865: the unit being commanded
	if u.status & (BUnit.ST_CONFUSION | BUnit.ST_LOST):
		await _confused_move_ui(u)
		return false
	while true:
		Mem.w32(BattleStage.CMD_PID, u.pid)
		st.range_unit = u                     # [0x4dc7dd] (0x43d5f3)
		var parents := {}
		var reach := st.actions.reachable(u, parents)
		_show_ranges(u, reach)
		var r := await _click()
		st.view.clear_highlights()
		if st._battle_finished():
			return false
		var cell: Vector2i = r[0]
		if r[1] == MOUSE_BUTTON_RIGHT:
			return false
		if not reach.has(cell):
			var other := st.unit_at(cell)
			if other and other != u and other.mode == 7 and other.slot < 115 and not other.acted:
				if other.status & (BUnit.ST_CONFUSION | BUnit.ST_LOST):
					return await select_unit(other)
				u = other
				continue
			return false
		var orig := u.pos
		var orig_dir := u.dir
		await _walk(u, Grid.path_to(parents, u.pos, cell))
		var done := await command_menu(u)
		Mem.w8(BattleStage.PATH_LEN, 0)       # 0x43e21c
		if done:
			st.refresh_units()
			return true
		# cancelled: undo the move
		u.pos = orig
		u.dir = orig_dir
		u.moved = false
		st.refresh_units()
	return false


func _show_ranges(u: BUnit, reach: Dictionary) -> void:
	st.view.set_move_cells(reach)
	var atk: Array[Vector2i] = []
	for c in reach:
		for a in st.actions.attack_cells(u, c):
			if not reach.has(a) and not atk.has(a):
				atk.append(a)
	st.view.set_attack_cells(atk)


## 0x43d544 / 0x43d5f8: a confused or lost unit's range is shown, and a click on the map only brings up the
## message.
func _confused_move_ui(u: BUnit) -> void:
	st.view.set_move_cells(st.actions.reachable(u))
	var r := await _click()
	st.view.clear_highlights()
	if r[1] != MOUSE_BUTTON_RIGHT and st.view.in_bounds(r[0]):
		await st.ui.popup("正处于混乱状态。" if u.status & BUnit.ST_CONFUSION else "正处于迷失状态。")


## The walk of the move UI, recorded as the original does (0x43da45; a click on the unit's own cell records
## nothing).
func _walk(u: BUnit, path: Array[Vector2i]) -> void:
	if not path.is_empty():
		st.record_path(u.pos, path)
	await st.actions.move_unit(u, path)


const COMMANDS := ["攻击", "绝招", "围攻", "策略", "交给", "道具", "待命"]


## The command menu (dialog 279, 0x43dde3), until the unit has finished: 攻击 绝招 围攻 策略 交给 道具 待命.
## After each command that ends the action, 再移动 (0x4d27a0). Returns false when the menu is cancelled (the
## caller undoes the move).
func command_menu(u: BUnit) -> bool:
	while not u.acted:
		var targets := st.actions.attackable_targets(u, u.pos)
		var strats := st.actions.known_strategies(u)
		var items := st.actions.usable_items()
		var en := [not targets.is_empty(), st.commands.special_enabled(), st.commands.siege_enabled(u),
				not strats.is_empty(), st.commands.give_enabled(u), not items.is_empty(), true]
		var sp := st.view.cell_pos(u.pos) - st.view.camera.position + Vector2(56, -10)
		var i := await st.ui.menu.choose(COMMANDS, sp, true, "", en, 60)
		if i < 0:
			st.actions.kill_rewards()
			return false
		Mem.set_ev(10, 0)          # mod 0x43e16b: no unit has fallen in this command yet
		var done := false
		match i:
			0: done = await _do_attack(u)
			1: done = await st.commands.special(u)
			2: done = await st.commands.siege_command(u)
			3: done = await _do_strategy(u, strats)
			4: done = await st.commands.give_command(u)
			5: done = await _do_item(u, items)
			6: done = true
		if done:
			await st.actions.end_action(u)
			await _move_again(u)
		st.actions.kill_rewards()
	return true


## 再移动 (effect 82, 0x4d27a0): after an action the unit may move once more, from where it stands; then its action
## ends again. (The original also offers it to a unit that fell in its own attack; the port does not.)
func _move_again(u: BUnit) -> void:
	if not (u.moved and u.acted and u.has_effect(82)) or not u.active():
		return
	u.flags = u.flags & ~6
	st.refresh_units()
	Mem.w32(BattleStage.CMD_PID, u.pid)
	if u.status & (BUnit.ST_CONFUSION | BUnit.ST_LOST):
		await _confused_move_ui(u)
	else:
		st.range_unit = u
		var parents := {}
		var reach := st.actions.reachable(u, parents)
		while true:
			_show_ranges(u, reach)
			var r := await _click()
			st.view.clear_highlights()
			var cell: Vector2i = r[0]
			if r[1] == MOUSE_BUTTON_RIGHT or cell == u.pos:
				break
			if reach.has(cell):
				await _walk(u, Grid.path_to(parents, u.pos, cell))
				break
	await st.actions.end_action(u)


## Picking a target: a right click cancels; with touch controls so does a tap outside the highlighted cells
## (a tap inside them that hits no target is ignored, as with a mouse).
func _cancels(r: Array, cells: Array) -> bool:
	return r[1] == MOUSE_BUTTON_RIGHT or (Game.touch and not cells.has(r[0]))


## The unit picker (0x45533d): highlights `cells` and returns the unit clicked on them that `ok` accepts, or
## null on a cancel.
func pick_unit(cells: Array[Vector2i], ok: Callable) -> BUnit:
	st.view.set_attack_cells(cells)
	while true:
		var r := await _click()
		if _cancels(r, cells):
			st.view.clear_highlights()
			return null
		var t := st.unit_at(r[0])
		if t and cells.has(t.pos) and ok.call(t):
			st.view.clear_highlights()
			return t
	return null


## 攻击 (0x43dada). 连续攻击 (effect 90): after the first attack, if the attacker stands and is not 乱, 怯 or 迷,
## the event scene is polled and the fallen removed (0x4d2ab2), and one more target may be picked; cancelling it
## ends the action.
func _do_attack(u: BUnit) -> bool:
	var again := false
	while true:
		var t := await pick_unit(st.actions.attack_cells(u, u.pos), func(x: BUnit) -> bool: return x.is_enemy_of(u) and x.active())
		if t == null:
			return again
		Mem.w8(BattleActions.STRIKE, 0)        # cave 0x407651, then the attack wrapper 0x4d7808
		await st.actions.attack_cmd(u, t)
		if again or not u.has_effect(90) or not u.active() or (u.status & (BUnit.ST_CONFUSION | BUnit.ST_FEAR | BUnit.ST_LOST)):
			return true
		await st.checkpoint()
		await st.remove_dead()
		if st._battle_finished():
			return true
		again = true
	return true


## 策略 (0x43dc21). Under 穷计 only the message. 连续策略 (effect 83): after a first cast the list opens again and
## strategies cost double; cancelling it ends the action (0x4d0d71).
func _do_strategy(u: BUnit, strats: Array[int]) -> bool:
	if u.status & BUnit.ST_SEAL:
		Audio.play_se("se02")
		await st.ui.popup("正处于穷计状态。")
		return false
	while true:
		var labels := []
		var en := []
		for s in strats:
			var sd := Game.strategy(s)
			labels.append("%s　%d" % [sd.get("name", "?"), st.actions.strategy_cost(u, s)])
			en.append(st.actions.can_cast(u, s))
		var i := await st.ui.menu.choose(labels, Vector2(-1, -1), true, "策略　（策略值 %d）" % u.mp, en, 160)
		if i < 0:
			if Mem.r8(BattleStage.SECOND_CAST) == 1:
				Mem.w8(BattleStage.SECOND_CAST, 0)
				return true
			return false
		var s: int = strats[i]
		var why := st.actions.cast_refusal(u, s)
		if why != "":
			await st.ui.popup(why)       # 0x41fec9 with its message
			continue
		var cells := st.actions.strategy_cast_cells(u, s)
		st.view.set_attack_cells(cells)
		var chosen := false
		while true:
			var r := await _click()
			if _cancels(r, cells):
				break
			var c: Vector2i = r[0]
			if not cells.has(c):
				continue
			var tg := st.actions.strategy_targets(u, s, c)
			if tg.is_empty() and not (s in [58, 59, 60]):
				var main := st.unit_at(c)
				if main and not st.actions.usable_on(u, s, main):
					# 0x420422's messages for a player-commanded caster
					var cat: int = Rules.STRAT_CATEGORY[s] if s < Rules.STRAT_CATEGORY.size() else 17
					if cat <= 3:
						await st.ui.popup("不能在这里使用。")
					elif cat == 15 and main == u:
						await st.ui.popup("不能对自己使用。")
				continue
			st.view.set_area_cells(st.actions.strategy_area(u, s, c))
			var hr := 100
			if not tg.is_empty():
				hr = Rules.strat_hit(u, tg[0], s, st.view.terrain_at(tg[0].pos), st.weather(), 0, true)
			var ok := await st.ui.menu.choose(["执行（成功率 %d%%）" % hr, "取消"], Vector2(-1, -1), true)
			st.view.set_area_cells([])
			if ok == 0:
				st.view.clear_highlights()
				await st.actions.cast(u, s, c)
				chosen = true
				break
		st.view.clear_highlights()
		if chosen and not st.actions.second_cast(u):
			return true
	return false


func _do_item(u: BUnit, items: Array) -> bool:
	var labels := []
	for e in items:
		var it := Game.item(int(e["id"]))
		var cnt := ("×%d" % int(e["count"])) if e.has("count") else ""
		labels.append("%s %s" % [it.get("name", "?"), cnt])
	var i := await st.ui.menu.choose(labels, Vector2(-1, -1), true, "道具", [], 160)
	if i < 0:
		return false
	var entry: Dictionary = items[i]
	var cells: Array[Vector2i] = [u.pos]
	for d in Grid.DIRS:
		cells.append(u.pos + d)
	st.view.set_attack_cells(cells)
	while true:
		var r := await _click()
		if _cancels(r, cells):
			st.view.clear_highlights()
			return false
		var t := st.unit_at(r[0])
		if t and cells.has(t.pos) and not t.is_enemy_of(u) and st.actions.item_usable_on(int(entry["id"]), t):
			st.view.clear_highlights()
			await st.actions.use_item(u, entry, t)
			return true
	return false


## 部队一览: every unit on the field by side; picking one centres the camera and shows its 武将情报 (0x47ade4).
func unit_list() -> void:
	var lst: Array[BUnit] = []
	var labels := []
	for side_name in [["我军", 0, 15], ["友军", 15, 35], ["敌军", 35, 115]]:
		for i in range(side_name[1], side_name[2]):
			var u := st.units[i]
			if u.active():
				lst.append(u)
				labels.append("%s %s　%s Lv%d　兵 %d/%d%s" % [side_name[0], u.person.name, u.person.class_name_str(), u.level(), u.hp, u.max_hp(), "　（已行动）" if u.acted and i < 35 else ""])
	if lst.is_empty():
		return
	while true:
		var k := await st.ui.menu.choose(labels, Vector2(-1, -1), true, "部队一览", [], 320)
		if k < 0:
			return
		var u := lst[k]
		await st.view.center_on(u.pos)
		st.view.cursor_cell = u.pos
		st.hud.set_hover(u.pos)
		await InfoWindow.open_unit(st.ui, st, u)


func system_menu() -> void:
	var i := await st.ui.menu.choose(["回合结束", "部队一览", "胜利条件", "存储进度", "读取进度", "回到标题"], Vector2(-1, -1), true)
	var main: Node = Game.main
	match i:
		0:
			end_turn = true
		1:
			await unit_list()
		2:
			await st.ui.dialog.talk(null, "", st.victory_text if st.victory_text != "" else st.goal_text, false)
		3:
			await main.save_menu()
		4:
			await main.load_menu()
		5:
			main.to_title()
