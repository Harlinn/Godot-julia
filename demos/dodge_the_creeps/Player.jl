# Ported from godot-demo-projects mono/dodge_the_creeps/Player.cs (MIT, Godot contributors).
using Godot

@godot_class mutable struct Player <: Area2D
    @signal hit()
    @export speed::Int = 400        # How fast the player will move (pixels/sec).
    screen_size::Vector2 = Vector2_ZERO   # Size of the game window.
end

function Godot._ready(self::Player)
    self.screen_size = get_viewport_rect(self).size
    hide(self)
end

function Godot._process(self::Player, delta::Float64)
    velocity = Vector2_ZERO
    is_action_pressed(Input, "move_right") && (velocity += Vector2(1, 0))
    is_action_pressed(Input, "move_left") && (velocity -= Vector2(1, 0))
    is_action_pressed(Input, "move_down") && (velocity += Vector2(0, 1))
    is_action_pressed(Input, "move_up") && (velocity -= Vector2(0, 1))

    animated_sprite = get_node(AnimatedSprite2D, self, "AnimatedSprite2D")
    if Godot.length(velocity) > 0
        velocity = normalized(velocity) * self.speed
        play(animated_sprite)
    else
        stop(animated_sprite)
    end

    position = self.position + velocity * Float32(delta)
    self.position = Vector2(clamp(position.x, 0, self.screen_size.x), clamp(position.y, 0, self.screen_size.y))

    if velocity.x != 0
        animated_sprite.animation = "right"
        animated_sprite.flip_v = false
        animated_sprite.flip_h = velocity.x < 0
    elseif velocity.y != 0
        animated_sprite.animation = "up"
        animated_sprite.flip_v = velocity.y > 0
    end
end

function start(self::Player, position::Vector2)
    self.position = position
    show(self)
    get_node(CollisionShape2D, self, "CollisionShape2D").disabled = false
end

function on_body_entered(self::Player, body::PhysicsBody2D)
    hide(self)  # Player disappears after being hit.
    emit_hit(self)
    # Must be deferred as we can't change physics properties on a physics callback.
    set_deferred(get_node(self, "CollisionShape2D"), :disabled, true)
end
