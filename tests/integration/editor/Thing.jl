# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot

@global_class @icon "res://addons/godot_julia/icons/JuliaScript.svg" @godot_class mutable struct Thing <: Resource
	@export power::Int = 1
end
