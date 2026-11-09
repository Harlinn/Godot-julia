# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

extends Node
# Hot reload driven like the editor / remote debugger: rewrite res://Mover.jl, then JuliaRuntime.reload_scripts
# (what the debugger's "reload_scripts" message does). parity: 7.1-7.6

const MOVER := "res://Mover.jl"

var passed := 0
var failed := 0


func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAILED: " + what)


func write_version(v: String) -> void:
	var src := FileAccess.get_file_as_string("res://versions/Mover_%s.jl.txt" % v)
	var f := FileAccess.open(MOVER, FileAccess.WRITE)
	f.store_string(src)
	f.close()


func reload() -> void:
	JuliaRuntime.reload_scripts(PackedStringArray([MOVER]))


func jl(code: String) -> String:
	return JuliaRuntime.eval_string(code)


func has_property(obj: Object, name: String) -> bool:
	for p in obj.get_property_list():
		if p["name"] == name:
			return true
	return false


func spawn(path: String) -> Node:
	var n := Node.new()
	n.set_script(load(path))
	add_child(n)
	return n


func _ready() -> void:
	write_version("v1")
	var m := spawn(MOVER)
	var fancy := spawn("res://Fancy.jl")
	var w := spawn("res://Watcher.jl")
	check(m.call("version") == 1 and fancy.call("sparkle_twice") == 10, "v1 loaded")
	m.speed = 2.5
	m.call("step")
	m.call("step")
	m.call("arm")
	w.call("watch", m)
	fancy.speed = 7.0
	fancy.sparkle = 9

	# v2: changed methods, a new field, a changed closure.
	write_version("v2")
	reload()
	check(m.call("version") == 2, "new method behavior after reload")
	check(m.speed == 2.5 and m.count == 2, "exported and plain fields preserved")
	check(m.extra == 42, "new field takes its default")
	check(m.call("stats_hits") == 2, "struct declared in the script is transferred")
	check(m.call("mode_name") == "Run", "enum declared in the script is transferred")
	check(m.label == "v1", "field value kept over the new initializer")
	check(m.saved == 200 and m.restored == 201, "_before_reload ran on the old instance, _after_reload on the new one")
	m.call("step")
	m.emit_signal("moved", 3)
	check(m.label == "v2:3", "closure connected by the old version runs the new code on the migrated instance")
	check(w.seen == 303, "closure of another script sees the migrated instance")
	check(w.call("target_count") == 3, "fields of other instances point to the migrated instance")
	check(m.get_signal_connection_list("moved").size() == 2, "signal connections kept")
	check(fancy.call("version") == 2 and fancy.speed == 7.0 and fancy.sparkle == 9 and fancy.call("sparkle_twice") == 18,
			"dependent script reloaded with state")

	# v3: a removed field and an incompatible type change.
	write_version("v3")
	reload()
	check(m.call("version") == 3 and m.speed == 2.5, "v3 reloaded")
	check(not has_property(m, "label"), "removed field is dropped")
	check(m.count == "", "incompatible type change falls back to the default")
	check(m.extra == 42, "unchanged field kept")

	# v4: syntax error. The instance keeps its state but runs no code until the file is fixed.
	write_version("v4")
	reload()
	check(not m.has_method("version") and m.speed == 2.5 and m.extra == 42, "broken reload keeps state, runs no code")
	m.speed = 4.0
	check(m.speed == 4.0, "state of a suspended instance stays editable")
	check(not fancy.has_method("sparkle_twice") and fancy.sparkle == 9, "dependent of a broken script is suspended")
	# Fixed on disk: the failed reload is retried on the next frames (julia/project/reload_attempts).
	write_version("v5")
	await get_tree().process_frame
	await get_tree().process_frame
	check(m.call("version") == 5 and m.speed == 4.0 and m.extra == 42, "retry picks up the fixed file and restores the instance")
	check(fancy.call("sparkle_twice") == 18 and fancy.speed == 7.0, "dependent restored")

	# Old generations are retired: repeated reloads do not grow script modules, classes or engine dispatch tables.
	var gens := jl("Godot.Runtime.live_generation_count()")
	var classes := jl("length(Godot.Runtime.SCRIPT_CLASSES)")
	var meths := jl("length(methods(Godot.godot_class_name))")
	var pins := jl("Godot.Runtime.pin_count()")
	for i in 6:
		write_version("v6" if i % 2 == 0 else "v5")
		reload()
	check(m.call("version") == 5 and m.speed == 4.0, "state survives repeated reloads")
	check(jl("Godot.Runtime.live_generation_count()") == gens, "generation modules retired (%s)" % gens)
	check(jl("length(Godot.Runtime.SCRIPT_CLASSES)") == classes, "class records retired")
	check(jl("length(methods(Godot.godot_class_name))") == meths, "methods of old generations deleted")
	check(jl("Godot.Runtime.pin_count()") == pins, "no pinned values leak")

	print('GDJL_TEST_RESULT {"name":"reload","passed":%d,"failed":%d,"errored":0,"broken":0}' % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
