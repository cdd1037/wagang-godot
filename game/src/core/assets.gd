extends Node
## Runtime asset access. All converted game data lives under res://assets as plain
## files (PNG/JSON/MP3/WAV/OGV) marked importer="keep", and is loaded on demand.

const ROOT := "res://assets/"

var _tex_cache: Dictionary = {}
var _json_cache: Dictionary = {}
var _audio_cache: Dictionary = {}
var _font: Font


func path(rel: String) -> String:
	return ROOT + rel


func exists(rel: String) -> bool:
	return FileAccess.file_exists(ROOT + rel)


## Load a PNG as a texture (cached).
func tex(rel: String) -> Texture2D:
	if _tex_cache.has(rel):
		return _tex_cache[rel]
	var t: Texture2D = null
	var img := image(rel)
	if img:
		t = ImageTexture.create_from_image(img)
	_tex_cache[rel] = t
	return t


## Load a PNG as an Image (not cached).
func image(rel: String) -> Image:
	var p := ROOT + rel
	if not FileAccess.file_exists(p):
		push_warning("missing image: " + rel)
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) != OK:
		return null
	return img


func json(rel: String) -> Variant:
	if _json_cache.has(rel):
		return _json_cache[rel]
	var p := ROOT + rel
	var v: Variant = null
	if FileAccess.file_exists(p):
		v = JSON.parse_string(FileAccess.get_file_as_string(p))
	else:
		push_warning("missing json: " + rel)
	_json_cache[rel] = v
	return v


func audio(rel: String) -> AudioStream:
	if _audio_cache.has(rel):
		return _audio_cache[rel]
	var p := ROOT + rel
	var s: AudioStream = null
	if FileAccess.file_exists(p):
		var bytes := FileAccess.get_file_as_bytes(p)
		if rel.ends_with(".mp3"):
			var m := AudioStreamMP3.new()
			m.data = bytes
			s = m
		elif rel.ends_with(".wav"):
			s = AudioStreamWAV.load_from_buffer(bytes)
		elif rel.ends_with(".ogg"):
			s = AudioStreamOggVorbis.load_from_buffer(bytes)
	_audio_cache[rel] = s
	return s


func video(rel: String) -> VideoStream:
	var p := ROOT + rel
	if not FileAccess.file_exists(p):
		return null
	var v := VideoStreamTheora.new()
	v.file = p
	return v


## CJK-capable UI font (system Song/Hei fonts on macOS).
func font() -> Font:
	if _font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["SimSun", "Songti SC", "STSong", "Heiti SC", "PingFang SC"])
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		f.hinting = TextServer.HINTING_NORMAL
		# Songti SC lacks ~130 of the game's characters (珪, 吽, traditional forms …); these two
		# cover all of them on macOS
		var fb: Array[Font] = []
		for n in ["Hiragino Sans GB", "Heiti SC"]:
			var g := SystemFont.new()
			g.font_names = PackedStringArray([n])
			g.antialiasing = f.antialiasing
			fb.append(g)
		f.fallbacks = fb
		_font = f
	return _font


func clear_cache() -> void:
	_tex_cache.clear()
	_json_cache.clear()
