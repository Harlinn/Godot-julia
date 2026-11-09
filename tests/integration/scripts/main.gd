# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

extends Node
# Drives the Julia script tests from GDScript (the engine side of the C# parity checks).
# parity: 4.3, 4.9, 5.1–5.3, 5.5–5.18

var passed := 0
var failed := 0
var hits := []


func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		printerr("FAILED: " + what)


func _on_hit(damage: int) -> void:
	hits.append(damage)


func script_of(obj: Object) -> Script:
	return obj.get_script()


func props_by_name(obj: Object) -> Dictionary:
	var props := {}
	for p in obj.get_property_list():
		props[p["name"]] = p
	return props


# Phase 09: export annotations, defaults, RPC config, static methods, global classes, dynamic properties.
func check_authoring(player: Node) -> void:
	var ex := $Exports
	var ex_script: Script = ex.get_script()
	var props := props_by_name(ex)
	check(props["Movement"]["usage"] == PROPERTY_USAGE_CATEGORY, "export_category")
	check(props["speed"]["usage"] & PROPERTY_USAGE_DEFAULT == PROPERTY_USAGE_DEFAULT, "export usage")
	check(props["health"]["hint"] == PROPERTY_HINT_RANGE and props["health"]["hint_string"] == "0,100,1,or_greater", "export_range")
	check(props["Visuals"]["usage"] == PROPERTY_USAGE_GROUP and props["Visuals"]["hint_string"] == "visual_", "export_group")
	check(props["Text"]["usage"] == PROPERTY_USAGE_SUBGROUP, "export_subgroup")
	check(props["visual_bg"]["hint"] == PROPERTY_HINT_COLOR_NO_ALPHA, "export_color_no_alpha")
	check(props["notes"]["hint"] == PROPERTY_HINT_MULTILINE_TEXT and props["title"]["hint"] == PROPERTY_HINT_PLACEHOLDER_TEXT, "text hints")
	check(props["size"]["hint"] == PROPERTY_HINT_ENUM and props["size"]["hint_string"] == "Small,Large:5", "export_enum")
	check(props["mode"]["type"] == TYPE_INT and props["mode"]["hint_string"] == "Walk:0,Run:1,Fly:2", "Julia @enum export")
	check(props["elements"]["hint"] == PROPERTY_HINT_FLAGS and props["elements"]["hint_string"] == "Fire,Water,Earth", "export_flags")
	check(props["layers"]["hint"] == PROPERTY_HINT_LAYERS_2D_PHYSICS, "export_flags_2d_physics")
	check(props["image"]["hint"] == PROPERTY_HINT_FILE and props["image"]["hint_string"] == "*.png,*.jpg", "export_file")
	check(props["folder"]["hint"] == PROPERTY_HINT_DIR and props["easing"]["hint"] == PROPERTY_HINT_EXP_EASING, "export_dir / exp_easing")
	check(props["sprite_path"]["hint"] == PROPERTY_HINT_NODE_PATH_VALID_TYPES and props["sprite_path"]["hint_string"] == "Sprite2D", "export_node_path")
	check(props["target"]["type"] == TYPE_OBJECT and props["target"]["hint"] == PROPERTY_HINT_NODE_TYPE and props["target"]["hint_string"] == "Node2D", "Node export")
	check(props["item"]["hint"] == PROPERTY_HINT_RESOURCE_TYPE and props["item"]["hint_string"] == "Item", "custom Resource export")
	check(props["items"]["hint"] == PROPERTY_HINT_ARRAY_TYPE and props["lookup"]["hint"] == PROPERTY_HINT_DICTIONARY_TYPE, "typed collections")
	check(props["hidden_state"]["usage"] & PROPERTY_USAGE_EDITOR == 0 and props["hidden_state"]["usage"] & PROPERTY_USAGE_STORAGE != 0, "export_storage")
	check(props["password"]["hint"] == PROPERTY_HINT_PASSWORD, "export_custom")
	check(props["reset_button"]["type"] == TYPE_CALLABLE and props["reset_button"]["hint"] == PROPERTY_HINT_TOOL_BUTTON and props["reset_button"]["hint_string"] == "Reset,Reload", "export_tool_button")
	check(ex.health == 150 and ex.target == player and ex.item.title == "Sword" and ex.item.power == 7, "values from .tscn and .tres")
	ex.speed = 1.0
	ex.reset_button.call()
	check(ex.speed == 300.0, "tool button calls the script function")
	ex.mode = 2
	check(ex.mode == 2, "enum property round trip")
	check(ex_script.get_property_default_value("speed") == 300.0 and ex_script.get_property_default_value("health") == 100, "default values for revert")
	var rpc: Dictionary = ex_script.get_rpc_config()
	check(rpc.get("shoot") == {"rpc_mode": MultiplayerAPI.RPC_MODE_ANY_PEER, "call_local": true, "transfer_mode": MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, "channel": 1}, "rpc config")
	check(rpc.get("ping", {}).get("rpc_mode") == MultiplayerAPI.RPC_MODE_AUTHORITY and rpc["ping"]["transfer_mode"] == MultiplayerPeer.TRANSFER_MODE_RELIABLE, "rpc defaults")
	check(ex_script.has_method("double_it") and ex_script.call_static("double_it", 21) == 42, "static method")
	var classes := {}
	for c in ProjectSettings.get_global_class_list():
		classes[String(c["class"])] = c
	check(classes.has("Item") and classes["Item"]["language"] == "Julia" and String(classes["Item"]["base"]) == "Resource", "global class")
	check(classes.has("AbstractWeapon") and classes["AbstractWeapon"].get("is_abstract", false), "abstract global class")
	check(String(classes["AbstractWeapon"]["icon"]).ends_with("JuliaScript.svg"), "@icon")
	check(ex_script.is_tool() and not script_of(player).is_tool(), "@tool")
	var failures: Array = ex.julia_checks()
	for f in failures:
		check(false, "julia: " + f)
	check(failures.is_empty(), "Exports Julia-side checks")

	var dyn := $Dyn
	check(dyn.virtual_value == 42, "_get")
	dyn.virtual_value = 5
	check(dyn.virtual_value == 5, "_set")
	var dyn_props := props_by_name(dyn)
	check(dyn_props.has("virtual_value"), "_get_property_list")
	check(dyn_props["secret"]["usage"] & PROPERTY_USAGE_EDITOR == 0 and dyn_props["shown"]["usage"] & PROPERTY_USAGE_EDITOR != 0, "_validate_property")
	check(dyn.property_can_revert("virtual_value") and dyn.property_get_revert("virtual_value") == 42, "_property_can_revert / _property_get_revert")


