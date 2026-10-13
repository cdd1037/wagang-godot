class_name RpgActor
extends Node2D
## A character in a story (R) scene. Isometric half-cell coordinates (x, y, z).
## Screen mapping (0x4272c5 with camX=60, camY=25, W=200, scene view at y=40):
##   foot point (sx, sy) = (8*(x-y) + 312, 4*(x+y) - 8*z - 152); 48x64 frame drawn at (sx, sy-64).
## Directions (actor +0x2e = sprite row): 0 up-right (-Y, back view), 1 down-right (+X, mirrored front),
## 2 down-left (+Y, front), 3 up-left (-X, mirrored back) — the walk step tables dx@0x48b8c0 = (0,1,0,-1),
## dy@0x48b8b0 = (-1,0,1,0); each step sets +0x2e to its code (0x42a4f5).
## Actions (table 0x48b920): 0 = walk cycle frames [0,1,0,2] (idle shows frame 0),
## 1..17 = single pose frame action+2, 18 = nothing.

const FW := 48
const FH := 64
const STEP_TIME := 0.055     # at 武将移动速度 普通; the scene's frame period scales it (Settings.scene_frame)

var pid := -1
var sprite_id := 0
var gx := 0
var gy := 0
var gz := 0
var dir := 2
var action := 0
var frame := 0
var walking := false
var _sheet: Texture2D
var _anim_t := 0.0


func setup(person_id: int, spr: int, x: int, y: int, d: int, act: int) -> void:
	pid = person_id
	set_sprite(spr)
	gx = x
	gy = y
	dir = d & 3
	set_action(act)
	_place()


func set_sprite(spr: int) -> void:
	sprite_id = spr
	_sheet = Assets.tex("gfx/rpg_sprites/%03d.png" % spr)
	queue_redraw()


func set_action(a: int) -> void:
	action = a if a <= 18 else 0
	frame = 0 if action == 0 else action + 2
	queue_redraw()


static func foot_point(x: int, y: int, z: int = 0) -> Vector2:
	return Vector2(8 * (x - y) + 312, 4 * (x + y) - 8 * z - 152)


func foot() -> Vector2:
	return foot_point(gx, gy, gz)


func _place() -> void:
	position = foot()
	z_index = int(position.y)
	queue_redraw()


func screen_rect() -> Rect2:
	return Rect2(position + Vector2(0, -FH), Vector2(FW, FH))


func _draw() -> void:
	if action == 18 or _sheet == null:
		return
	var src := Rect2(frame * FW, dir * FH, FW, FH)
	draw_texture_rect_region(_sheet, Rect2(0, -FH, FW, FH), src)


func _process(delta: float) -> void:
	if walking:
		_anim_t += delta
		var seq := [0, 1, 0, 2]
		var f: int = seq[int(_anim_t / (0.12 * _speed())) % 4]
		if f != frame:
			frame = f
			queue_redraw()


const STEP_DX := [0, 1, 0, -1]
const STEP_DY := [-1, 0, 1, 0]


## The story-scene loop runs one frame per GS+8 × 50 ms (0x429908): 普通 1, 慢 2, 快 unthrottled.
func _speed() -> float:
	return Settings.scene_frame() / 0.05


## Direction codes of the steps from (x0, y0) to (x1, y1) in open ground: along the axis with the larger distance
## first, X on a tie (0x42855f), keeping the direction while it still gets closer (0x42836e). `route` gives the same
## in open ground; this is its shorthand.
static func walk_steps(x0: int, y0: int, x1: int, y1: int) -> Array[int]:
	var dx := x1 - x0
	var dy := y1 - y0
	var sx: Array[int] = []
	for i in absi(dx):
		sx.append(1 if dx > 0 else 3)
	var sy: Array[int] = []
	for i in absi(dy):
		sy.append(2 if dy > 0 else 0)
	if absi(dy) > absi(dx):
		sy.append_array(sx)
		return sy
	sx.append_array(sy)
	return sx


# ------------------------------------------------------------------ the walk grid (Buha.wa)
## The RPG scene's walk grid: Buha.wa's entry for the scene's image (0x428857, on entering mode 2 through 0x429ff6),
## 100 × 100 words after a 16-byte header; a cell whose word has the high byte 0xF0 is blocked (0x4270d3), and so
## is any cell outside. The exported mask (backgrounds/buha/NNN.png, 200 × 100 bytes) keeps the words' bytes.
const GW := 100
const GH := 100
const FAR := 0xfefe
## 1 where the 3 × 3 footprint of an actor standing on the cell is clear (0x4271c7: rows y − 2 .. y, columns x .. x + 2).
static var _fits := PackedByteArray()
static var grid_image := -1


static func load_grid(image: int) -> void:
	grid_image = image
	var blocked := PackedByteArray()
	blocked.resize(GW * GH)
	var rel := "gfx/backgrounds/buha/%03d.png" % image
	var img := Assets.image(rel) if image >= 0 and FileAccess.file_exists(Assets.ROOT + rel) else null
	if img:
		if img.get_format() != Image.FORMAT_L8:
			img.convert(Image.FORMAT_L8)
		var d := img.get_data()
		if img.get_width() == 2 * GW and img.get_height() == GH:
			for y in GH:
				for x in GW:
					blocked[y * GW + x] = 1 if d[y * 2 * GW + 2 * x + 1] == 0xf0 else 0
	set_blocked(blocked)


