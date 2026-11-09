# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot

@godot_class mutable struct Bad <: Node
end

# Deliberate syntax error: the editor build must report res://Bad.jl:10.
broken(self::Bad) = (1, 2]

fixed(self::Bad) = 3
