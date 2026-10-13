class_name BattleDeploy
extends RefCounted
## Deployment and battlefield creation (docs/rules.md §10.1-10.2): the battle's opening ops (0x44-0x4b), the sortie
## list, BattleStage.create_battlefield's unit setup (UnitInit 0x4429f9, SetAI, Promote 0x442890) and free cells.

var st: BattleStage


func _init(s: BattleStage) -> void:
	st = s


## deployment ai_mode 0..6 → AI code (table 0x48e380)
const AI_CODE := [3, 1, 2, 0, 0, 4, 4]


# ------------------------------------------------------------------ deployment ops
func op_battle_init(_ins: Dictionary) -> void:
	for i in 256:
		Mem.set_flag(i, false)
	Mem.w32(Addr.TOWN_DEPLOY_ON, 0)
	for i in 115:
		st.deploy[i] = {"person": 0xffff, "flags": 0}
		Mem.w8(BUnit.GRUDGE + i, 0)
	# players = sortie list. 0x412230 resets only an entry's person and flags (+0, +8): a player without an op 0x4b
	# in this battle keeps the position an earlier battle gave its entry (S_08's seventh unit)
	var lst := sortie_list()
	for k in mini(lst.size(), 15):
		st.deploy[k] = {"person": lst[k], "flags": 0, "x": Mem.r8(DEPLOY + 64 * k + 4), "y": Mem.r8(DEPLOY + 64 * k + 5),
				"hidden": false}


## The sortie list u32[] @0x48b350 (0xffff-terminated), set by the 出场 screen / scripts.
func sortie_list() -> Array[int]:
	var out: Array[int] = []
	for k in 32:
		var v := Mem.r32(Addr.SORTIE + 4 * k) & 0xffff
		if v == 0xffff:
			break
		out.append(v)
	return out


func set_sortie_list(lst: Array) -> void:
	for k in lst.size():
		Mem.w32(Addr.SORTIE + 4 * k, int(lst[k]))
	Mem.w32(Addr.SORTIE + 4 * lst.size(), 0xffff)


func op_battle_settings(ins: Dictionary) -> void:
	st.turn_limit = st.arg(ins, 2)
	var a3 := st.arg(ins, 3)
	if a3 == 0xffff:
		st.level_offset = 0
	elif a3 <= 50:
		st.level_offset = a3
	else:
		st.level_offset = -(a3 - 50)
	var a5 := st.arg(ins, 5)
	st.boss_pid = -1 if a5 == 0xffff else a5
	var a7 := st.arg(ins, 7)
	st.leader_pid = -1 if a7 == 0xffff else a7
	var a8 := st.arg(ins, 8)
	st.climate = 0 if a8 == 0xffff else clampi(a8, 0, 4)
	var a9 := st.arg(ins, 9)
	st.weather_level = 1 if a9 == 0xffff else clampi(a9, 0, 5)


func _entry_from(e: Array, enemy: bool) -> Dictionary:
	var i := 0
	var d := {}
	var v := func(k: int) -> int:
		var x: Variant = e[k]
		if x is Dictionary:
			return Mem.ev(int(x.get("var", 0)))
		return int(x)
	d["person"] = v.call(0)
	i = 1
	d["kind3"] = false
	if enemy:
		d["kind3"] = v.call(1) not in [0, 0xffff]
		i = 2
	d["hidden"] = v.call(i) not in [0, 0xffff]
	d["x"] = v.call(i + 1)
	d["y"] = v.call(i + 2)
	d["dir"] = v.call(i + 3)
	if enemy and int(d["dir"]) > 3:
		d["dir"] = 2              # 0x449b27 → 0x449ae8: 0xffff or any facing above 3 is 2
	var lv: int = v.call(i + 4)
	d["lv"] = 0 if lv == 0xffff else lv
	var promo: int = v.call(i + 5)
	d["promo"] = 2 if promo == 0xffff else promo
	var aim: int = v.call(i + 6)
	d["ai"] = 1 if aim == 0xffff else aim
	d["ai_person"] = v.call(i + 7)
	d["ai_x"] = v.call(i + 8)
	d["ai_y"] = v.call(i + 9)
	d["flags"] = (1 if enemy else 2) | (2 if d["kind3"] else 0) | (4 if d["hidden"] else 0)
	return d