## `blocked`: GW × GH cells, 1 = blocked (the checks set one directly).
static func set_blocked(blocked: PackedByteArray) -> void:
	if blocked.size() < GW * GH:
		blocked = PackedByteArray()
		blocked.resize(GW * GH)
	_fits.resize(GW * (GH + 2))
	for y in GH + 2:
		for x in GW:
			var ok := 1
			for r in range(y - 2, y + 1):
				for c in range(x, x + 3):
					if r < 0 or c < 0 or r >= GH or c >= GW or blocked[r * GW + c] != 0:
						ok = 0
			_fits[y * GW + x] = ok


static func _fit(c: Vector2i) -> bool:
	if _fits.is_empty():
		set_blocked(PackedByteArray())
	return _fits[c.y * GW + c.x] != 0


## A step of 0x4281c7 from c in direction d with the 3 × 3 footprint, or (-1, -1) off the grid: the new x and x + 2
## inside, and y − 2 inside with y − 4 ≥ 0 (its check takes the height off twice).
static func _step(c: Vector2i, d: int) -> Vector2i:
	var n := c + Vector2i(STEP_DX[d], STEP_DY[d])
	if n.x < 0 or n.x + 2 >= GW or n.y - 4 < 0 or n.y - 2 >= GH:
		return Vector2i(-1, -1)
	return n


## The first direction of a walk (0x42855f): along the axis with the larger distance, X on a tie.
static func first_dir(x0: int, y0: int, x1: int, y1: int) -> int:
	if x0 < x1:
		if y0 < y1:
			return 2 if x1 - x0 < y1 - y0 else 1
		return 0 if x1 - x0 < y0 - y1 else 1
	if y0 < y1:
		return 2 if x0 - x1 < y1 - y0 else 3
	return 0 if x0 - x1 < y0 - y1 else 3


## The steps of op 0x32's walk (0x429159): a distance field from the target (0x429266, each cell's neighbours in
## the order of the step codes, a clear cell one more than the cell it was reached from, a blocked one marked and
## left), which stops as soon as it reaches the walker's cell; then from there downhill (0x42869c → 0x42836e): of
## the clear neighbours the lowest, below the current cell, trying the last step's direction first (the first one
## from 0x42855f). null when the field never reaches the walker: the original does not walk at all then, nor turn.
static func route(x0: int, y0: int, x1: int, y1: int) -> Variant:
	var dist := PackedInt32Array()
	dist.resize(GW * (GH + 2))
	dist.fill(FAR)
	var start := Vector2i(x0, y0)
	var goal := Vector2i(x1, y1)
	if goal.x < 0 or goal.x >= GW or goal.y < 0 or goal.y >= GH + 2:
		return null
	dist[goal.y * GW + goal.x] = 0
	if start != goal:
		var queue: Array[Vector2i] = [goal]
		var head := 0
		var found := false
		while head < queue.size() and not found:
			var c := queue[head]
			head += 1
			var cur := dist[c.y * GW + c.x]
			for d in 4:
				var n := _step(c, d)
				if n.x < 0:
					continue
				if n == start:
					found = true
					break
				var i := n.y * GW + n.x
				if dist[i] == FAR:
					if _fit(n):
						dist[i] = cur + 1
						queue.append(n)
					else:
						dist[i] += 1
		if not found:
			return null
	var steps: Array[int] = []
	var p := start
	var last := first_dir(x0, y0, x1, y1)
	if p.x < 0 or p.x >= GW or p.y < 0 or p.y >= GH + 2:
		return steps
	while steps.size() < GW * GH:
		var best := dist[p.y * GW + p.x]
		if best == 0:
			break
		var pick := -1
		for k in 4:
			var d := (last + k) & 3
			var n := _step(p, d)
			if n.x < 0 or not _fit(n):
				continue
			if dist[n.y * GW + n.x] < best:
				best = dist[n.y * GW + n.x]
				pick = d
		if pick < 0:
			break
		last = pick
		steps.append(pick)
		p += Vector2i(STEP_DX[pick], STEP_DY[pick])
	return steps


## Walk to (x, y) step by step along `route` (facing each step's direction), then face `end_dir`: op 0x32 →
## 0x429159, which turns a facing above 3 into 0. end_dir -1 keeps the last step's facing. Nothing at all when the
## target cannot be reached.
func walk_to(x: int, y: int, end_dir: int = -1, fast := false) -> void:
	var steps: Variant = route(gx, gy, x, y)
	if steps == null:
		return
	walking = true
	_anim_t = 0.0
	var st := 0.0 if fast else STEP_TIME * _speed()
	for d in steps:
		dir = d
		await _tween_to(foot_point(gx + STEP_DX[d], gy + STEP_DY[d], gz), st)
		gx += STEP_DX[d]
		gy += STEP_DY[d]
		_place()
	walking = false
	if end_dir >= 0:
		dir = end_dir if end_dir <= 3 else 0
	set_action(action if action != 0 else 0)
	frame = 0 if action == 0 else action + 2
	queue_redraw()


func _tween_to(p: Vector2, t: float) -> void:
	if t <= 0:
		position = p
		return
	var tw := create_tween()
	tw.tween_property(self, "position", p, t)
	await tw.finished
