class_name ResourceMeter
extends Control
## The third pane of the town status window (0x476715): resource 2 (GS+0x12, 0..100, set by op 0x3a kind 2) as a
## 200×8 bar, the first value × 2 px in the Kao.wa pattern 0x40 (value < 16) or 0x00, the rest in 0xc0 (value < 85)
## or 0x40. Not in battles. Op 0x3a's add / subtract (0x40d2a9 / 0x40d3ae) step it in five steps of 3 ticks with a
## blinking up / down arrow, then 1 tick. The original pane sits at (342, 25) in the status window; here it goes
## left of the top bar's 菜单 at (290, 25), and above the buttons (y 2) while the town toolbar shows.

var value := -1                 # shown value (−1: follow GS+0x12)
var arrow := 0                  # 1 up, −1 down, 0 none


func _ready() -> void:
	position = Vector2(290, 25)
	size = Vector2(212, 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var v := value if value >= 0 else Mem.r8(Mem.GS + 0x12)
	var w := maxi(v * 2, 1)
	var fill := Assets.tex("gfx/effects/kao/%05x_8x8.png" % (0x40 if v < 16 else 0x00))
	var rest := Assets.tex("gfx/effects/kao/%05x_8x8.png" % (0xc0 if v < 85 else 0x40))
	if fill:
		draw_texture_rect(fill, Rect2(0, 0, w, 8), true)
	if rest and w < 200:
		draw_texture_rect(rest, Rect2(w, 0, 200 - w, 8), true)
	if arrow != 0:
		var f := Assets.font()
		draw_string(f, Vector2(203, 8), "▲" if arrow > 0 else "▼", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UIStyle.NAME_COLOR)


## The add / subtract animation from `old` to `new`.
func animate(old: int, new: int) -> void:
	if Game.autoplay:
		return
	var step := (new - old) / 5
	for k in 5:
		value = old + k * step
		arrow = (1 if new >= old else -1) if (k + 1) & 1 else 0
		await get_tree().create_timer(0.15).timeout
	value = -1
	arrow = 0
	await get_tree().create_timer(0.05).timeout
