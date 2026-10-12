class_name BattleFieldOps
extends RefCounted
## Changes to the battlefield: terrain changes and their undo (ops 0x21 / 0x58, the record that saves carry), the
## marked goal area (op 0x5b) and its blink.

var st: BattleStage


func _init(s: BattleStage) -> void:
	st = s


## op 0x5b (0x416cbb): in a battle, the area (x1, y1)–(x2, y2) is stored (ctx+0xc..0xf) with ctx+8 = (flag == 0),
## then shown (0x45a0ce): the map goes to its middle and it blinks three times. With flag 0 胜利条件 shows it again.
const GOAL_FLAG := 0x4b3d10

const GOAL_AREA := 0x4b3d14


func op_op_5b(ins: Dictionary) -> void:
	if not st.in_battle():
		return
	var flag := st.arg(ins, 4)
	if flag == 0xffff:
		flag = 0
	for k in 4:
		Mem.w8(GOAL_AREA + k, st.arg(ins, k))
	Mem.w32(GOAL_FLAG, 1 if flag == 0 else 0)
	await blink_goal(flag != 0)


## 0x45a0ce: when ctx+8 is set (or `force`), centre the stored area (clamped to the map) and blink it 3 times,
## 0.5 s on and 0.5 s off.
func blink_goal(force: bool) -> void:
	if Mem.r32(GOAL_FLAG) == 0 and not force:
		return
	var a := [Mem.r8(GOAL_AREA), Mem.r8(GOAL_AREA + 1), Mem.r8(GOAL_AREA + 2), Mem.r8(GOAL_AREA + 3)]
	var x1: int = mini(a[0], st.view.map_w - 1)
	var y1: int = mini(a[1], st.view.map_h - 1)
	var x2: int = mini(a[2], st.view.map_w - 1)
	var y2: int = mini(a[3], st.view.map_h - 1)
	if x1 > x2 or y1 > y2:
		return
	var cx := x1 + ((x2 - x1 + 1) / 2 if x2 - x1 > 2 else 0)
	var cy := y1 + ((y2 - y1 + 1) / 2 if y2 - y1 > 2 else 0)
	await st.view.center_on(Vector2i(cx, cy))
	var cells: Array[Vector2i] = []
	for y in range(y1, y2 + 1):
		for x in range(x1, x2 + 1):
			cells.append(Vector2i(x, y))
	for k in 3:
		st.view.goal_cells = cells
		await st.wait(0.5)
		st.view.goal_cells = []
		await st.wait(0.5)


## op 0x58: alt 0 → ChangeTerrain (0x456140): terrain change at (x, y) with an overlay mark (patch < 4) or a
## 3x3 map patch (Nima.wa 2*patch-8). alt ≠ 0 → mod 0x4d7dc5: with scroll set, terrain byte (x, y) = terrain;
## then the recorded change (x, y, patch) is undone (0x4567c1), e.g. a fire put out.
func op_op_58(ins: Dictionary) -> void:
	var patch := st.arg(ins, 0)
	var alt := st.arg(ins, 1)
	var terr := st.arg(ins, 2)
	var c := Vector2i(st.arg(ins, 3), st.arg(ins, 4))
	var scroll := st.arg(ins, 5)
	var silent := st.arg(ins, 6)
	if not st.view.in_bounds(c):
		return
	if scroll == 0xffff:
		scroll = 0
	if alt == 0:
		await _change_terrain(c, terr, patch, scroll, silent != 0 and silent != 0xffff)
	else:
		if scroll != 0:
			st.view.set_terrain(c, terr & 0xff)
		await _revert_terrain(c, patch, scroll)
	st.refresh_units()


