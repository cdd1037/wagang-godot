extends Node
## Global game state: static data tables, runtime persons, the bag, saves, the chronicle.

const MAX_PERSONS := 1024
const INVENTORY_MAX := 100

# static tables
var items_db: Array = []
var classes_db: Array = []
var families_db: Array = []
var strategies_db: Array = []
var strategy_rules_db: Array = []      # what each strategy does (data/strategy_rules.json, docs/MODDING.md)
var item_rules: Dictionary = {}        # item type → what a consumable of that type does (data/item_rules.json)
var skills_db: Array = []              # the character skills: holders and numbers (data/skills.json, Skills)
var shops_db: Array = []
var names_db: Dictionary = {}
var texts_db: Dictionary = {}
var terrain_names: Array = []
var unit_index: Dictionary = {}
var person_overrides: Dictionary = {}
var portraits: Dictionary = {}

# runtime state
var persons: Array[Person] = []       # the party is person byte +0x2a (is_member), the bag is in GS (BAG)
var autoplay := OS.get_environment("WG_AUTO") != ""
var demo := OS.get_environment("WG_DEMO") != ""
var god := OS.get_environment("WG_GOD") != ""   # debug: player side invulnerable & strong
## A test or bot run (autoplay, a jump start, the flow-test harness, the bots, the unit checks): it leaves the
## player's autosave and endings record (niuniu.bin) alone.
var test_run := autoplay or demo or ["WG_START", "WG_AUTOSAVE", "WG_INPUTBOT", "WG_UIBOT", "TEST"].any(
		func(e: String) -> bool: return OS.get_environment(e) != "")
var history: Array = []
var ending_reached := false
var _name_index: Dictionary = {}

## GS+7: scenario counter. even = R_(n/2) story file, odd = S_(n/2) battle file.
var scenario: int:
	get: return Mem.r8(Mem.GS + 7)
	set(v): Mem.w8(Mem.GS + 7, v)

## GS+0xc: gold (u32, max 9,999,999).
var gold: int:
	get: return Mem.r32(Mem.GS + 0xc)
	set(v): Mem.w32(Mem.GS + 0xc, clampi(v, 0, 9999999))
var chapter_title := ""
var play_time := 0.0
var loaded := false
var clicks := 0                  # count of click / confirm presses; waits compare it to see a new press
var main = null                  # the Main node (src/main.gd); inside the touch shell it is not /root/Main
var shell = null                 # TouchShell when the game runs in it (mobile), else null
var touch := false               # touch controls: tap on release, drag pans the map / scrolls lists
var fast_toggle := false         # the touch shell's 快进 button: acts like holding Ctrl


## The test harness and bots (core/test_hooks.gd): src/debug/harness.gd when the build has src/debug, else hooks that
## do nothing.
const HARNESS := "res://src/debug/harness.gd"
var hooks: TestHooks = TestHooks.new()


func _ready() -> void:
	load_data()
	if ResourceLoader.exists(HARNESS):
		hooks = load(HARNESS).new()


func _input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		if shell and not shell.over_game(ev.position):
			return       # a touch-shell button beside the picture, not a click in the game
		if ev.pressed and ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			clicks += 1
	elif ev.is_action_pressed("ui_accept") or ev.is_action_pressed("ui_cancel"):
		clicks += 1


## Ctrl held (or the touch shell's 快进 on): type text fast and skip waits.
func skip_held() -> bool:
	return fast_toggle or Input.is_key_pressed(KEY_CTRL)


