# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

extends Node
# Runs test_bindings.jl inside the engine; the Julia side prints the GDJL_TEST_RESULT line.


func _ready() -> void:
	var path := ProjectSettings.globalize_path("res://test_bindings.jl")
	var ok := JuliaRuntime.eval_string("include(raw\"%s\")" % path) == "true"
	get_tree().quit(0 if ok else 1)
