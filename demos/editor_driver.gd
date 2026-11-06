@tool
extends EditorPlugin
# Injected by demos/run.jl for the editor_plugin demo: checks the Julia plugin's dock and its button, then quits.

func _enter_tree() -> void:
	_run.call_deferred()


func _run() -> void:
	for i in 120:
		await get_tree().process_frame
	var failures := []
	var docks := EditorInterface.get_base_control().find_children("Julia Spinner", "", true, false)
	if docks.is_empty():
		failures.append("Julia dock not found")
	else:
		var dock: Node = docks[0]
		EditorInterface.open_scene_from_path("res://main.tscn")
		for i in 30:
			await get_tree().process_frame
		var root := EditorInterface.get_edited_scene_root()
		var before := root.get_child_count() if root else -1
		(dock.get_node("AddButton") as Button).pressed.emit()
		if root == null or root.get_child_count() != before + 1:
			failures.append("Add Spinner button did not add a node")
		elif root.get_child(before).get("speed") != 1.0:
			failures.append("added node is not a Spinner")
		if dock.get_node("Count").text != "Spinners added: 1":
			failures.append("dock label not updated")
		var spinner := root.get_node_or_null("Spinner") if root else null
		if spinner == null or float(spinner.get("turns")) <= 0.0:
			failures.append("@tool Spinner does not run in the editor")
	print("GDJL_DEMO_OK" if failures.is_empty() else "GDJL_DEMO_FAILED: " + ", ".join(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
