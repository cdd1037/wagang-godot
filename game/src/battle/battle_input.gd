class_name BattleInput
extends RefCounted
## Player-phase interaction (CCZ-style): select a unit → show move range → move → command menu.

var st: BattleStage
var end_turn := false
var idle := false              # the player phase waits at its top level (no unit selected; touch shell's 菜单)
var waiting_cell := false      # a click on the map is awaited (any level: unit, move, target), for the UI bot


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
	waiting_cell = true
	var r: Array = await st.view.cell_clicked
	waiting_cell = false
	return r


func player_phase() -> void:
	end_turn = false
	if not st.view.cell_hovered.is_connected(st.hud.set_hover):
		st.view.cell_hovered.connect(st.hud.set_hover)
	var pu := _player_units()
	if not pu.is_empty():
		await st.view.center_on(pu[0].pos)
		st.view.cursor_cell = pu[0].pos
	if await Game.hooks.player_phase(self):     # the input bot (WG_INPUTBOT, WG_FXTEST) when the build has it
		return
	if Game.auto_input:
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
		# 0x44e0d9: SE 0 on a top-level left click; an empty cell shows its terrain box, then SE 1
		var u := st.unit_at(cell)
		if u == null:
			Audio.se(0)
			if st.view.in_bounds(cell):
				await st.hud.terrain_popup(cell)
			Audio.se(1)
			continue
		# 0x43d538: a unit with code 7 and no flag 0x80 (mod 0x4d6268: any slot) is commanded unless it is 混乱
		# (state 5), 迷失 (7) or has acted (6); any other unit is 这是非受控部队 (state 1; state 0, 这是敌军部队,
		# needs a slot ≥ 115 since the mod)
		if u.mode != 7 or u.slot >= 115 or u.flags & BUnit.F_PASS:
			await show_unit_ranges(u, "这是非受控部队")
		elif u.status & (BUnit.ST_CONFUSION | BUnit.ST_LOST):
			Audio.se(0)
			await _confused_move_ui(u)
		elif u.acted:
			await show_unit_ranges(u, "已经行动完毕。")
		else:
			var did := await select_unit(u)
			await after_command(u, did)
			# checked after each action only, so units all under 乱 do not end the phase; 否 keeps it going
			if did and _all_done() and not st._battle_finished() and await _confirm_end():
				break
	st.view.clear_highlights()


## Autoplay: let the AI drive player units (for headless smoke tests).
func _auto_player_phase() -> void:
	for u in _player_units():
		if st._battle_finished():
			return
		if u.active() and not u.acted:
			await Game.hooks.before_auto_unit(st, u)
			var did := await st.ai.act(u)
			Game.hooks.after_auto_unit()
			await after_command(u, did)


## After a command (0x44e0d9): `u` is the current unit (0x44e452) and, while it is on the map and the battle goes
## on, the event scene is polled (0x45b5fe) — before the fallen leave, so a section can still see a unit at HP 0
## on the map (S_13's 杨素第一次死 restores 杨素's HP). If the command did something, units left at HP 0 leave the
## map (0x44cc03) and the scene is polled again.
func after_command(u: BUnit, did: bool) -> void:
	await st.actor_poll(u)
	if not did:
		return
	await st.remove_dead()
	if not st._battle_finished():
		await st.checkpoint()


## A unit that is not commanded now: its ranges, then a click on the map brings SE 2 and `why` (0x43d821 …
## 0x43d931), a cancel SE 1.
func show_unit_ranges(u: BUnit, why: String) -> void:
	Audio.se(0)
	_show_ranges(u, st.actions.reachable(u))
	var r := await _click()
	st.view.clear_highlights()
	await _refused(r, why)


func _refused(r: Array, why: String) -> void:
	if r[1] == MOUSE_BUTTON_RIGHT or Game.touch or not st.view.in_bounds(r[0]):     # touch: a tap dismisses
		Audio.se(1)
		return
	Audio.se(2)
	await st.ui.message(why)


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
				# port convenience: a click on another unit to command takes it up
				if other.status & (BUnit.ST_CONFUSION | BUnit.ST_LOST):
					return await select_unit(other)
				u = other
				continue
			if Game.touch:
				return false          # touch: a tap outside cancels, as in the pickers
			# 0x43d776..0x43d7f4: SE 2, and the pick stays open
			Audio.se(2)
			if other and st.actions.reachable(u, {}, true).has(cell):
				await st.ui.message("因为有其他部队，所以不能移动。")
			else:
				await st.ui.message("不是移动范围。")
			continue
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
	# 0x43d8e0 (state 5) / 0x43ee03 (state 7): SE 2 and the message, a cancel SE 1
	await _refused(r, "正处于混乱状态。" if u.status & BUnit.ST_CONFUSION else "正处于迷失状态。")


## The walk of the move UI, recorded as the original does (0x43da45; a click on the unit's own cell records
## nothing).
func _walk(u: BUnit, path: Array[Vector2i]) -> void:
	if not path.is_empty():
		st.record_path(u.pos, path)
	await st.actions.move_unit(u, path)


