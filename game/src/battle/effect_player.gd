class_name EffectPlayer
extends Node2D
## Plays a KoeiAnim effect (Xben small effects / MCALL full-screen strategy animations).
## Records are shown one per delay tick, each with its blend (effect_blend.gdshader): mode 0 weighs the background
## by p2 and the picture by p3, mode 1 takes alpha map p2 at strength p3 (0x402cb5).

const BLEND := preload("res://src/battle/effect_blend.gdshader")

var frames: Array = []
var images: Array[Texture2D] = []
var alphas: Array[Texture2D] = []
var delay := 0.05
var sound := -1                 # SE 100 + the low byte of the header's id (Xben 0x40205e, MCALL 0x403147)
var _i := 0
var _t := 0.0
var _cur: Dictionary = {}
signal done

static var _index: Dictionary = {}


static func index() -> Dictionary:
	if _index.is_empty():
		_index = Assets.json("gfx/effects/index.json")
	return _index


## kind "xben" or "mcall", id = animation number. Returns null if missing.
static func create(kind: String, id: int) -> EffectPlayer:
	var idx: Dictionary = index().get(kind, {})
	var anims: Variant = idx.get("anims", {})
	var a: Dictionary = {}
	if anims is Dictionary:
		a = (anims as Dictionary).get(str(id), (anims as Dictionary).get("%02d" % id, {}))
	elif anims is Array:
		for x in anims:
			if int(x.get("id", -1)) == id:
				a = x
				break
	if a.is_empty() or (a.get("records", []) as Array).is_empty():
		return null
	var e := EffectPlayer.new()
	e.delay = maxf(float(a.get("delay_ms", 50)) / 1000.0, 0.02)
	e.frames = a.get("records", [])
	e.sound = 100 + (int(a.get("id", 0)) & 0xff)
	for k in int(a.get("images", 0)):
		e.images.append(Assets.tex("gfx/effects/%s/%02d/img_%02d.png" % [kind, id, k]))
	for k in int(a.get("alphas", 0)):
		e.alphas.append(Assets.tex("gfx/effects/%s/%02d/alpha_%02d.png" % [kind, id, k]))
	var m := ShaderMaterial.new()
	m.shader = BLEND
	e.material = m
	return e


func _ready() -> void:
	# start on the next frame so callers can `await done` right after add_child()
	_show.call_deferred(0)


func _show(i: int) -> void:
	_i = i
	if i >= frames.size():
		done.emit()
		queue_free()
		return
	_cur = frames[i]
	# 0x4031e8 / 0x403262: the sound at the first record unless its sound byte is 2, and at each record whose byte is 3
	var flag := int(_cur.get("sound", 0))
	if (i == 0 and flag != 2) or flag == 3:
		Audio.play_se(SoundMap.se_name(sound))
	queue_redraw()


func _process(d: float) -> void:
	_t += d
	while _t >= delay:
		_t -= delay
		_show(_i + 1)
		if _i >= frames.size():
			return


func _draw() -> void:
	if _cur.is_empty():
		return
	var k := int(_cur.get("image", 0))
	if k < 0 or k >= images.size() or images[k] == null:
		return
	var t := images[k]
	var mode := int(_cur.get("mode", 0))
	var p2 := int(_cur.get("p2", 0))
	var m := material as ShaderMaterial
	if mode != 0 and (p2 >= alphas.size() or alphas[p2] == null):
		return
	m.set_shader_parameter("mode", 0 if mode == 0 else 1)
	m.set_shader_parameter("p2", float(p2))
	m.set_shader_parameter("p3", float(_cur.get("p3", 16)))
	if mode != 0:
		m.set_shader_parameter("alpha_tex", alphas[p2])
	draw_texture(t, -t.get_size() / 2)
