extends Node
## Mods (Assets._load_mods, docs/MODDING.md): a .zip in the mod folder is mounted over res://, its JSON is read
## instead of the game's, and a picture it replaces is shown as the mod has it rather than from the HD pack. Uses
## user://test/mods/, never the player's user://mods/. Prints "t_mods: PASS".

var _ok := true


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("t_mods: FAIL ", what)
		_ok = false


func run() -> void:
	var dir := "user://test/mods/"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir + f))
	var pic := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	pic.fill(Color.RED)
	var zp := ZIPPacker.new()
	_check(zp.open(dir + "probe.zip") == OK, "the test zip can be written")
	zp.start_file("assets/data/mod_probe.json")
	zp.write_file('{"probe": 7}'.to_utf8_buffer())
	zp.close_file()
	zp.start_file("assets/gfx/screens/00.png")
	zp.write_file(pic.save_png_to_buffer())
	zp.close_file()
	zp.close()
	FileAccess.open(dir + "notes.txt", FileAccess.WRITE).store_string("not a mod")
	var before := Assets.tex("gfx/screens/00.png").get_size()
	Assets.mod_dir = dir
	Assets._load_mods()
	Assets.clear_cache()
	_check(Assets.mods == (["probe.zip"] as Array[String]), "the zip loads, other files do not: %s" % [Assets.mods])
	var j: Variant = Assets.json("data/mod_probe.json")
	_check(j is Dictionary and int(j["probe"]) == 7, "the mod's JSON is read: %s" % [j])
	var t := Assets.tex("gfx/screens/00.png")
	_check(t != null and t.get_size() == Vector2(2, 2), "the mod's picture replaces the game's (and its HD one): %s, was %s"
			% [t.get_size() if t else null, before])
	_check(Assets.json("data/items.json") is Array, "files the mod leaves alone still load")
	print("t_mods: PASS" if _ok else "t_mods: FAILED")
