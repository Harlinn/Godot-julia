# Ported from godot-demo-projects mono/pong/Logic/Wall.cs (MIT, Godot contributors).
using Godot

const Ball = Godot.script_type("res://Logic/Ball.jl")

@godot_class mutable struct Wall <: Area2D
end

function on_wall_area_entered(self::Wall, area::Area2D)
    # Ball went off the side of the screen, reset it.
    area isa Ball && Godot.call(area, :reset!)
end
