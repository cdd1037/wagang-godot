extends Node
## Story-scene walking as in the original (op 0x32 → 0x429159): step codes 0 = -Y, 1 = +X, 2 = +Y, 3 = -X, the
## axis with the larger distance first (X on a tie), facing each step, a final facing above 3 → 0.
## Prints "t_rpgwalk: PASS".

var _ok := true


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("t_rpgwalk: FAIL ", what)
		_ok = false


func run() -> void:
	_check(RpgActor.walk_steps(0, 0, 2, -5) == [0, 0, 0, 0, 0, 1, 1], "longer -Y first: %s" % [RpgActor.walk_steps(0, 0, 2, -5)])
	_check(RpgActor.walk_steps(0, 0, 3, 3) == [1, 1, 1, 2, 2, 2], "tie: X first: %s" % [RpgActor.walk_steps(0, 0, 3, 3)])
	_check(RpgActor.walk_steps(5, 5, 3, 5) == [3, 3], "-X: %s" % [RpgActor.walk_steps(5, 5, 3, 5)])
	_check(RpgActor.walk_steps(5, 5, 5, 5).is_empty(), "no move")
	var a := RpgActor.new()
	add_child(a)
	a.setup(1, 1, 30, 30, 2, 0)
	var seen: Array[int] = []
	var watch := func() -> void:
		while a.walking or seen.is_empty():
			if a.walking and (seen.is_empty() or seen[-1] != a.dir):
				seen.append(a.dir)
			await get_tree().process_frame
	watch.call()
	await a.walk_to(31, 26, -1, false)        # up-right on screen (-Y) for 4 steps, then down-right (+X)
	_check(a.gx == 31 and a.gy == 26, "arrives at (31,26): (%d,%d)" % [a.gx, a.gy])
	_check(seen == [0, 1], "faces up-right (0) then down-right (1) while walking: %s" % [seen])
	await a.walk_to(31, 26, 0xFFFF, true)
	_check(a.dir == 0, "a final facing of 0xFFFF becomes 0: %d" % a.dir)
	await a.walk_to(29, 26, 2, true)
	_check(a.dir == 2 and a.gx == 29, "final facing 2 after walking -X")
	a.queue_free()
	_route()
	print("t_rpgwalk: PASS" if _ok else "t_rpgwalk: FAILED")


## The walk grid (0x429266 / 0x42869c): open ground as walk_steps; around a wall through its gap, every cell
## clear for the 3 × 3 footprint; no walk at all to a walled-in target; x + 2 must stay inside (an exit to x 98
## stops at 97); Buha.wa entry 66's 管毅 walk to (28, 22) (R_16) cannot reach it.
func _route() -> void:
	RpgActor.set_blocked(PackedByteArray())
	for c in [[30, 30, 31, 26], [30, 30, 36, 33], [50, 50, 40, 44], [20, 60, 20, 60]]:
		_check(RpgActor.route(c[0], c[1], c[2], c[3]) == RpgActor.walk_steps(c[0], c[1], c[2], c[3]),
				"open ground %s: %s" % [c, RpgActor.route(c[0], c[1], c[2], c[3])])
	var b := PackedByteArray()
	b.resize(RpgActor.GW * RpgActor.GH)
	for y in RpgActor.GH:
		if y < 50 or y > 56:
			b[y * RpgActor.GW + 40] = 1
	RpgActor.set_blocked(b)
	var r: Variant = RpgActor.route(30, 40, 50, 40)
	_check(r != null, "a way through the gap")
	if r != null:
		var p := Vector2i(30, 40)
		var clear := true
		for d in r:
			p += Vector2i(RpgActor.STEP_DX[d], RpgActor.STEP_DY[d])
			clear = clear and RpgActor._fit(p)
		_check(p == Vector2i(50, 40) and clear and p.y <= 56, "arrives through clear cells: %s" % p)
		_check(r.size() > 20, "longer than the straight line (%d)" % r.size())
	for y in range(48, 58):
		b[y * RpgActor.GW + 40] = 1
	RpgActor.set_blocked(b)
	_check(RpgActor.route(30, 40, 50, 40) == null, "walled off: no route")
	var a := RpgActor.new()
	add_child(a)
	a.setup(1, 1, 30, 40, 2, 0)
	a.walk_to(50, 40, 0, true)
	_check(a.gx == 30 and a.gy == 40 and a.dir == 2 and not a.walking, "no walk and no turn")
	a.queue_free()
	RpgActor.set_blocked(PackedByteArray())
	var e: Variant = RpgActor.route(92, 64, 98, 64)
	_check(e != null and e.size() == 5, "an exit to x 98 stops at 97: %s" % [e])
	RpgActor.load_grid(66)
	_check(RpgActor.route(28, 54, 28, 22) == null, "Buha 66: (28, 22) is walled in")
	_check(RpgActor.route(28, 54, 40, 40) != null, "Buha 66: open ground is reachable")
	RpgActor.load_grid(-1)
