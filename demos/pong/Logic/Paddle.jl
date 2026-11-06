# Ported from godot-demo-projects mono/pong/Logic/Paddle.cs (MIT, Godot contributors).
using Godot

const MOVE_SPEED = 100
const Ball = Godot.script_type("res://Logic/Ball.jl")

@godot_class mutable struct Paddle <: Area2D
    # All three of these change for each paddle.
    ball_dir::Int = 1
    up::String = ""
    down::String = ""
end

function Godot._ready(self::Paddle)
    n = lowercase(string(get_name(self)))
    self.up = n * "_move_up"
    self.down = n * "_move_down"
    self.ball_dir = n == "left" ? 1 : -1
end

function Godot._process(self::Paddle, delta::Float64)
    # Move up and down based on input.
    input = get_action_strength(Input, self.down) - get_action_strength(Input, self.up)
    position = self.position + Vector2(0, input * MOVE_SPEED * delta)
    self.position = Vector2(position.x, clamp(position.y, 16, get_viewport_rect(self).size.y - 16))
end

function on_area_entered(self::Paddle, area::Area2D)
    if area isa Ball
        # Assign new direction.
        area.direction = normalized(Vector2(self.ball_dir, rand() * 2 - 1))
    end
end