func load_data() -> void:
	items_db = _table("data/items.json", [])
	classes_db = _table("data/classes.json", [])
	families_db = _table("data/class_families.json", [])
	strategies_db = _table("data/strategies.json", [])
	strategy_rules_db = _table("data/strategy_rules.json", [])
	item_rules.clear()
	for r in _table("data/item_rules.json", []):
		item_rules[int(r["type"])] = r
	skills_db = _table("data/skills.json", [])
	Skills.index(skills_db)
	shops_db = _table("data/shops.json", [])
	names_db = _table("data/names.json", {})
	texts_db = _table("data/texts.json", {})
	var t: Variant = Assets.json("data/terrain.json")
	terrain_names = t["names"] if t else []
	var ui: Variant = Assets.json("gfx/units/index.json")
	unit_index = ui if ui else {}
	if unit_index.has("entry_index"):
		for k in unit_index["entry_index"].get("person_override", {}):
			person_overrides[int(k)] = int(unit_index["entry_index"]["person_override"][k])
	var pi: Variant = Assets.json("gfx/portraits/index.json")
	portraits = pi if pi else {}
	new_game_state()
	loaded = true


## A data table: a missing or damaged file (a broken mod, docs/MODDING.md) is named in the log and left empty.
func _table(rel: String, empty: Variant) -> Variant:
	var v: Variant = Assets.json(rel)
	if typeof(v) != typeof(empty):
		push_error("data file %s is missing or not valid JSON" % rel)
		return empty
	return v


## Reload a person's base record from data.wa (0x41b606) — used for generated battle units.
func reset_person(pid: int) -> void:
	var recs: Array = _table("data/persons.json", [])
	if pid < 0 or pid >= recs.size():
		return
	var keep_face := person(pid).face
	var keep_member := Mem.r8(person(pid).base + 0x2a)
	Person.init_record(recs[pid])
	person(pid).face = keep_face
	Mem.w8(person(pid).base + 0x2a, keep_member)


func new_game_state() -> void:
	Mem.reset()
	persons.clear()
	var recs: Array = _table("data/persons.json", [])
	for r in recs:
		persons.append(Person.init_record(r))
	history.clear()
	init_bag()
	# sortie parameters default: max 1, no forced persons, protagonist flags (u32 0x4b0a04[0..9]) set
	Mem.w8(0x4b09ec, 1)
	for k in 5:
		Mem.w32(0x4b09f0 + 4 * k, 0xffff)
	for k in 10:
		Mem.w32(0x4b0a04 + 4 * k, 0xffff)
	play_time = 0.0
	chapter_title = ""          # a new game's first saves are not labelled with the last game's chapter
	_name_index.clear()
	for p in persons:
		if p.name != "" and not _name_index.has(p.name):
			_name_index[p.name] = p.id


func _process(delta: float) -> void:
	play_time += delta / maxf(Engine.time_scale, 0.01)    # real time, also while fast-forwarding


# ------------------------------------------------------------------ lookups
func person(id: int) -> Person:
	if id < 0 or id >= persons.size():
		return null
	return persons[id]


func item(id: int) -> Dictionary:
	if id < 0 or id >= items_db.size():
		return {}
	return items_db[id]


func cls(id: int) -> Dictionary:
	if id < 0 or id >= classes_db.size():
		return {}
	return classes_db[id]


## What a consumable of item `id`'s type does: its record in data/item_rules.json ({} for none).
func item_rule(id: int) -> Dictionary:
	return item_rules.get(int(item(id).get("type", -1)), {})


## What strategy `id` does: its record in data/strategy_rules.json ({} for none).
func strategy_rule(id: int) -> Dictionary:
	if id < 0 or id >= strategy_rules_db.size():
		return {}
	return strategy_rules_db[id]


func strategy(id: int) -> Dictionary:
	if id < 0 or id >= strategies_db.size():
		return {}
	return strategies_db[id]


## Class family (0x4077d0): class <= 38 -> class/3, 39..52 -> class-26, else 27.
func family_of(c: int) -> int:
	if c <= 38:
		return c / 3
	if c <= 52:
		return c - 26
	return 27


func family(f: int) -> Dictionary:
	if f < 0 or f >= families_db.size():
		return {}
	return families_db[f]


func person_override(pid: int) -> int:
	return person_overrides.get(pid, 0)