const COMMANDS := ["攻击", "绝招", "围攻", "策略", "交给", "道具", "待命"]
## Their CmdIcon.dll icons (0x45bd05, mod 0x4d034d): sword, sword, sword, scroll, hand-over, pouch, tent.
const COMMAND_ICONS := [0, 0, 0, 1, 4, 2, 3]


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
		var i := await st.ui.menu.choose(COMMANDS, sp, true, "", en, 60, 0, Callable(), command_icons())
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


static func command_icons() -> Array:
	return UIStyle.cmd_icons(COMMAND_ICONS)


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
## null on a cancel. `kind` 1-4 with `actor` and `param`: the hover panel shows that forecast (0x4541a9 → 0x4404bd).
## Kinds 3 and 4 pick from one's own side (0x45533d modes 3 / 4), the others from the other side. As there: with
## nobody of that side in range a message and SE 1 close it at once; a click outside the range is SE 2 and
## "不在范围之内。", one on the wrong side SE 2 and its message; a cancel is SE 1.
func pick_unit(cells: Array[Vector2i], ok: Callable, kind := 0, actor: BUnit = null, param := -1) -> BUnit:
	var own := kind in [3, 4]
	if actor != null and not _side_in(cells, actor, own):
		await _nobody_in_range(own)
		return null
	st.view.set_attack_cells(cells)
	show_forecast(kind, actor, param, cells)
	while true:
		var r := await _click()
		if _cancels(r, cells):
			st.view.clear_highlights()
			show_forecast(0)
			Audio.se(1)
			return null
		if not cells.has(r[0]):
			Audio.se(2)
			await st.ui.message("不在范围之内。")
			continue
		var t := st.unit_at(r[0])
		if t == null:
			continue
		if actor != null and not await _side_ok(t, actor, own):
			continue
		if ok.call(t):
			st.view.clear_highlights()
			show_forecast(0)
			return t
	return null


## Strategy handlers that pick their target with 0x45533d (the self-cast ones, 飓风, the weather, 聚气 / 豪气, 暝思 and
## 白虎, do not).
const PICKER_HANDLERS := ["damage", "stat", "status", "heal", "again", "bazhen", "xuanwu", "qinglong"]


## 0x436586 as 0x45533d calls it: is a living unit of the wanted group (0x406710: slot < 35 or not) on the cells?
func _side_in(cells: Array, actor: BUnit, own: bool) -> bool:
	for c in cells:
		var t := st.unit_at(c)
		if t and t.hp > 0 and ((t.slot < 35) == (actor.slot < 35)) == own:
			return true
	return false


## 0x455479..0x4554a7: "范围内没有…部队。" (style 2 box), then the picker's SE 1.
func _nobody_in_range(own: bool) -> void:
	await st.ui.message("范围内没有我军部队。" if own else "范围内没有敌军部队。")
	Audio.se(1)


## 0x4555f9 / 0x455659: a unit of the wrong group is refused with SE 2 and "这是敌军部队。" / "不能攻击我军部队。".
func _side_ok(t: BUnit, actor: BUnit, own: bool) -> bool:
	if ((t.slot < 35) == (actor.slot < 35)) == own:
		return true
	Audio.se(2)
	await st.ui.message("这是敌军部队。" if own else "不能攻击我军部队。")
	return false


## Kind 0 ends the forecast.
func show_forecast(kind: int, actor: BUnit = null, param := -1, cells: Array = []) -> void:
	st.hud.forecast = {} if kind == 0 or actor == null else {"kind": kind, "actor": actor, "param": param, "cells": cells}
	st.hud.queue_redraw()


