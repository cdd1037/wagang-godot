extends Node
## Saves (Game.save_game / read_save / load_game, Mem.snapshot / check_snapshot) in a folder of its own
## (user://test/saves/, never the player's slots): a save loads back; a damaged one, or one whose memory ranges do
## not fit this build, is refused before anything changes. Prints "t_save: PASS".

var _ok := true


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("t_save: FAIL ", what)
		_ok = false


func run() -> void:
	var keep_dir := Game.save_dir
	Game.save_dir = "user://test/saves/"
	DirAccess.make_dir_recursive_absolute(Game.save_dir)
	Game.new_game_state()
	Game.join_party(0, 1)
	Game.gold = 1234
	Mem.w_str(Addr.TITLE_TEXT, "第二章")
	_check(Game.save_game(3, {"kind": "story", "scene": 2}), "a save is written")
	var d: Variant = Game.read_save(3)
	_check(d is Dictionary, "it reads back")
	Game.gold = 5
	var extra: Variant = Game.load_game(3)
	_check(extra is Dictionary and int(extra.get("scene", -1)) == 2, "load gives the stage state back (%s)" % [extra])
	_check(Game.gold == 1234 and Mem.str_at(Addr.TITLE_TEXT) == "第二章", "memory comes back (gold %d)" % Game.gold)
	# damaged saves: refused by read_save, and load_game changes nothing
	var good := FileAccess.get_file_as_string(Game.save_path(3))
	var bad := {
		"one range short": func(x: Dictionary) -> void: (x["mem"]["ranges"] as Array).pop_back(),
		"a range of the wrong size": func(x: Dictionary) -> void: x["mem"]["ranges"][0] = Marshalls.raw_to_base64(PackedByteArray([1, 2, 3])),
		"no person heap": func(x: Dictionary) -> void: (x["mem"] as Dictionary).erase("heap"),
		"a bad page": func(x: Dictionary) -> void: x["mem"]["pages"] = {"7": "AAAA"},
		"no scenario": func(x: Dictionary) -> void: x.erase("scenario"),
	}
	Game.gold = 77
	for what in bad:
		var x: Dictionary = JSON.parse_string(good)
		(bad[what] as Callable).call(x)
		var f := FileAccess.open(Game.save_path(3), FileAccess.WRITE)
		f.store_string(JSON.stringify(x))
		f.close()
		_check(Game.read_save(3) == null, "refused: " + what)
		_check(Game.load_game(3) == null and Game.gold == 77 and Game.is_member(0), "nothing changed: " + what)
	var f := FileAccess.open(Game.save_path(3), FileAccess.WRITE)
	f.store_string(good.substr(0, good.length() / 2))
	f.close()
	_check(Game.read_save(3) == null, "refused: a truncated file")
	Game.delete_save(3)
	Game.save_dir = keep_dir
	print("t_save: PASS" if _ok else "t_save: FAILED")
