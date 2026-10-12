extends Node
## Headless test harness: TEST=res://src/debug/t_xxx.gd godot --headless --path . res://src/debug/test_runner.tscn
## A test's run() prints "<name>: PASS" or "<name>: FAILED" (with "<name>: FAIL …" lines before). The exit code
## says how it went: 0 passed; 1 failed, could not be loaded, or hit a script error (which would otherwise stop
## it silently half-way); 2 still running after TEST_TIMEOUT seconds (default 300).

## Watches everything the test prints and every script error, whichever thread reports it.
class Watch extends Logger:
	var test := ""
	var passed := false
	var failed := false
	var errors: Array[String] = []

	func _log_message(message: String, _error: bool) -> void:
		if message.begins_with(test + ": PASS"):
			passed = true
		elif message.begins_with(test + ": FAIL"):
			failed = true

	func _log_error(_function: String, file: String, line: int, code: String, _rationale: String,
			_editor_notify: bool, error_type: int, _script_backtrace: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_SCRIPT:
			errors.append("%s:%d: %s" % [file, line, code])


var _watch := Watch.new()
var _done := false


func _ready() -> void:
	var path := OS.get_environment("TEST")
	_watch.test = path.get_file().get_basename()
	OS.add_logger(_watch)
	var s: GDScript = load(path) if path != "" and FileAccess.file_exists(path) else null
	if s == null or not s.can_instantiate():
		_finish(1, "cannot load the test '%s'" % path)
		return
	var limit := float(OS.get_environment("TEST_TIMEOUT")) if OS.get_environment("TEST_TIMEOUT") != "" else 300.0
	get_tree().create_timer(limit, true, false, true).timeout.connect(
			func() -> void: _finish(2, "still running after %d s" % limit))
	var t: Node = s.new()
	add_child(t)
	await t.run()
	if not _watch.errors.is_empty():
		_process(0)
	elif _watch.passed and not _watch.failed:
		_finish(0, "")
	else:
		_finish(1, "no \"%s: PASS\"" % _watch.test if not _watch.failed else "")


func _process(_d: float) -> void:
	if not _watch.errors.is_empty():
		_finish(1, "script error at " + "; ".join(_watch.errors))


func _finish(code: int, why: String) -> void:
	if _done:
		return
	_done = true
	OS.remove_logger(_watch)
	if why != "":
		printerr("test_runner: %s: %s" % [_watch.test, why])
	get_tree().quit(code)
