extends Node
## Smoke test: run scenarios from WG_FROM to WG_TO in autoplay mode, report unimplemented ops.
func run() -> void:
	var main = get_tree().root.get_node_or_null("Main")
	print("main: ", main)