func op_battle_allies(ins: Dictionary) -> void:
	var a: Array = ins["args"]
	for k in mini(a.size(), 20):
		var d := _entry_from(a[k], false)
		if d["person"] == 0xffff:
			continue
		st.deploy[15 + k] = d


func op_battle_enemies(ins: Dictionary) -> void:
	var a: Array = ins["args"]
	for k in mini(a.size(), 80):
		var d := _entry_from(a[k], true)
		if d["person"] == 0xffff:
			continue
		st.deploy[35 + k] = d

const DEPLOY := 0x494fd4       # deployment table R+0x2044, 115 entries × 64 bytes (0x418dd0); x, y at +4, +5


## op 0x48 (0x412dd6): equipment codes for the ally/enemy deployment entry of a person (slots 15+),
## used when the battle starts (0x44cc85, see Person.equip_code). 0xffff → 0.
func op_battle_equipment(ins: Dictionary) -> void:
	var pid := st.arg(ins, 0)
	if pid > 0x3ff:
		return
	for i in range(15, 115):
		var d: Dictionary = st.deploy[i]
		if int(d.get("person", 0xffff)) == pid:
			var keys := ["weapon", "wlv", "armor", "alv", "acc"]
			for k in 5:
				var v := st.arg(ins, 1 + k)
				d[keys[k]] = 0 if v == 0xffff else v & 0xff
			st.deploy[i] = d
			return


## op 0x4a (0x415d92 → 0x41856a): build the sortie list. Forced persons (5 here + any from op 0x06)
## that are party members go first; if all 9 flag bytes are non-zero the protagonist is included;
## when the stored max exceeds the forced count the player picks the rest.
func op_battle_prepare(ins: Dictionary) -> void:
	for k in 5:
		Mem.w32(ScriptHost.SORTIE_FORCED + 4 * k, st.arg(ins, 1 + k))
	for k in 4:
		Mem.w32(ScriptHost.SORTIE_FORCED + 4 * (5 + k), st.arg(ins, 6 + k))
	Mem.w32(ScriptHost.SORTIE_FLAGS + 4 * 9, st.arg(ins, 10))
	await st.build_sortie()


func trimmed_mean_level() -> int:
	var lv: Array[int] = []
	for pid in sortie_list():
		lv.append(Game.person(pid).level)
	if lv.is_empty():
		return 1
	lv.sort()
	lv.reverse()
	var n := lv.size()
	var cut := n / 4
	var s := 0
	var c := 0
	for i in range(cut, n - cut):
		s += lv[i]
		c += 1
	return s / maxi(c, 1)


