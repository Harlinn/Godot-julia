# Ported from godot-demo-projects mono/pong/Logic/CeilingFloor.cs (MIT, Godot contributors).
using Godot

const Ball = Godot.script_type("res://Logic/Ball.jl")

@godot_class mutable struct CeilingFloor <: Area2D
    @export bounce_direction::Int = 1
end

function on_area_entered(self::CeilingFloor, area::Area2D)
    if area isa Ball
        area.direction = normalized(area.direction + Vector2(0, self.bounce_direction))
    end
end
