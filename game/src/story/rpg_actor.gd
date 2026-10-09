class_name RpgActor
extends Node2D
## A character in a story (R) scene. Isometric half-cell coordinates (x, y, z).
## Screen mapping (0x4272c5 with camX=60, camY=25, W=200, scene view at y=40):
##   foot point (sx, sy) = (8*(x-y) + 312, 4*(x+y) - 8*z - 152); 48x64 frame drawn at (sx, sy-64).
## Directions: 0 up-left (-X), 1 down-right (+X), 2 down-left (+Y), 3 up-right (-Y).
## Actions (table 0x48b920): 0 = walk cycle frames [0,1,0,2] (idle shows frame 0),
## 1..17 = single pose frame action+2, 18 = nothing.

const FW := 48
const FH := 64
const STEP_TIME := 0.055

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
		var f: int = seq[int(_anim_t / 0.12) % 4]
		if f != frame:
			frame = f
			queue_redraw()


## Walk to (x, y): first along X, then along Y (original moves axis by axis), then face `end_dir`.
func walk_to(x: int, y: int, end_dir: int = -1, fast := false) -> void:
	walking = true
	_anim_t = 0.0
	var st := 0.0 if fast else STEP_TIME
	while gx != x:
		dir = 1 if x > gx else 0
		var tgt := foot_point(gx + signi(x - gx), gy, gz)
		await _tween_to(tgt, st)
		gx += signi(x - gx)
		_place()
	while gy != y:
		dir = 2 if y > gy else 3
		var tgt2 := foot_point(gx, gy + signi(y - gy), gz)
		await _tween_to(tgt2, st)
		gy += signi(y - gy)
		_place()
	walking = false
	if end_dir >= 0:
		dir = end_dir & 3
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
