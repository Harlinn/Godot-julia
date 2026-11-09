# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

extends Node
# Injected by demos/run.jl (via override.cfg) to play each demo headlessly and check that its Julia code ran.
# Prints "GDJL_DEMO_OK" when the checks pass, "GDJL_DEMO_FAILED: ..." otherwise, then quits.

var failures := []


func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)


func user_arg(name: String) -> bool:
	return name in OS.get_cmdline_user_args()


func wait_seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var demo: String = ProjectSettings.get_setting("application/config/name")
	if demo.begins_with("Dodge"):
		await dodge()
	elif demo.begins_with("Pong Multiplayer"):
		await multiplayer_pong()
	elif demo.begins_with("Pong"):
		await pong()
	elif demo.begins_with("Squash"):
		await squash()
	else:
		failures.append("no driver for " + demo)
	if failures.is_empty():
		print("GDJL_DEMO_OK")
	else:
		print("GDJL_DEMO_FAILED: ", ", ".join(failures))
	get_tree().quit(0 if failures.is_empty() else 1)


func dodge() -> void:
	var main := get_tree().current_scene
	main.call("new_game")
	check(main.get_node("HUD/MessageLabel").text == "Get Ready!", "HUD message after new_game")
	check(main.get_node("Player").visible, "player shown by start")
	await wait_seconds(4.0)
	check(main.get("score") > 0, "score increases")
	check(get_tree().get_nodes_in_group("mobs").size() > 0, "mobs spawned")
	main.call("game_over")
	check(main.get_node("HUD/MessageLabel").text == "Game Over", "game over message")
	await wait_seconds(3.5)
	check(main.get_node("HUD/StartButton").visible, "start button back after the async game-over sequence")


func pong() -> void:
	var ball := get_tree().current_scene.get_node("Ball")
	var start: Vector2 = ball.position
	await wait_seconds(6.0)
	check(ball.position != start, "ball moves")
	check(ball.get("speed") > 100.0, "ball speeds up")
	check(ball.get("direction") != Vector2.LEFT, "ball bounced off a paddle, ceiling or floor")


func squash() -> void:
	var main := get_tree().current_scene
	var before := main.get_child_count()
	await wait_seconds(3.0)
	check(main.get_child_count() > before, "mobs spawned")


func multiplayer_pong() -> void:
	var lobby := get_tree().current_scene.get_node("LobbyPanel")
	if user_arg("host"):
		lobby.call("on_host_pressed")
		check(lobby.get_node("StatusOk").text == "Waiting for player...", "hosting")
	else:
		lobby.get_node("Address").text = "127.0.0.1"
		lobby.call("on_join_pressed")
	# The client process starts a few seconds after the host and needs time to boot Julia.
	for i in 300:
		if get_tree().root.has_node("Pong"):
			break
		await wait_seconds(0.1)
	check(get_tree().root.has_node("Pong"), "game started on both peers")
	if not get_tree().root.has_node("Pong"):
		return
	var ball := get_tree().root.get_node("Pong/Ball")
	var start: Vector2 = ball.position
	# Sampled before the ball can reach a side and be reset to the center.
	await wait_seconds(1.0)
	# When one peer quits, the other's lobby frees the game (as in the original demo).
	check(is_instance_valid(ball) and ball.position != start,
			"ball moves (start %s, now %s, stopped %s, speed %s, processing %s)" % [start,
			ball.position if is_instance_valid(ball) else "freed", ball.get("stopped") if is_instance_valid(ball) else "-",
			ball.get("speed") if is_instance_valid(ball) else "-", ball.is_processing() if is_instance_valid(ball) else "-"])
	if not user_arg("host"):
		await wait_seconds(8.0)   # stay connected until the host has checked its game (it quits first)