func text(index: int) -> String:
	var arr: Array = texts_db.get("texts", [])
	if index < 0 or index >= arr.size():
		return ""
	var v: Variant = arr[index]
	return "" if v == null else str(v)


## Terrain name from the executable's GBK name table (pointers at 0x48bdb0), which scripts may overwrite
## (S_12 renames 大河 to 海洋); the converted names are the fallback.
func terrain_name(t: int) -> String:
	if t < 0 or t >= terrain_names.size():
		return ""
	var s := Mem.str_at(Mem.r32(Addr.TERRAIN_NAMES + 4 * t), 16)
	return s if s != "" else str(terrain_names[t])


## Resolved portrait number for a person (GetFace 0x4075a7): the protagonist (pid 0) uses his own
## face field (faces 0..6 are his expressions); everyone else face+7; persons 1/4/8/35 switch to
## fixed portraits depending on story bits in GS+0x11.
func resolved_face(pid: int) -> int:
	var p := person(pid)
	if p == null:
		return -1
	var f := p.face
	var b := Mem.r8(Mem.GS + 0x11)
	match pid:
		0:
			return f & 0xffff
		1:
			if (b & 0x0f) == 4:
				return 0xe0
			if (b & 0x80) == 0:
				return 0xdf
		35:
			if b & 0x10:
				return 0xd6
		8:
			if b & 0x20:
				return 0xe2
		4:
			if b & 0x40:
				return 0xe3
	return f + 7


func face_texture(face: int, small := false) -> Texture2D:
	if face < 0:
		return null
	var rel := "gfx/portraits/%s/%03d.png" % ["small" if small else "large", face]
	if not Assets.exists(rel):
		return null
	return Assets.tex(rel)


func person_face(pid: int, small := false) -> Texture2D:
	return face_texture(resolved_face(pid), small)


# ------------------------------------------------------------------ party
## Party membership = person byte +0x2a (0 = member, 0xff = not) (0x41a190).
func is_member(pid: int) -> bool:
	if pid < 0 or pid >= 1024:
		return false
	return Mem.r8(Mem.person_addr(pid) + 0x2a) == 0


func party_ids() -> Array[int]:
	var out: Array[int] = []
	for p in persons:
		if Mem.r8(p.base + 0x2a) == 0:
			out.append(p.id)
	return out


## Average level of party members among persons 0..25 (0x40c14f).
## 0x40c14f: average level of the 15 highest-levelled party members among persons 0..25 (at least 1).
func party_avg_level() -> int:
	var lv: Array[int] = []
	for i in 26:
		if is_member(i):
			lv.append(person(i).level)
	if lv.is_empty():
		return 1
	lv.sort()
	lv.reverse()
	lv = lv.slice(0, 15)
	var tot := 0
	for v in lv:
		tot += v
	return maxi(tot / lv.size(), 1)


## EEX op 0x3b (0x40c28c): mode 0 = join, levelled to min(avg+arg, 70) with class tier by level
## (>=40 top tier, >=20 middle tier); mode 1 = join as is; mode 0xff/0xffff = leave (equipment to bag).
func join_party(pid: int, mode := 1, arg := 0xff) -> void:
	if pid < 0 or pid >= 1024:
		return
	if OS.get_environment("WG_TRACE_BATTLE") != "":
		print("  join pid %d mode %d arg %d (member before: %s)" % [pid, mode, arg, is_member(pid)])
	var p := person(pid)
	if mode == 0xff or mode == 0xffff:
		if is_member(pid):
			for e in [[p.weapon, p.weapon_lvl], [p.armor, p.armor_lvl], [p.accessory, 0]]:
				if e[0] >= 0:
					add_item(e[0], maxi(e[1], 1))
			p.weapon = -1
			p.armor = -1
			p.accessory = -1
			Mem.w8(p.base + 0x2a, 0xff)
		return
	if is_member(pid):
		return
	if mode == 0 and arg <= 99:
		var target := mini(party_avg_level() + arg, 70)
		if p.level < target:
			p.level_up(target - p.level)
		if p.cls <= 38:
			var tier := 2 if p.level >= 40 else (1 if p.level >= 20 else 0)
			p.cls = (p.cls / 3) * 3 + tier
	Mem.w8(p.base + 0x2a, 0)


