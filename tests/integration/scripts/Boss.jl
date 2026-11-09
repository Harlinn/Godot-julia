# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot

# Script-to-script inheritance (C#: `partial class Boss : Player`).
@godot_class mutable struct Boss <: script_type("res://Player.jl")
    @export armor::Float64 = 5.0
end

function Godot._ready(self::Boss)
    self.ready_called = true
    self.label = "boss"
    nothing
end
