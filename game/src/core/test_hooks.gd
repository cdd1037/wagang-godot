class_name TestHooks
extends RefCounted
## The points where the test harness and the bots (src/debug/harness.gd) step into the game. This base does nothing:
## every hook returns what the game does without them. Game.hooks is the harness when src/debug is in the build (a
## source checkout), else this, so the game never names a debug class and a build without src/debug plays the same.
##
## A hook whose harness version awaits is a coroutine here too (`_coroutine`, never run; t_parse checks it): with
## round_end a plain function here, the battle loop that awaits Game.hooks.round_end ended after the god mode's field
## clear although the battle went on (Godot 4.7, S_03 flow tests); as a coroutine here it goes on.


## Boot (main.gd): start a bot.
func boot(_main: Node) -> void:
	pass


## The battle file reached its battle: true to go straight to the aftermath (flow-test retries).
func skip_battle(_st: BattleStage) -> bool:
	return false


## The battle loop starts.
func battle_start(_st: BattleStage) -> void:
	pass


## A round is over (before the weather changes): true ends the battle loop.
func round_end(_st: BattleStage) -> bool:
	if false:
		await _coroutine()
	return false


## The player phase: true when the hook played it (input bot, strategy effect test).
func player_phase(_input: BattleInput) -> bool:
	if false:
		await _coroutine()
	return false


## Autoplay is about to let the AI play player unit `u` / has played it.
func before_auto_unit(_st: BattleStage, _u: BUnit) -> void:
	if false:
		await _coroutine()


func after_auto_unit() -> void:
	pass


## BattleAI: may AI unit `u` hit `t` now; does it keep out of cell `c`; a player unit's move under autoplay (true when
## the hook set the AI's decision).
func may_hit(_u: BUnit, _t: BUnit) -> bool:
	return true


func avoids(_u: BUnit, _c: Vector2i) -> bool:
	return false


func player_walk(_ai: BattleAI, _mv: int) -> bool:
	return false


## God mode (Game.god): an enemy it leaves at its normal damage.
func spared(_t: BUnit) -> bool:
	return false


## A person a sortie forces in who is not in the party yet joins it (jump starts lack earlier files' recruits).
func recruit_forced(_pid: int) -> bool:
	return false


## Story autoplay: the actor to click among `keys` (-1: the usual pick); `idle` polls with nothing to click and
## `clicks` autoplay clicks so far: true leaves the file.
func story_pick(_st: StoryStage, _keys: Array) -> int:
	if false:
		await _coroutine()
	return -1


func story_leave(_st: StoryStage, _idle: int, _clicks: int) -> bool:
	return false


## Makes a hook a coroutine, as its harness version is (see above).
func _coroutine() -> void:
	await Engine.get_main_loop().process_frame
