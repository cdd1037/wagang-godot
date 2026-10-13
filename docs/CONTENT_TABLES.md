# Content tables (proposal)

**Status:** proposal of 2026-10-13. Nothing here is built yet. It needs three decisions, listed at the end.

The goal is to let a mod change *who has a skill*, *what a strategy does* and *what an item does* by editing a data
file instead of the game's code. Today those rules are written into the code as numbers.

## What the code has today

**Character skills.** The code checks a person id in about 70 places across 8 files. The busiest are `battle_actions.gd`
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

## Proposal

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

## Decisions needed

1. **Scope.**
   * **A:** strategies and items only. This is the smallest and most mechanical step.
   * **B (recommended):** A plus the skill holders, conditions and numbers.
   * **C:** B plus generic effect records (hit bonus, damage multiplier, on-hit status …) that the engine
     interprets, so a mod could add a skill without code. Not recommended now: many skills don't fit such records,
     and building them risks changing behaviour.
2. **Where the tables live.**
   * **JSON under `game/assets/data` (recommended):** mods already override these files, and `make_mod.py`
     packs them from its extra folder.
   * **GDScript constants:** no loading step, but a mod could not change them.
3. **Read the fixed holders from the program image?** The original compares fixed holders as constants in its
   code. Reading them from `exe_image.bin`, as strategy power is read, would carry a mod made by patching the
   original program over automatically. That needs every compare site found in Ghidra: about 60, some checked in
   several places. **Recommended: not now.** The JSON is then the place a mod edits.
