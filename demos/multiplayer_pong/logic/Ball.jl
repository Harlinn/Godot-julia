# Ported from godot-demo-projects mono/multiplayer_pong/logic/Ball.cs (MIT, Godot contributors).
using Godot

const DEFAULT_SPEED = 100.0

@godot_class mutable struct Ball <: Area2D
    direction::Vector2 = Vector2_LEFT
    stopped::Bool = false
    speed::Float64 = DEFAULT_SPEED
    screen_size::Vector2 = Vector2_ZERO
end

Godot._ready(self::Ball) = (self.screen_size = get_viewport_rect(self).size; nothing)

function Godot._process(self::Ball, delta::Float64)
    self.speed += delta
    # The ball moves normally for both players, even if slightly out of sync, so the motion stays smooth.
    self.stopped || translate(self, Float32(self.speed * delta) * self.direction)

    # Check screen bounds to make the ball bounce.
    p, d = self.position, self.direction
    if (p.y < 0 && d.y < 0) || (p.y > self.screen_size.y && d.y > 0)
        self.direction = Vector2(d.x, -d.y)
    end

    if is_multiplayer_authority(self)
        # Only the server decides when the ball is out on its (left) side, and only the peer on the right side,
        # so the game stays playable with high latency.
        if p.x < 0
            rpc(get_parent(self), :update_score, false)
            rpc(self, :reset_ball, false)
        elseif p.x > self.screen_size.x
            rpc(get_parent(self), :update_score, true)
            rpc(self, :reset_ball, true)
        end
    end
end

# Both players can make it bounce.
@rpc :any_peer :call_local function bounce(self::Ball, left::Bool, random::Float64)
    dx = left ? abs(self.direction.x) : -abs(self.direction.x)
    self.speed *= 1.1
    self.direction = normalized(Vector2(dx, random * 2 - 1))
end

@rpc :any_peer :call_local stop(self::Ball) = (self.stopped = true; nothing)

@rpc :any_peer :call_local function reset_ball(self::Ball, for_left::Bool)
    self.position = self.screen_size / 2
    self.direction = for_left ? Vector2_LEFT : Vector2_RIGHT
    self.speed = DEFAULT_SPEED
end
