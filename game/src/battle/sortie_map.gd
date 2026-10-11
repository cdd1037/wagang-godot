class_name SortieMap
extends DlgPanel
## 出战位置 (dialog 333, drawn by mod 0x4db180 / 0x4db2a7): the map Yun.wa (GS+7 >> 1), normally the coming
## battle's, at 12 px a cell with Qusi.wa entry 14's terrain tiles, and the start positions of the mod table
## 0x55e9d8 (op 0x4b in towns: x, y, set) as numbered discs, Qusi.wa 12 (set 0, blue) or 13 (set 1, red).
## All 15 entries are drawn; ones the chapter did not set keep older values.

const T := 12

static var _tiles := {}          # [entry, tile] → ImageTexture


## Tile t of a Qusi.wa entry of 12×12 tiles stored one after another (144 bytes each, read 48 px a row).
static func tile(entry: int, t: int, key_black := false) -> Texture2D:
	var k := Vector2i(entry, t)
	if _tiles.has(k):
		return _tiles[k]
	var src := Assets.tex("gfx/effects/qusi/%02d.png" % entry)
	if src == null:
		return null
	var img := src.get_image()
	if img.is_compressed():
		img.decompress()
	var out := Image.create(T, T, false, Image.FORMAT_RGBA8)
	var w := img.get_width()
	for y in T:
		for x in T:
			var i := t * T * T + y * T + x
			var c := img.get_pixel(i % w, i / w)
			if key_black and c.r < 0.02 and c.g < 0.02 and c.b < 0.02:
				c = Color(0, 0, 0, 0)
			out.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(out)
	_tiles[k] = tex
	return tex


static func open(ui: Node) -> void:
	var maps: Array = Assets.json("gfx/maps/index.json")["maps"]
	var n := Game.scenario >> 1
	if n >= maps.size():
		return
	var m: Dictionary = maps[n]
	var w := SortieMap.new()
	w.dlu_scale = Vector2.ONE
	w.set_meta("map", m)
	w.dlu = Vector2(int(m["width"]) * T, int(m["height"]) * T)
	await DlgPanel.run(ui, w)


func _draw_dialog() -> void:
	var m: Dictionary = get_meta("map")
	var terr: Array = m["terrain"]
	for y in terr.size():
		var row: Array = terr[y]
		for x in row.size():
			var t := tile(14, int(row[x]))
			if t:
				draw_texture(t, origin + Vector2(x, y) * T)
	for k in 15:
		var a := 0x55e9d8 + 3 * k
		var x := Mem.r8(a)
		if x == 0xff:
			break
		var t := tile(13 if Mem.r8(a + 2) != 0 else 12, k, true)
		if t:
			draw_texture(t, origin + Vector2(x, Mem.r8(a + 1)) * T)


func _on_hit(_key: Variant) -> void:
	close()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		close()
		accept_event()
		return
	super._gui_input(ev)
