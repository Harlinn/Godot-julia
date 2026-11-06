using Godot

@godot_class mutable struct Bad <: Node
end

# Deliberate syntax error: the editor build must report res://Bad.jl:7.
broken(self::Bad) = (1, 2]

fixed(self::Bad) = 3
