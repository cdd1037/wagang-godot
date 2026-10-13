class_name SystemMenu
extends RefCounted
## The menu bar (0x474c59) as one list, the same in towns and battles. Outside battles 结束回合, 检索未执行部队,
## 胜利条件 and 战场缩小图 are greyed (0x4759bc), so the town's list leaves them out; 装备, 买进 and 卖出 are on the
## town's toolbar. A command is [id, label, battle only]: the label is only what the menu shows, the id is what
## runs, so a new command is a row here and a case in `open` (or in the battle's handler).

const COMMANDS := [
	["end_turn", "结束回合", true],
	["find_unit", "检索未执行部队", true],
	["units", "武将一览", false],
	["items", "持有道具一览", false],
	["terrain", "地形情报一览", false],
	["history", "历史情报", false],
	["victory", "胜利条件", true],
	["minimap", "战场缩小图", true],
	["settings", "环境设定", false],
	["save", "存储进度", false],
	["load", "读取进度", false],
	["version", "版本情报", false],
	["title", "回到标题", false],
]


## The commands of a battle's menu (`battle`) or a town's.
static func commands(battle: bool) -> Array:
	return COMMANDS.filter(func(c: Array) -> bool: return battle or not c[2])


## The labels of that menu, in order.
static func labels(battle: bool) -> Array:
	return commands(battle).map(func(c: Array) -> String: return c[1])


## Shows the menu and runs the chosen command. In a battle (`st`) the battle-only ones go to `battle_command`, a
## coroutine taking the id.
static func open(ui: GameUI, st: BattleStage = null, battle_command := Callable()) -> void:
	var cmds := commands(st != null)
	var i := await ui.menu.choose(cmds.map(func(c: Array) -> String: return c[1]), Vector2(-1, -1), true)
	if i < 0:
		return
	var main: Node = Game.main
	match str(cmds[i][0]):
		"units":
			await UnitListWindow.open(ui, st)
		"items":
			await ItemListWindow.open(ui)
		"terrain":
			await TerrainWindow.open(ui)
		"history":
			await HistoryWindow.open(ui)
		"settings":
			await SettingsWindow.open(ui)
		"save":
			await main.save_menu()
		"load":
			await main.load_menu()
		"version":
			await MsgBox.version(ui)
		"title":
			# 结束游戏 (item 112 → WM_CLOSE → 0x474ba7): "结束「瓦岗山异闻录」么？", and only 是 leaves
			if await MsgBox.yes_no(main.ui, "结束「瓦岗山异闻录」么？", "结束「瓦岗山异闻录」"):
				main.to_title()
		var id:
			await battle_command.call(id)