## 攻击 (0x43dada). 引导攻击 (effect 46, 0x43db4e): while the target falls, the next one in reach is attacked at
## once. 连续攻击 (effect 90): after the first attack, if the attacker stands and is not 乱, 怯 or 迷, the event
## scene is polled and the fallen removed (0x4d2ab2), and one more target may be picked; cancelling it ends the
## action.
func _do_attack(u: BUnit) -> bool:
	var again := false
	while true:
		var t := await pick_unit(st.actions.attack_cells(u, u.pos), func(x: BUnit) -> bool: return x.is_enemy_of(u) and x.active(), 1, u)
		if t == null:
			return again
		Mem.w8(BattleActions.STRIKE, 0)        # cave 0x407651, then the attack wrapper 0x4d7808
		await st.actions.attack_cmd(u, t)
		while t.hp == 0 and u.has_effect(46):
			var nt := st.actions.guided_target(u)
			if nt == null:
				break
			Mem.w8(BattleActions.STRIKE, 0)
			await st.actions.attack_cmd(u, nt)
			t = nt
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
		await st.ui.message("正处于穷计状态。")
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
			await st.ui.message(why)       # 0x41fec9 with its message
			continue
		var cells := st.actions.strategy_cast_cells(u, s)
		# the handlers that pick a unit with 0x45533d (rules.md §5.1): mode 2 at the other side, 3 at one's own
		var own := int(Game.strategy(s).get("target", 0)) == 1
		var picks := Rules.handler(s) in PICKER_HANDLERS
		if picks and not _side_in(cells, u, own):
			await _nobody_in_range(own)
			continue                  # the strategy list again (0x43dc4e)
		st.view.set_attack_cells(cells)
		# 0x42335b / 0x423549 and the others: kind 2 at the other side, 3 at one's own (2 + (arg ≠ 0))
		show_forecast(3 if own else 2, u, s, cells)
		var chosen := false
		while true:
			var r := await _click()
			if _cancels(r, cells):
				Audio.se(1)
				break
			var c: Vector2i = r[0]
			if not cells.has(c):
				if picks:
					Audio.se(2)
					await st.ui.message("不在范围之内。")
				continue
			var main := st.unit_at(c)
			if picks:
				if main == null:
					continue
				if not await _side_ok(main, u, own):
					continue
			var tg := st.actions.strategy_targets(u, s, c)
			if tg.is_empty() and Rules.handler(s) != "weather":
				if main and not st.actions.usable_on(u, s, main):
					# 0x420422's messages for a player-commanded caster; a refusal ends the cast (the list again)
					var cat := Rules.strat_category(s) if s < 0x3e else 17
					if cat <= 3:
						await st.ui.message("不能在这里使用。")
					elif cat == 15 and main == u:
						Audio.se(2)         # 0x420869: SE 2 before the message
						await st.ui.message("不能对自己使用。")
					break
				continue
			# the picked unit is cast on at once (0x42335b: picker, usability test 0x420422, cast; no question)
			st.view.clear_highlights()
			show_forecast(0)
			await st.actions.cast(u, s, c)
			chosen = true
			break
		st.view.clear_highlights()
		show_forecast(0)
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
	var iid := int(entry["id"])
	show_forecast(4, u, iid, cells)
	var t70 := BattleActions.item_checked_after(iid)
	# the own-side picker (0x45533d mode 4): a cancel plays SE 1; outside the range SE 2 + "不在范围之内。"; a unit
	# of the other group SE 2 + "这是敌军部队。". Fruits, 仙人果 and 印绶 take any own unit and refuse afterwards.
	while true:
		var r := await _click()
		if _cancels(r, cells):
			st.view.clear_highlights()
			show_forecast(0)
			Audio.se(1)
			return false
		var c: Vector2i = r[0]
		if not cells.has(c):
			Audio.se(2)
			await st.ui.message("不在范围之内。")
			continue
		var t := st.unit_at(c)
		if t == null:
			continue
		if (t.slot < 35) != (u.slot < 35):
			Audio.se(2)
			await st.ui.message("这是敌军部队。")
			continue
		if not t70 and not st.actions.item_usable_on(iid, t):
			continue
		st.view.clear_highlights()
		show_forecast(0)
		return await st.actions.use_item(u, entry, t)
	return false


## The menu bar (SystemMenu); its battle-only commands are here. 结束回合 asks first (0x449cae →
## "结束所有部队的命令吗？").
func system_menu() -> void:
	await SystemMenu.open(st.ui, st, _battle_command)


func _battle_command(id: String) -> void:
	match id:
		"end_turn":
			if await _confirm_end():
				end_turn = true
		"find_unit":
			await find_unit()
		"victory":
			await st.show_victory()
		"minimap":
			st.minimap.open()


func _confirm_end() -> bool:
	return await MsgBox.yes_no(st.ui, "结束所有部队的命令吗？")


## 检索未执行部队 (state 7 of 0x44e0d9 → 0x44e706): the player's own units (slots 0..34, colour 0, code 7, on the
## map, neither moved nor finished, not 混乱) in slot order; the index [0x4b4238] steps on before it is used and
## starts again at 0 each turn. The map goes to that unit and the cursor onto it; nothing is selected. With none
## left: "没有可以行动的部队。", then the end-of-phase question.
const FIND_INDEX := 0x4b4238


func find_unit() -> void:
	var lst: Array[BUnit] = []
	for i in 35:
		var u := st.units[i]
		if u.state == BUnit.STATE_ON_MAP and u.mode == 7 and u.colour == 0 and not u.moved and not u.acted \
				and not (u.status & BUnit.ST_CONFUSION):
			lst.append(u)
	if lst.is_empty():
		await MsgBox.ok(st.ui, "没有可以行动的部队。")
		if await _confirm_end():
			end_turn = true
		return
	var k := Mem.r8(FIND_INDEX) + 1
	if k >= lst.size():
		k = 0
	Mem.w8(FIND_INDEX, k)
	var u := lst[k]
	await st.view.center_on(u.pos)
	st.view.cursor_cell = u.pos
	st.hud.set_hover(u.pos)
