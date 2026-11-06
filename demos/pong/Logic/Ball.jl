# Ported from godot-demo-projects mono/pong/Logic/Ball.cs (MIT, Godot contributors).
using Godot

const DEFAULT_SPEED = 100.0

@godot_class mutable struct Ball <: Area2D
    direction::Vector2 = Vector2_LEFT
    initial_pos::Vector2 = Vector2_ZERO
    speed::Float64 = DEFAULT_SPEED
end

Godot._ready(self::Ball) = (self.initial_pos = self.position; nothing)

function Godot._process(self::Ball, delta::Float64)
    self.speed += delta * 2
    self.position += Float32(self.speed * delta) * self.direction
end

function reset!(self::Ball)
    self.direction = Vector2_LEFT
    self.position = self.initial_pos
    self.speed = DEFAULT_SPEED
end