## ChangeTerrain (0x456140 → 0x4561e3): record (x, y, new, old, patch) for saves and undo, set the terrain, show
## the mark or the map patch. Unless `quiet` (op arg 6 ≠ 0): scroll → camera to the cell, and the sounds: a mark
## 0 / 2 (fire) plays SE 0x13 and holds 1 tick; a patch to 0x0c plays SE 16, to 0x0f SE 15, to 0x11 城门 SE 18 with
## a 1.5 s hold when no 城门 is beside it, else a 2.5 s hold (both holds only while 听音效 is on). The 7th argument
## is byte EV[0] (mod patch at 0x416833): 1 leaves the map patch undrawn and unrecorded.
func _change_terrain(c: Vector2i, terr: int, patch: int, scroll: int, quiet: bool) -> void:
	if scroll != 0 and not quiet:
		await st.view.center_on(c)
	var no_patch := Mem.r8(Mem.EV) == 1
	var old := st.view.terrain_at(c)
	st.view.set_terrain(c, terr)
	var gate_next := terr == 0x11 and _gate_beside(c)
	var node: Node = null
	if patch < 4:
		st.view.add_mark(patch, c)
		if not quiet:
			if patch in [0, 2]:
				Audio.se(0x13)
			await st.wait(0.05)
	else:
		if not no_patch:
			node = st.view.add_patch(2 * patch - 8, c)
		if not quiet:
			match terr:
				0x0c:
					Audio.se(16)
				0x0f:
					Audio.se(15)
				0x11:
					if not gate_next:
						Audio.se(18)
						if Settings.on(Settings.SE):
							await st.wait(1.5)
		if not quiet and gate_next and Settings.on(Settings.SE):
			await st.wait(2.5)
	st.terrain_changes.append({"x": c.x, "y": c.y, "new": terr, "old": old, "patch": 0xff if no_patch and patch >= 4 else patch,
		"silent": quiet, "node": node})


## A 城门 (0x11) left, right, above or below c.
func _gate_beside(c: Vector2i) -> bool:
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if st.view.in_bounds(c + d) and st.view.terrain_at(c + d) == 0x11:
			return true
	return false


## 0x4567c1: undo the first recorded change at (x, y) with this patch (none → nothing): scroll → camera to the
## cell; the mark or the map patch goes, the old terrain comes back. Undoing a 城门 (new terrain 0x11) plays SE 18
## and holds 1.5 s when another 城门 is beside it, else holds 2.5 s (holds only while 听音效 is on).
func _revert_terrain(c: Vector2i, patch: int, scroll: int) -> void:
	for i in st.terrain_changes.size():
		var e: Dictionary = st.terrain_changes[i]
		if int(e["x"]) != c.x or int(e["y"]) != c.y or int(e["patch"]) != patch:
			continue
		if scroll != 0:
			await st.view.center_on(c)
		if patch < 4:
			st.view.marks.erase(c)
			st.view.overlay.queue_redraw()
		else:
			var gate := int(e["new"]) == 0x11
			var gate_next := gate and _gate_beside(c)
			if gate_next:
				Audio.se(18)
				if Settings.on(Settings.SE):
					await st.wait(1.5)
			var n: Variant = e.get("node")
			if n and is_instance_valid(n):
				(n as Node).queue_free()
			if gate and not gate_next and Settings.on(Settings.SE):
				await st.wait(2.5)
		st.view.set_terrain(c, int(e["old"]))
		st.terrain_changes.remove_at(i)
		return


## op 0x21 map_mark (0x413efb): x, y, mode, scroll, silent (0xffff → 0). Mode 0 sets fire: ChangeTerrain to
## terrain 0x1a 火 with overlay mark 0; mode 1 puts it out (undo of the patch-0 change there).
func op_map_mark(ins: Dictionary) -> void:
	var c := Vector2i(st.arg(ins, 0), st.arg(ins, 1))
	var mode := st.arg(ins, 2)
	var scroll := st.arg(ins, 3)
	var silent := st.arg(ins, 4)
	if scroll == 0xffff:
		scroll = 0
	if silent == 0xffff:
		silent = 0
	if not st.view.in_bounds(c):
		return
	if mode == 0:
		await _change_terrain(c, 0x1a, 0, scroll, silent == 1)
	elif mode == 1:
		await _revert_terrain(c, 0, scroll)
	st.refresh_units()