## Item bag in GS: 200 slots × 3 bytes (id, level, exp) at 0x4b0783 (0xff = empty);
## stackable consumables 0x57..0x67 are counts at 0x4b09db[id-0x57] (cf. op 0x6f handler 0x411046).
const BAG := 0x4b0783
const BAG_SLOTS := 200
const STACKS := 0x4b09db
const STACK_FIRST := 0x57
const STACK_LAST := 0x67


func is_stack_item(id: int) -> bool:
	return id >= STACK_FIRST and id <= STACK_LAST


func stack_count(id: int) -> int:
	return Mem.r8(STACKS + id - STACK_FIRST) if is_stack_item(id) else 0


## A bag slot is empty when its id byte is 0xff (0x40d6e0, 0x40d79c).
func bag_entries() -> Array:
	var out := []
	for i in BAG_SLOTS:
		var a := BAG + 3 * i
		var id := Mem.r8(a)
		if id != 0xff:
			out.append({"slot": i, "id": id, "lvl": Mem.r8(a + 1), "exp": Mem.r8(a + 2)})
	for id in range(STACK_FIRST, STACK_LAST + 1):
		var c := stack_count(id)
		if c > 0:
			out.append({"slot": -1, "id": id, "lvl": 0, "exp": 0, "count": c})
	return out


func bag_free_slot() -> int:
	for i in BAG_SLOTS:
		var a := BAG + 3 * i
		if Mem.r8(a) == 0xff:
			return i
	return -1


func init_bag() -> void:
	for i in BAG_SLOTS:
		Mem.w8(BAG + 3 * i, 0xff)
		Mem.w8(BAG + 3 * i + 1, 0)
		Mem.w8(BAG + 3 * i + 2, 0)


## Add one item (0x40da45 / 0x40d79c): a consumable stack grows while it is below 255 (else the item is lost); other
## items take the first empty bag slot with their level and experience, an accessory with 0xff, 0xff. False when
## nothing was added.
func add_item(id: int, lvl := 1, xp := 0) -> bool:
	if is_stack_item(id):
		if stack_count(id) >= 255:
			return false
		Mem.w8(STACKS + id - STACK_FIRST, stack_count(id) + 1)
		return true
	var i := bag_free_slot()
	if i < 0:
		return false
	var equip := Person.slot_of(item(id)) < 2
	Mem.w8(BAG + 3 * i, id)
	Mem.w8(BAG + 3 * i + 1, lvl if equip else 0xff)
	Mem.w8(BAG + 3 * i + 2, xp if equip else 0xff)
	return true


func remove_bag_slot(i: int) -> void:
	Mem.w8(BAG + 3 * i, 0xff)
	Mem.w8(BAG + 3 * i + 1, 0xff)
	Mem.w8(BAG + 3 * i + 2, 0xff)


## Remove one item (0x411046): stacks, then the bag, then party members' equipment.
func remove_item_id(id: int) -> bool:
	if is_stack_item(id):
		var c := stack_count(id)
		if c > 0:
			Mem.w8(STACKS + id - STACK_FIRST, c - 1)
			return true
		return false
	for i in BAG_SLOTS:
		if Mem.r8(BAG + 3 * i) == id:
			remove_bag_slot(i)
			return true
	for p in persons:
		if p.weapon == id:
			p.weapon = -1
			return true
		if p.armor == id:
			p.armor = -1
			return true
		if p.accessory == id:
			p.accessory = -1
			return true
	return false