func create_battlefield(id: int) -> void:
	st.map_id = id
	st.ui.clear_strips()            # the battle's status pane shows the cursor cell instead (mod 0x4d1c10)
	st.ui.meter.visible = false     # 0x476715 draws resource 2 only outside battles
	Mem.w32(Skills.MAP_NO, id & 0xff)   # 0x44c2e3: the battle map's number (battle mode for the person getters)
	Mem.set_ev(10, 0)            # mod 0x44ccc8: no unit has fallen yet
	st.view.load_map(id)
	for u in st.units:
		u.reset(u.slot)
		if u.node:
			u.node.queue_free()
			u.node = null
	Mem.fill(BattleStage.ASSASSIN_MARK, 115, 0)
	var base := maxi(1, trimmed_mean_level() + st.level_offset)
	var next_p := 0
	var next_f := 15
	var next_e := 35
	for i in 115:
		var d: Dictionary = st.deploy[i]
		var pid := int(d.get("person", 0xffff))
		if pid == 0xffff:
			continue
		var flags := int(d.get("flags", 0))
		var slot := -1
		if flags & 3 == 0:
			slot = next_p
			next_p += 1
		elif flags & 1:
			slot = next_e
			next_e += 1
		else:
			slot = next_f
			next_f += 1
		if slot < 0 or slot >= 115 or (flags & 3 == 0 and slot >= 15) or (flags & 1 == 0 and flags & 2 and slot >= 35):
			continue
		var u := st.units[slot]
		var p := Game.person(pid)
		if p == null:
			continue
		var generated := flags & 3 != 0 and not (flags & 1 == 0 and Game.is_member(pid))
		if generated:
			# reload base data, then level/promotion/equipment from the deployment entry
			Game.reset_person(pid)
			var lv := int(d.get("lv", 0))
			var level := mini(base + lv, 70) if lv <= 50 else maxi(base - (lv - 50), 1)
			_promote(p, int(d.get("promo", 2)), level)
			# 0x44cc85 → 0x4429f9 per slot; ops 0x46/0x47 start entries with code 0 (default equipment for the
			# class and level, 0x407fe7) and level 1, op 0x48 sets other codes
			p.equip_code(0, int(d.get("weapon", 0)), int(d.get("wlv", 1)))
			p.equip_code(1, int(d.get("armor", 0)), int(d.get("alv", 1)))
			p.equip_code(2, int(d.get("acc", 0)), 0xff)
		_unit_init(u, pid, flags, int(d.get("x", 0)), int(d.get("y", 0)), int(d.get("dir", 2)), bool(d.get("hidden", false)))
		if flags & 3 != 0:
			# SetAI refuses party members: one deployed as an ally keeps AI code 0 from the reset and the target
			# point its slot had, and acts in the ally phase (not player-controlled: its colour is 1)
			_set_ai(u, clampi(int(d.get("ai", 1)), 0, 6), int(d.get("ai_person", 0xffff)), int(d.get("ai_x", 0)), int(d.get("ai_y", 0)))
	# after 0x44cc85 (0x44d427): flag 0x80 and status bits 0x1e cleared; player-side units of the player's colour
	# are player-controlled (code 7)
	for u in st.units:
		u.flags = u.flags & ~0x80
		u.status = u.status & ~0x1e
		if u.slot < 35 and u.state != 0 and u.colour == 0:
			u.mode = 7
	st.field_ready = true
	if OS.get_environment("WG_TRACE_BATTLE") != "":
		print("battlefield map=%d sortie=%s" % [id, sortie_list()])
		for u in st.units:
			if u.exists():
				print("  slot %d pid %d %s state %d pos %s hp %d/%d mode %d lv %d cls %d" % [u.slot, u.pid, u.person.name, u.state, u.pos, u.hp, u.max_hp(), u.mode, u.level(), u.cls()])
	st.refresh_units()
	st.hud.visible = true
	Mem.w8(0x4b3d08, st.map_id)


## Promote (0x442890): promo 0 none; 1 → +1 tier at level ≥ 20; 2 → +1 at ≥ 20, +2 at ≥ 40 (classes ≤ 38).
func _promote(p: Person, promo: int, level: int) -> void:
	if p.cls <= 38:
		var t := p.cls % 3
		var base_c := p.cls - t
		if promo == 1 and level >= 20:
			p.cls = mini(p.cls + 1, base_c + 2)
		elif promo == 2:
			if level >= 40:
				p.cls = mini(p.cls + 2, base_c + 2)
			elif level >= 20:
				p.cls = mini(p.cls + 1, base_c + 2)
	if level > p.level:
		p.level_up(level - p.level)


