extends Node
## The content tables (data/strategy_rules.json, item_rules.json, skills.json; docs/CONTENT_TABLES.md) hold exactly
## the original's values that the code had as constants before them: a changed or mistyped record fails here.
## (A mod may change them on purpose; the checks run without mods.) Prints "t_tables: PASS".

var _ok := true


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("t_tables: FAIL ", what)
		_ok = false


func run() -> void:
	_strategies()
	_items()
	_skills()
	_modded()
	print("t_tables: PASS" if _ok else "t_tables: FAILED")


## A mod that changes a record changes the game: 智将 moved to 王君珂 (2), 医疗 made a damage strategy.
func _modded() -> void:
	Game.new_game_state()
	var a := BUnit.at(0)
	a.clear(0)
	a.pid = 2
	a.state = BUnit.STATE_ON_MAP
	a.hp = a.max_hp()
	var d := BUnit.at(35)
	d.clear(35)
	d.pid = 300
	d.state = BUnit.STATE_ON_MAP
	d.hp = d.max_hp()
	_check(Rules.damage_post(a, d, 10) == 10, "王君珂 has no 智将")
	var recs: Array = Game.skills_db.duplicate(true)
	for r in recs:
		if r["id"] == "zhijiang":
			r["holder"] = {"pid": 2}
	Skills.index(recs)
	_check(Rules.damage_post(a, d, 10) == mini(a.spirit() * 15 / 100 + 10, d.hp), "a changed holder moves 智将")
	Skills.index(Game.skills_db)
	var keep: Dictionary = Game.strategy_rules_db[39].duplicate()
	Game.strategy_rules_db[39]["hp_damage"] = true
	_check(Rules.strat_hp_damage(39), "a changed strategy record changes the strategy")
	Game.strategy_rules_db[39] = keep
	a.clear(0)
	d.clear(35)


func _strategies() -> void:
	_check(Game.strategy_rules_db.size() == Game.strategies_db.size(), "one rule per strategy")
	var hp_damage := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 33, 34, 35, 36, 38, 64, 65]
	var hit := {}
	for s in [1, 2, 6, 7, 11, 13, 14, 16, 22, 23, 25, 33]: hit[s] = [9, 10]
	for s in [3, 8, 18, 24, 26, 27, 29, 31, 34, 35, 37]: hit[s] = [4, 5]
	for s in [4, 20, 28, 30, 36]: hit[s] = [3, 5]
	hit[32] = [1, 2]
	for s in [21, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 67]: hit[s] = "always"
	hit[9] = "leader_third"
	# the dispatcher 0x425627
	var handlers := {}
	for s in range(0, 14) + range(15, 23) + [65]: handlers[s] = "damage"
	handlers[14] = "storm"
	for s in range(23, 31) + range(48, 57): handlers[s] = "stat"
	for s in range(31, 38) + [46, 47]: handlers[s] = "status"
	for s in range(39, 46): handlers[s] = "heal"
	handlers[38] = "bazhen"
	handlers[57] = "again"
	for s in [58, 59, 60]: handlers[s] = "weather"
	handlers[61] = "fortify"
	handlers[63] = "fortify"
	handlers[62] = "meditate"
	handlers[64] = "qinglong"
	handlers[66] = "xuanwu"
	handlers[67] = "baihu"
	var stat := {23: [0x17], 24: [0x17], 25: [0x19], 26: [0x19], 27: [0x1b], 28: [0x1b], 29: [0x1d], 30: [0x1d], 48: [0x30],
		49: [0x31], 50: [0x31], 51: [0x33], 52: [0x33], 53: [0x35], 54: [0x35], 55: [0x37], 56: [0x37], 61: [0x35],
		63: [0x31, 0x33, 0x35, 0x37]}
	var status := {31: "confusion", 32: "confusion", 33: "poison", 34: "poison", 35: "paralysis", 36: "paralysis", 37: "seal"}
	var ai := {}
	for s in [0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 15, 16, 17, 18, 19, 20, 33, 34, 35, 36]: ai[s] = "damage"
	for s in [21, 31, 32]: ai[s] = "hit35"
	ai[22] = "drain_mp"
	ai[37] = "seal"
	for s in [39, 40, 43]: ai[s] = "heal"
	for s in [41, 42]: ai[s] = "supply"
	for s in [44, 45, 62]: ai[s] = "mp"
	for s in [46, 47]: ai[s] = "cure"
	ai[57] = "again"
	for s in Game.strategies_db.size():
		var r := Game.strategy_rule(s)
		var w := "strategy %d %s" % [s, r.get("name", "?")]
		_check(int(r.get("id", -1)) == s, w + ": id")
		_check(Rules.handler(s) == str(handlers.get(s, "none")), w + ": handler")
		_check((r.get("element") == null) == (s >= 20) and (s >= 20 or int(r["element"]) == s / 5), w + ": element")
		var f: Variant = r.get("hit")
		var want: Variant = hit.get(s)
		_check((f == null and want == null) or (f is Array and want is Array and Array(f.map(func(x: float) -> int: return int(x))) == want)
				or (f is String and f == want), w + ": hit factor %s" % [f])
		_check(Rules.strat_hp_damage(s) == (s in hp_damage), w + ": HP damage")
		_check(Rules.strat_mp_damage(s) == (s == 22), w + ": MP damage")
		_check(bool(r.get("absorb_hp", false)) == (s == 20) and bool(r.get("assassinate", false)) == (s == 21), w + ": 暗算 / 暗杀")
		_check(str(r.get("status", "")) == str(status.get(s, "")), w + ": status")
		_check(int(r.get("cure", 0)) == (0x7e if s in [46, 47] else 0), w + ": cure")
		_check(Array(r.get("stat_codes", []).map(func(x: float) -> int: return int(x))) == stat.get(s, []), w + ": stat codes")
		_check(Rules.strat_hp_heal(s) == (s >= 39 and s <= 43) and Rules.strat_mp_heal(s) == (s in [44, 45]), w + ": heal kind")
		_check(str(r.get("heal", "")) == ("hp" if s in [39, 40, 41, 42, 43, 67] else "mp" if s in [44, 45] else ""), w + ": heal")
		_check(str(r.get("heal_size", "")) == ("small" if s in [39, 41] else "large" if s in [40, 42, 43, 67] else ""), w + ": heal size")
		_check(int(r.get("weather", -1)) == {58: 2, 59: 0, 60: 1}.get(s, -1), w + ": weather")
		_check(str(r.get("ai", "")) == str(ai.get(s, "")), w + ": AI kind")
		_check(int(r.get("ai_bonus", 0)) == {40: 5, 43: 10}.get(s, 0), w + ": AI bonus")
		_check(Rules.strat_has(s, "ai_opposing") == (s <= 38 or s >= 64), w + ": AI side")