# ------------------------------------------------------------------ save / load
const SAVE_VERSION := 1
const AUTO_SLOT := -1          # the autosave (继续游戏), a file of its own beside the numbered slots
## Debug: WG_SAVEDIR=name keeps every save in user://name/ instead of user://, so tests that go through the save
## menu leave the player's slots alone. The UI bot (WG_UIBOT) uses user://uibot/ unless WG_SAVEDIR says otherwise.
var save_dir := _save_dir()
## Where a test run keeps its other files (SpecialFuncs' copy of niuniu.bin): its save folder when that is its
## own (WG_SAVEDIR, the UI bot's), else user://test/.
var test_dir := save_dir if save_dir != "user://" else "user://test/"


static func _save_dir() -> String:
	var d := OS.get_environment("WG_SAVEDIR")
	if d == "" and OS.get_environment("WG_UIBOT") != "":
		d = "uibot"
	if d == "":
		return "user://"
	DirAccess.make_dir_recursive_absolute("user://" + d)
	return "user://%s/" % d


func save_path(slot: int) -> String:
	if slot == AUTO_SLOT:
		return save_dir + "autosave.json"
	return save_dir + "save_%02d.json" % slot


## Small summary next to each save so the slot list does not have to parse whole saves.
func _info_path(slot: int) -> String:
	if slot == AUTO_SLOT:
		return save_dir + "autosave.info.json"
	return save_dir + "save_%02d.info.json" % slot


## Write `text` to `path` through a temporary file, so a crash mid-write cannot destroy the old file. The old file
## is replaced only when the whole text landed (a full disk can leave a short file without reporting an error).
static func _write_atomic(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var bytes := text.to_utf8_buffer()
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	var ok := f.store_buffer(bytes)
	f.close()
	var back := FileAccess.open(tmp, FileAccess.READ)
	if not ok or back == null or back.get_length() != bytes.size():
		back = null
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		return false
	back.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path)) == OK


func save_game(slot: int, extra: Dictionary = {}) -> bool:
	return write_capture(slot, capture_save(extra))


## The current state as save text, taken now (so later changes do not leak in) and written by write_capture.
## The save of the game as it is now, for write_capture: memory is copied, not yet encoded, and the rest copied
## too, so that a capture taken at a checkpoint and written later still holds that checkpoint.
func capture_save(extra: Dictionary = {}) -> Dictionary:
	var info := {
		"version": SAVE_VERSION,
		"time": Time.get_datetime_string_from_system(),
		"scenario": scenario,
		"chapter_title": chapter_title,
	}
	var d := info.duplicate()
	d.merge({
		"play_time": play_time,
		"party": party_ids(),       # (only so that builds before 2026-10-13 can read the save: they need these keys)
		"inventory": [],
		"ivars": {},
		"history": history.duplicate(true),
		"mem": Mem.raw_snapshot(),
		"extra": extra.duplicate(true),
	})
	return {"data": d, "info": info}


func write_capture(slot: int, cap: Dictionary) -> bool:
	var d: Dictionary = (cap["data"] as Dictionary).duplicate()
	d["mem"] = Mem.encode_snapshot(d["mem"])
	if not _write_atomic(save_path(slot), JSON.stringify(d)):
		return false
	_write_atomic(_info_path(slot), JSON.stringify(cap["info"]))
	return true


