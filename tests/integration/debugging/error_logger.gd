# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

extends Logger
# Records every error Godot reports, with the script backtraces (Julia frames come from
# JuliaLanguage::_debug_get_current_stack_info). Loggers are called from any thread.

var _errors: Array = []
var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var frames := []
	for bt in script_backtraces:
		for i in bt.get_frame_count():
			frames.append({"language": bt.get_language_name(), "file": bt.get_frame_file(i),
					"line": bt.get_frame_line(i), "function": bt.get_frame_function(i)})
	_mutex.lock()
	_errors.append({"function": function, "file": file, "line": line, "code": code, "rationale": rationale,
			"type": error_type, "frames": frames})
	_mutex.unlock()


func _log_message(_message: String, _error: bool) -> void:
	pass


func take() -> Array:
	_mutex.lock()
	var e := _errors.duplicate()
	_errors.clear()
	_mutex.unlock()
	return e