func _items() -> void:
	var want := {63: ["heal_hp"], 64: ["heal_mp"], 65: ["cure", 0x48], 66: ["cure", 0x12], 67: ["cure", 0x7e],
		68: ["cure", 0x24], 69: ["all_up"], 75: ["level_up"], 76: ["promote"]}
	for ty in range(70, 75):
		want[ty] = ["fruit", [0, 2, 1, 3, 4][ty - 70], [0x22, 0x22, 0x23, 0x24, 0x25][ty - 70]]
	_check(Game.item_rules.size() == want.size(), "one rule per consumable type")
	for ty in want:
		var r: Dictionary = Game.item_rules.get(ty, {})
		var w: Array = want[ty]
		_check(r.get("kind") == w[0], "item type %d: kind %s" % [ty, r.get("kind")])
		if w[0] == "cure":
			_check(int(r.get("mask", -1)) == w[1], "item type %d: mask" % ty)
		if w[0] == "fruit":
			_check(int(r.get("stat", -1)) == w[1] and int(r.get("fx", -1)) == w[2], "item type %d: stat and effect" % ty)


func _skills() -> void:
	var ids := {}
	for r in Game.skills_db:
		_check(not ids.has(r["id"]), "skill id %s only once" % r["id"])
		ids[r["id"]] = true
	# who holds what (dynamic slots and memory holders by their slot / address)
	var holders := {"qiangmuzi": {"pid": 204}, "feijiangjun": {"pid": 25}, "special_range_6": {"pid": 8},
		"special_range_adjacent": {"pids": [5, 26, 14, 19]}, "changying": {"pid": 178}, "yuwen_halved": {"pid": 33},
		"zhuying": {"pid": 35}, "hengtui": {"pid": 44}, "gaima": {"pid": 34}, "fengwu": {"pid": 33}, "longyin": {"pid": 32},
		"guimen": {"pid": 43}, "numu": {"pid": 4}, "sha": {"pid": 3}, "shuanglei": {"pids": [101, 136]},
		"choutiqiang": {"pid": 14}, "special_no_crit": {"pids": [7, 26]}, "jinming": {"pid": 17}, "sheming": {"dyn": 10},
		"zhijiang": {"pid": 19}, "strategy_immune": {"pid": 0x89}, "duduan": {"beside": 185}, "fangmou": {"beside": 179},
		"xu_maogong": {"pid": 22}, "liemo": {"dyns": [15, 16, 17, 18]}, "ruosha": {"dyns": [19, 20]}, "xuanyuan": {"pid": 0},
		"sanbanfu": {"pid": 1}, "mengyan": {"pid": 67}, "zhang_poison": {"pid": 204}, "guanshi": {"pid": 24},
		"windup": {"pids": [0, 204]}, "boruo": {"pid": 15}, "duanzao": {"pid": 16}, "kill_mp": {"pid": 3},
		"dingtianqing": {"pid": 6}, "shanxiongxin_mount": {"pid": 4}, "xiangma": {"dyn": 7}, "baibao": {"dyn": 9},
		"fanhu": {"pid": 11}, "bingdi": {"dyn": 2}, "tianyun": {"pid": 10}, "yunxiu": {"pid": 29}, "mp_aura": {"pid": 31},
		"tianmo": {"mem": Addr.TIANMO}, "mogong": {"mem": Addr.MOGONG}, "attack_aura": {"pid": 42}, "mingjing": {"beside": 23},
		"weizhen_bahuang": {"pid": 7}, "canglong": {"pid": 0}, "duomianbian": {"dyn": 4}, "tapo": {"pid": 5},
		"hengsao": {"pid": 26}, "shashoujian": {"pid": 8}, "huixuan": {"dyn": 11}, "huimaqiang": {"pid": 19},
		"shikuai": {"pid": 20}}
	for id in holders:
		_check(Skills.rule(id).get("holder", {}) == holders[id], "skill %s: holder %s" % [id, Skills.rule(id).get("holder")])
	var nums := {"qiangmuzi": {"range": 12}, "feijiangjun": {"range": 4}, "special_range_6": {"range": 6},
		"special_range_adjacent": {"range": 0}, "changying": {"area": 6}, "zhuying": {"range": 13},
		"sheming": {"hp_below": 60, "percent": 130}, "zhijiang": {"percent": 15}, "duduan": {"hit": 20},
		"xu_maogong": {"percent": 50}, "xuanyuan": {"weapon": 23, "ev": 3184, "chance_ev": 2700},
		"sanbanfu": {"hit": 50, "weapon": 25}, "zhang_poison": {"map_max": 34},
		"guanshi": {"ev": 3223, "min": 3, "mp_ev": 3257, "base_ev": 3451}, "boruo": {"flag": Addr.BORUO},
		"duanzao": {"flag": Addr.DUANZAO}, "kill_mp": {"ev": 3183, "min": 4, "per_kill": 5},
		"dingtianqing": {"terrain_effect": 11}, "shanxiongxin_mount": {"ev_byte": 3190, "min": 3, "accessory": 0x2f},
		"bingdi": {"partner": 0, "percent": 8}, "lianli": {"percent": 5, "within": 5}}
	for id in nums:
		for k in nums[id]:
			_check(Skills.num(id, k, -999) == nums[id][k], "skill %s: %s = %d" % [id, k, Skills.num(id, k, -999)])
	_check(Skills.rule("feijiangjun").get("if", {}) == {"class": 41}, "飞将军 as class 41")
	_check(Skills.rule("xu_maogong").get("strategies") == [20, 37], "徐茂功's strategies")
	_check(Skills.rule("dingtianqing").get("terrains") == [9, 10, 13], "丁天庆's terrains")
	_check(Skills.rule("xiangma").get("mounts") == [0x3d, 0x3e, 0x3f, 0x2f, 0x3b, 0x3c], "相马's mounts")
	_check(Skills.rule("lianli").get("auras") == [{"stat": 0, "dyn": 0, "partner": 0}, {"stat": 1, "dyn": 1, "partner": 0},
			{"stat": 3, "dyn": 1, "partner": 12}, {"stat": 4, "dyn": 0, "partner": 29}], "连理's auras")
	var suhen := [[8, 0, 3181, "weapon", 0x18, 3401, 3201], [0, 0, 3184, "weapon", 0x17, 3416, 3204],
		[1, 1, 3185, "weapon", 0x19, 3422, 3205], [0, 1, 3184, "weapon", 0x17, 3417, 3204],
		[21, 2, 3186, "weapon", 0x23, -1, 3206], [0, 2, 3184, "weapon", 0x17, 3418, 3204],
		[19, 3, 3189, "weapon", 0x1a, -1, 3209], [0, 3, 3184, "weapon", 0x17, 3419, 3204],
		[13, 4, 3182, "armor", 0x2e, -1, 3202], [0, 4, 3184, "weapon", 0x17, 3420, 3204]]
	var got: Array = Skills.rule("suhen").get("entries", [])
	_check(got.size() == suhen.size(), "宿痕 entries")
	for i in mini(got.size(), suhen.size()):
		var e: Dictionary = got[i]
		var w: Array = suhen[i]
		_check(e["pid"] == w[0] and e["stat"] == w[1] and e["flag_ev"] == w[2] and e.get(w[3]) == w[4]
				and e["base_ev"] == w[5] and e["factor_ev"] == w[6], "宿痕 entry %d" % i)
	# the 绝招 routines, in the order the original tests the persons (0x4d3007)
	var order := []
	for r in Game.skills_db:
		if r.has("special"):
			order.append(r["special"])
	_check(order == ["wei_zhen_ba_huang", "cang_long", "duo_mian_bian", "san_ban_fu", "ta_po_lian_ying", "heng_sao",
			"sha_shou_jian", "jin_ming", "hui_ma_qiang"], "绝招 order %s" % [order])
	for id in BattleActions.TECHNIQUES:
		_check(Skills.rule(id).get("technique") == id, "technique %s has its record" % id)