func _ready() -> void:
	var player := $Player
	var boss := $Boss
	var script: Script = player.get_script()
	check(script != null and script.get_class() == "JuliaScript", "Julia script attached from .tscn")
	check(script.can_instantiate() and not script.is_tool(), "script valid")
	check(script.get_instance_base_type() == &"Node2D", "instance base type")
	check(player.ready_called, "_ready ran")
	check(is_equal_approx(player.speed, 123.5), "exported property set in .tscn")
	check(player.label == "player", "property default")
	player.label = "hero"
	check(player.label == "hero", "GDScript writes a Julia property")
	check(player.has_method("take_damage") and player.has_method("_ready"), "has_method")
	check(not player.has_method("_physics_process"), "unimplemented callbacks are not methods")
	check(player.has_signal("hit"), "script signal declared")
	player.connect("hit", _on_hit)
	check(player.take_damage(10) == 90, "GDScript calls a Julia method")
	check(hits == [10], "Julia emits a signal connected in GDScript")
	check(player.describe() == "hero:90", "method without arguments")
	var names := []
	for p in player.get_property_list():
		names.append(p["name"])
	check(names.has("speed") and names.has("health") and names.has("Player.jl"), "property list with category")
	var methods := []
	for m in script.get_script_method_list():
		methods.append(m["name"])
	check(methods.has("take_damage") and methods.has("_ready"), "script method list")
	var failures: Array = player.julia_checks()
	for f in failures:
		check(false, "julia: " + f)
	check(failures.is_empty(), "Julia-side checks")

	check(boss.get_script().get_base_script() == script, "Boss.jl inherits Player.jl")
	check(boss.ready_called and boss.label == "boss", "derived _ready override")
	check(boss.armor == 5.0 and boss.speed == 300.0, "derived and inherited exported defaults")
	check(boss.take_damage(30) == 70, "inherited method")

	var broken := $Broken
	var broken_script: Script = broken.get_script()
	check(broken_script == null or not broken_script.can_instantiate(), "script with a syntax error is not instantiated")
	check(not broken.has_method("_ready") and broken.get("value") == null, "no instance for an invalid script")

	check_authoring(player)

	for i in 3:
		await get_tree().process_frame
	check(player.process_frames >= 2, "_process runs every frame")
	check(player.notifications.has(NOTIFICATION_READY) and player.notifications.has(NOTIFICATION_ENTER_TREE), "_notification")

	var n := 100000
	var t0 := Time.get_ticks_usec()
	for i in n:
		player.noop(i)
	var t1 := Time.get_ticks_usec()
	for i in n:
		player.speed
	var t2 := Time.get_ticks_usec()
	print("GDJL_PERF gdscript->julia call %.0f ns, property get %.0f ns" % [(t1 - t0) * 1000.0 / n, (t2 - t1) * 1000.0 / n])

	print('GDJL_TEST_RESULT {"name":"scripts","passed":%d,"failed":%d,"errored":0,"broken":0}' % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