## SetAI (0x459d8b): ai_mode 0..6 → AI code (table 0x48e380) and clears flag 0x80; modes 3 and 5 also
## set the target person (unit[8] = its slot), 4 and 6 the target point (unit[8] = 0xff, [9], [10] = x, y).
## Other modes change nothing; a target person without a unit (0x45a751) or a point off the map (0x45a6bf)
## leaves the old target. Refused for party members (0x41a190: person byte +0x2a == 0), wherever they stand.
func _set_ai(u: BUnit, ai_mode: int, ai_person: int, ax: int, ay: int) -> void:
	if ai_mode < 0 or ai_mode > 6 or Game.is_member(u.pid):
		return
	u.flags = u.flags & ~0x80
	u.mode = AI_CODE[ai_mode]
	match ai_mode:
		3, 5:
			var s := BUnit.slot_of(ai_person) if ai_person != 0xffff else -1
			if s >= 0:
				Mem.w8(u.addr + 8, s)
				u.extra["ai_person"] = ai_person
		4, 6:
			if ax < st.view.map_w and ay < st.view.map_h:
				Mem.w8(u.addr + 8, 0xff)
				Mem.w8(u.addr + 9, ax)
				Mem.w8(u.addr + 10, ay)


## A retreated unit re-entering (ops 0x55 / 0x6d → 0x4591a1): UnitInit with the flags of its deployment entry,
## so the colour stays; the AI code and target and the flags are kept.
func _unit_reenter(u: BUnit, x: int, y: int, d: int) -> void:
	var colour := u.colour
	# UnitInit tells this call site (0x459417) by its return address: no 出阵数 for the re-entry
	_unit_init(u, u.pid, 0 if u.slot < 15 else (2 if u.slot < 35 else 1), x, y, d, false, false)
	u.colour = colour


## UnitInit (0x44274c): person, colour (0x449b7b), facing, position and state, full HP/MP, neutral buffs, no
## status. It leaves the AI code and target ([8]..[0xa]), the order byte and the flags as they are. A party
## member's 出阵数 (+0x27) counts up, except on op 0x55's re-entry (`sortie` false).
func _unit_init(u: BUnit, pid: int, flags: int, x: int, y: int, d: int, hidden: bool, sortie := true) -> void:
	u.state = BUnit.STATE_HIDDEN
	u.pid = pid
	var kind := 0
	if flags & 1:
		kind = 3 if flags & 2 else 2
	elif flags & 2:
		kind = 1
	u.colour = kind
	u.dir = d & 3
	if hidden:
		u.pos = Vector2i(x, y)
	else:
		u.state = BUnit.STATE_ON_MAP
		u.pos = nearest_free(Vector2i(x, y), u)
	u.hp = u.max_hp()
	u.mp = u.max_mp()
	for i in 6:
		u.set_buff(i, 3)
	u.status = 0
	var p := u.person
	if Game.is_member(pid):
		if sortie:
			Mem.w8(p.base + 0x27, mini(Mem.r8(p.base + 0x27) + 1, 255))
	else:
		for off in [0x27, 0x28, 0x29]:
			Mem.w8(p.base + off, 0)


## The free cell nearest c for u (0x43f040): c itself, then its neighbours N, E, S, W; the same around c + N, then
## c + N + E, then c + E; else the first cell (row by row) with the smallest |dx| + |dy| on the whole map. Free: on
## the map, no other unit, terrain u can enter (move table ≠ 0xff).
func nearest_free(c: Vector2i, u: BUnit) -> Vector2i:
	var ok := func(p: Vector2i) -> bool:
		return st.view.in_bounds(p) and st.unit_at(p, u) == null and Rules.move_cost(u, st.view.terrain_at(p)) < 255
	var dirs := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	var cur := c
	for k in 4:
		if ok.call(cur):
			return cur
		for d in dirs:
			if ok.call(cur + d):
				return cur + d
		cur += dirs[k]
	var best := c
	var bd := 1 << 30
	for y in st.view.map_h:
		for x in st.view.map_w:
			var p := Vector2i(x, y)
			var dist := absi(x - c.x) + absi(y - c.y)
			if dist < bd and ok.call(p):
				best = p
				bd = dist
	return best
