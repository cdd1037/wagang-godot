# Content tables

**Status:** built on 2026-10-13 (scope B of "Decisions taken" below). The fields are
documented for modders in [MODDING.md](MODDING.md), "Rules as tables". This page keeps the design and why.

The goal is to let a mod change *who has a skill*, *what a strategy does* and *what an item does* by editing a data
file instead of the game's code. Before the tables, those rules were numbers in the code.

## What the code had before

**Character skills.** The code checked a person id in about 70 places across 8 files. The busiest are `battle_actions.gd`
(22), `person.gd` (18), `battle_commands.gd` (14) and `rules.gd` (12). A skill's holder is one of three kinds:

| Holder | Example | How the original decides it |
|---|---|---|
| A fixed person | 张善相 (204) 枪母子, 秦琼 (8) 绝招 range 6 | a number compared in the mod's code |
| A dynamic slot | 尤俊达 百宝 = slot 9, 尉迟恭 夺面鞭 = slot 4 | `EV[3970 + k]`, which the story scripts set (the code names slots 2, 4, 7, 9, 10, 19 and 20, and loops over the rest) |
| Whoever stands beside the unit | 房玄龄 (179) 房谋, 185, 23 | 0x4d4a60: the holder is on one of the 8 cells around the unit |

Many skills also need a condition, such as an EV progress value (宿痕: `EV[3181..3190] ≥ n`), a weapon or armour
(0x17, 0x18, 0x2e …), a class (张公瑾 as class 41), or a map number (张善相's poison up to map 34).

In the original, only the dynamic slots are data. The fixed holders are constants in the mod's code.

**Strategies.** `strategies.json` has 73 records, converted from the original's data: name, effect, target, range,
area, MP and so on. Power and category are read from the program image. What each strategy *does* is spread over
about ten lists of ids and three `match` blocks:

* `Rules.DAMAGE_STRATS`, `STRAT_HP_DAMAGE`, `STRAT_HIT_9_10 / 4_5 / 3_5 / 1_2 / ALWAYS`;
* `BattleActions.DAMAGE_HANDLER`, `STATUS_HANDLER`, and the heal and weather id tests;
* the AI's id lists and scores (`BattleAI._strat_score`) and its side rule `s <= 38 or s >= 64`.

The original decides most of this in its strategy dispatcher (0x425627). That is a compiled `switch`, not a table a
mod could edit, so the port has to write it down itself.

**Items.** `items.json` (original data) gives each item a type. The consumable types 63–76 are handled in three
functions: `item_usable_on`, `use_item` and `_item_check`. Their status-cure masks (0x48, 0x12, 0x7e, 0x24) are
bare numbers in that code.

## The design

### 1. Strategies: `data/strategy_rules.json`, one record per strategy id

```json
{ "id": 33, "handler": "status", "hp_damage": true, "hit": 0.9, "side": "enemy",
  "ai": "damage", "status": "poison" }
```

* `handler` names the original's handler group: damage, damage_14, drain_hp, drain_mp, status, debuff, buff,
  heal_hp, heal_mp, cure, weather, again, random. It replaces `DAMAGE_HANDLER`, `STATUS_HANDLER` and the id tests in
  the `match` blocks, which then switch on the handler.
* `hit` replaces the `STRAT_HIT_*` lists, `hp_damage` replaces `STRAT_HP_DAMAGE`, `side` replaces the side rule,
  and `ai` replaces the AI's id lists.
* Each field's comment in the file names the original's address it comes from.

**What a mod could do:** change a strategy's kind, hit factor or AI use; or add a strategy (a record in
`strategies.json` plus a rule record) that reuses an existing handler.

### 2. Items: `data/item_rules.json`, one record per consumable type (63–76)

```json
{ "type": 66, "kind": "cure", "mask": 18 }
```

The kinds are heal_hp, heal_mp, cure, all_up (太保令), fruit (with a stat), xianren and promote. The three
functions then read the record instead of matching the type number.

### 3. Character skills: `data/skills.json`, holders, conditions and numbers

```json
{ "id": "qiang_mu_zi", "name": "枪母子", "holder": {"pid": 204}, "range": 12 },
{ "id": "baibao", "name": "百宝", "holder": {"dyn": 9} },
{ "id": "fangmou", "name": "房谋", "holder": {"beside": 179} },
{ "id": "suhen_qinqiong", "name": "宿痕", "holder": {"pid": 8}, "if": {"ev": [3181, 1], "weapon": 24} }
```

The code asks `Skills.has(u, "qiang_mu_zi")` and `Skills.num("qiang_mu_zi", "range")` instead of `u.pid == 204`.
What a skill *does* stays in GDScript.

**What a mod could do:** give a skill to another person, change its condition, or change its numbers. Inventing a
new skill would still need code.

The 绝招 moves (`battle_commands.gd`, one routine per person) stay code; the table only records who has which.

## Keeping it the same game

* Every default is today's constant, which is the original's value, so playing changes nothing.
* A new check, `t_tables`, compares each record with the constant it replaces, so a typo in a table fails CI.
* `t_skills`, `t_rules`, `t_commands` and `t_strat` must pass unchanged, followed by a full autoplay run.

## Decisions taken

1. **Scope: B.** Strategies, items, and the skill holders, conditions and numbers. Generic effect records (C) were
   left out.
2. **JSON under `game/assets/data`:** `strategy_rules.json`, `item_rules.json`, `skills.json`.
3. **Fixed holders are not read from the program image.** The JSON is the place a mod edits.

How it turned out: about 70 person checks, ten strategy lists and the item-type branches now read the tables.
`Skills.holds(id, pid)`, `Skills.num(id, key)` and `Skills.near(id, unit)` answer for skills, `Rules.handler(s)` and
`Game.strategy_rule(s)` for strategies, and `Game.item_rule(id)` for items. Two protagonist-only checks
(管毅's entrance animation and the 现金 line in 武将情报) and the critical-hit shout table stay in the code: they
are not skills.

The 绝招 records are kept in the order the original tests the persons. Its enable check (0x4d5444) tests them in a
slightly different order, which matters only if one person held two 绝招. The scripts never assign that (dynamic
slot 4, 夺面鞭, only ever holds 尉迟恭), so the table's single order plays the same.

`t_tables` compares every record with the constant it replaced and shows that a changed record changes the game.
`t_skills`, `t_rules`, `t_commands`, `t_strat` and the flow runs pass unchanged.