func delete_save(slot: int) -> void:
	for p in [save_path(slot), _info_path(slot)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func save_info(slot: int) -> Dictionary:
	var p := save_path(slot)
	if not FileAccess.file_exists(p):
		return {}
	var d: Variant = null
	if FileAccess.file_exists(_info_path(slot)) \
			and FileAccess.get_modified_time(_info_path(slot)) >= FileAccess.get_modified_time(p):
		d = JSON.parse_string(FileAccess.get_file_as_string(_info_path(slot)))
	if not d is Dictionary:
		d = read_save(slot)
		if d == null:
			return {}
	return {"time": d.get("time", ""), "scenario": d.get("scenario", 0), "chapter_title": d.get("chapter_title", "")}


## The parsed save in `slot`, or null if it is missing, damaged or from a newer version of the game.
func read_save(slot: int) -> Variant:
	var p := save_path(slot)
	if not FileAccess.file_exists(p):
		return null
	var j := JSON.new()                 # (JSON.parse_string would log a damaged file as an engine error)
	if j.parse(FileAccess.get_file_as_string(p)) != OK:
		return null
	var d: Variant = j.data
	if not d is Dictionary or int(d.get("version", 0)) > SAVE_VERSION:
		return null
	if not d.has("mem") or not d.has("scenario") or not d.get("history", []) is Array \
			or not d.get("extra", {}) is Dictionary \
			or not (d["scenario"] is float or d["scenario"] is int) or not Mem.check_snapshot(d["mem"]):
		return null
	return d


## Load the save in `slot`; returns its stage state ("extra"), or null (and changes nothing) if the save
## cannot be read.
func load_game(slot: int) -> Variant:
	var d: Variant = read_save(slot)
	if d == null:
		return null
	chapter_title = str(d.get("chapter_title", ""))
	play_time = float(d.get("play_time", 0))
	history.clear()
	for h in d.get("history", []):
		if h is Dictionary:
			history.append(h)
		else:
			add_history(1, str(h))      # saves before the categories: "<number><text>"
	Mem.restore(d["mem"])
	Mem.w32(Addr.SAVE_ALLOWED, 1)          # LoadGame (0x41adc1 → mod 0x4d0c29): saving is allowed again after a load
	scenario = int(d["scenario"])
	return d.get("extra", {})


# ------------------------------------------------------------------ chronicle (史录)
## An entry of the mod's chronicle (op 0x16 with EV[4095] = category): the text starts with the entry
## number. A category other than 0xff is appended as it is, even when that number is already there
## (0x413adc). Category 0xff edits the first entry with that number (mod 0x4d1679): a text that is only the
## number deletes it, any other replaces its text (the category stays); with no such entry nothing happens.
func add_history(cat: int, text: String) -> void:
	var n := 0
	while n < text.length() and text[n] >= "0" and text[n] <= "9":
		n += 1
	var id := int(text.substr(0, n)) if n > 0 else -1
	var e := {"id": id, "cat": cat, "text": text.substr(n)}
	if cat != 0xff:
		history.append(e)
		return
	for i in history.size():
		if id >= 0 and int(history[i]["id"]) == id:
			if n == text.length():
				history.remove_at(i)
			else:
				e["cat"] = history[i]["cat"]
				history[i] = e
			return


# ------------------------------------------------------------------ names / text
func person_id_by_name(n: String) -> int:
	return int(_name_index.get(n, -1))


## Text substitution hook (engine 0x4179a5). Plain pass-through for now.
# ------------------------------------------------------------------ resources (EEX 0x3a / 0x37)
## kind 0 = gold (GS+0xc), kind 2 = 0..100 value at GS+0x12, kind 1 = byte GS+6 (0x418c70).
func get_resource(kind: int) -> int:
	match kind:
		0: return gold
		1: return Mem.r8(Mem.GS + 6)
		2: return Mem.r8(Mem.GS + 0x12)
	return 0


## op: 0 set, 1 add, 2 subtract.
func change_resource(kind: int, op: int, v: int) -> void:
	match kind:
		0:
			match op:
				0: gold = v
				1: gold = gold + v
				2: gold = 0 if v > gold else gold - v
		1:
			Mem.w8(Mem.GS + 6, v)
		2:
			var cur := Mem.r8(Mem.GS + 0x12)
			match op:
				0: cur = v if v <= 100 else cur
				1: cur = mini(cur + v, 100)
				2: cur = maxi(cur - v, 0)
			Mem.w8(Mem.GS + 0x12, cur)


## Comparison mode (tag 0x24, ops 0x3f/0x41/0x36/0x37): 0 → a >= b, 1 → a < b, other → a == b.
func compare(a: int, b: int, cmp: int) -> bool:
	match cmp:
		0: return a >= b
		1: return a < b
	return a == b
