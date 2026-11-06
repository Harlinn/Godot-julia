extends Node
# parity: 1.1, 4.10, 9.4

var passed := 0
var failed := 0


func check(condition: bool, name: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		printerr("FAILED: ", name)


func _ready() -> void:
	check(JuliaRuntime.is_available(), "runtime available")
	check(JuliaRuntime.get_julia_version().begins_with("1."), "version reported")
	check(JuliaRuntime.eval_string("1 + 2") == "3", "eval 1 + 2")
	check(JuliaRuntime.eval_string("Threads.threadid()") == "1", "Godot main thread is Julia thread 1")

	JuliaRuntime.eval_string("println(\"hello from julia\")")
	JuliaRuntime.eval_string("print(\"partial \"); print(\"line\\n\")")
	JuliaRuntime.eval_string("println(stderr, \"stderr from julia\")")
	JuliaRuntime.eval_string("@info \"info from julia\"")
	JuliaRuntime.eval_string("@warn \"warning from julia\"")

	check(JuliaRuntime.eval_string("error(\"expected test failure\")") == "", "exception returns empty result")
	check(JuliaRuntime.eval_string("1 +") == "", "parse error returns empty result")
	check(JuliaRuntime.eval_string("2 * 21") == "42", "runtime usable after exceptions")

	var first: Array = _run_on_thread()
	check(first[0] != "" and first[0] != "1", "worker thread adopted (threadid=%s)" % first[0])
	check(first[1] == "true", "GC on worker while main thread runs Godot code")
	check(first[2] == first[0], "worker keeps its Julia thread id")

	var second: Array = _run_on_thread()
	check(second[1] == "true", "second worker thread after the first one exited")

	check(JuliaRuntime.eval_string("GC.gc(); :ok") == ":ok", "GC on main thread after adopted threads")

	print('GDJL_TEST_RESULT {"name":"runtime","passed":%d,"failed":%d,"errored":0,"broken":0}' % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


func _run_on_thread() -> Array:
	var thread := Thread.new()
	thread.start(_worker)
	return thread.wait_to_finish()


func _worker() -> Array:
	var tid := JuliaRuntime.eval_string("Threads.threadid()")
	var gc := JuliaRuntime.eval_string("GC.gc(); true")
	var tid_again := JuliaRuntime.eval_string("Threads.threadid()")
	return [tid, gc, tid_again]
