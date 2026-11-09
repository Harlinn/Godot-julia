# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot

# Depends on Mover by inheritance: reloading Mover reloads this script too.
@godot_class mutable struct Fancy <: script_type("res://Mover.jl")
    sparkle::Int = 5
end

sparkle_twice(self::Fancy) = 2 * self.sparkle
