class_name UnitSprite
extends Node2D
## Battle unit graphic (48x48 move/special frames, 64x64 attack frames).
## Directions use the original engine codes: 0 up, 1 right, 2 down, 3 left.
## Right-facing frames are the left-facing ones mirrored.

enum Pose { STAND, WALK, ATTACK, DEFEND, HURT, CHEER, WEAK, FIXED }
enum Sheet { MOV, ATK, SPC }

const MOV_W := 48
const ATK_W := 64

var entry := 0
var dir := 2
var pose := Pose.STAND
var frame := 0
var anim_time := 0.0
var walk_speed := 4.0      # frames per second for walking
var greyed := false        # already acted this turn
var flash := 0.0           # white flash amount (hit)
var flash_color := Color.WHITE
var fade := 1.0
var clip_h := 48.0          # rows of a still (FIXED) frame drawn from the top (RemoveUnit's sinking image)
var _mov: Texture2D
var _atk: Texture2D
var _spc: Texture2D
var _shader_mat: ShaderMaterial
# Pose.FIXED: one frame of a sheet, as the scripted unit actions draw them (0x45778f)
var _fixed := [Sheet.MOV, 6, false, 0.0]     # sheet, frame, mirrored, y offset

static var _grey_shader: Shader


func _init() -> void:
	if _grey_shader == null:
		_grey_shader = Shader.new()
		_grey_shader.code = """
shader_type canvas_item;
uniform float grey = 0.0;
uniform float flash = 0.0;
uniform vec3 flash_color = vec3(1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float l = dot(c.rgb, vec3(0.3, 0.59, 0.11));
	c.rgb = mix(c.rgb, vec3(l * 0.85), grey);
	c.rgb = mix(c.rgb, flash_color, flash);
	COLOR = c;
}
"""
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = _grey_shader
	material = _shader_mat


func set_entry(e: int) -> void:
	entry = e
	_mov = Assets.tex("gfx/units/mov/%03d.png" % e)
	_atk = Assets.tex("gfx/units/atk/%03d.png" % e)
	_spc = Assets.tex("gfx/units/spc/%03d.png" % e)
	queue_redraw()


func set_pose(p: int, d: int = -1) -> void:
	pose = p
	if d >= 0:
		dir = d
	frame = 0
	anim_time = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	anim_time += delta
	if pose == Pose.WALK or pose == Pose.WEAK or pose == Pose.STAND:
		var f := int(anim_time * walk_speed) % 2
		if f != frame:
			frame = f
			queue_redraw()
	_shader_mat.set_shader_parameter("grey", 1.0 if greyed else 0.0)
	_shader_mat.set_shader_parameter("flash", flash)
	_shader_mat.set_shader_parameter("flash_color", Vector3(flash_color.r, flash_color.g, flash_color.b))
	modulate.a = fade


## Map direction to (frame-base for up/down/left, mirrored)
func _dir_index() -> Array:
	match dir:
		0: return [1, false]   # up
		1: return [2, true]    # right = mirrored left
		3: return [2, false]   # left
		_: return [0, false]   # down


## Show frame `idx` of a sheet (mov 48×48: 0-1 walk down, 2-3 up, 4-5 left, 6-8 stand down/up/left, 9-10 weak; atk
## 64×64: 0-3 down, 4-7 up, 8-11 left; spc: 0-2 defend down/up/left, 3 hurt, 4 cheer), mirrored for facing right.
func show_frame(sheet: int, idx: int, mirror := false, y_off := 0.0) -> void:
	pose = Pose.FIXED
	_fixed = [sheet, idx, mirror, y_off]
	queue_redraw()


func _draw() -> void:
	var di: Array = _dir_index()
	var d: int = di[0]
	var mirror: bool = di[1]
	var tex: Texture2D = _mov
	var fw := MOV_W
	var idx := 0
	var y_off := 0.0
	match pose:
		Pose.FIXED:
			tex = [_mov, _atk, _spc][int(_fixed[0])]
			fw = ATK_W if int(_fixed[0]) == Sheet.ATK else MOV_W
			idx = int(_fixed[1])
			mirror = bool(_fixed[2])
			y_off = float(_fixed[3])
		Pose.STAND:
			# CCZ units idle with the 2-frame walk cycle on the battlefield
			idx = d * 2 + frame
		Pose.WALK:
			idx = d * 2 + frame
		Pose.WEAK:
			idx = 9 + frame
			mirror = false
		Pose.ATTACK:
			tex = _atk
			fw = ATK_W
			idx = d * 4 + clampi(frame, 0, 3)
		Pose.DEFEND:
			tex = _spc
			idx = d
		Pose.HURT:
			tex = _spc
			idx = 3
			mirror = false
		Pose.CHEER:
			tex = _spc
			idx = 4
			mirror = false
	if tex == null:
		draw_rect(Rect2(4, 4, 40, 40), Color(1, 0, 1, 0.6))
		return
	var h := float(fw) if pose != Pose.FIXED else clampf(clip_h, 0.0, float(fw))
	var src := Rect2(0, idx * fw, fw, h)
	var off := (Vector2.ZERO if fw == MOV_W else Vector2(-8, -8)) + Vector2(0, y_off)
	if mirror:
		draw_set_transform(Vector2(off.x + fw, off.y), 0, Vector2(-1, 1))
		draw_texture_rect_region(tex, Rect2(0, 0, fw, h), src)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		draw_texture_rect_region(tex, Rect2(off, Vector2(fw, h)), src)


## Still frame used for the standing pose (no animation): stand_down/up/left.
func set_still(d: int) -> void:
	dir = d
	pose = Pose.STAND
	queue_redraw()


## One picture of the map attack (0x4044e9): f = −1 the standing frame (MOV 6 + facing, case 0), else attack frame
## f of the facing (the 64×64 buffers 0x4ae4c8 + 0x1000·f). Clears the attacker's glow.
func attack_frame(d: int, f: int) -> void:
	dir = d
	flash = 0.0
	if f < 0:
		var di: Array = _dir_index()
		show_frame(Sheet.MOV, 6 + int(di[0]), bool(di[1]))
	else:
		pose = Pose.ATTACK
		frame = f
		queue_redraw()


## Play the 4-frame attack animation. Returns after it finishes.
func play_attack(d: int, frame_time := 0.09) -> void:
	set_pose(Pose.ATTACK, d)
	for f in 4:
		frame = f
		queue_redraw()
		await get_tree().create_timer(frame_time * (2.0 if f == 2 else 1.0)).timeout
	set_pose(Pose.STAND, d)
