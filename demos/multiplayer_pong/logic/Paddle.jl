# Ported from godot-demo-projects mono/multiplayer_pong/logic/Paddle.cs (MIT, Godot contributors).
using Godot

const MOTION_SPEED = 150

@godot_class mutable struct Paddle <: Area2D
    @export left::Bool = false
    motion::Float64 = 0.0
    you_hidden::Bool = false
    screen_size_y::Float64 = 0.0
end

Godot._ready(self::Paddle) = (self.screen_size_y = get_viewport_rect(self).size.y; nothing)

function Godot._process(self::Paddle, delta::Float64)
    if is_multiplayer_authority(self)   # This peer controls the paddle.
        self.motion = get_action_strength(Input, "move_down") - get_action_strength(Input, "move_up")
        !self.you_hidden && self.motion != 0 && hide_you_label(self)
        self.motion *= MOTION_SPEED
        # Unreliable, so the position is updated as fast as possible even if a call is dropped.
        rpc(self, :set_pos_and_motion, self.position, self.motion)
    elseif !self.you_hidden
        hide_you_label(self)
    end
    translate(self, Vector2(0, self.motion * delta))
    # Set screen limits.
    self.position = Vector2(self.position.x, clamp(self.position.y, 16, self.screen_size_y - 16))
end

@rpc :unreliable function set_pos_and_motion(self::Paddle, pos::Vector2, motion::Float64)
    self.position = pos
    self.motion = motion
end

function hide_you_label(self::Paddle)
    self.you_hidden = true
    hide(get_node(Label, self, "You"))
end

function on_paddle_area_enter(self::Paddle, area::Area2D)
    is_multiplayer_authority(self) && rpc(area, :bounce, self.left, Float64(GD.randf()))
end
