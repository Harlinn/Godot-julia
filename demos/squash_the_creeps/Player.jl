# Ported from godot-demo-projects mono/squash_the_creeps/Player.cs (MIT, Godot contributors).
using Godot

const Mob = Godot.script_type("res://Mob.jl")

@godot_class mutable struct Player <: CharacterBody3D
    @signal hit()                     # Emitted when the player was hit by a mob.
    @export speed::Int = 14           # How fast the player moves in meters per second.
    @export fall_acceleration::Int = 75   # Downward acceleration in the air (m/s²).
    @export jump_impulse::Int = 20    # Vertical impulse applied when jumping (m/s).
    @export bounce_impulse::Int = 16  # Vertical impulse when bouncing over a mob (m/s).
    target_velocity::Vector3 = Vector3_ZERO
end

function Godot._physics_process(self::Player, delta::Float64)
    direction = Vector3_ZERO
    is_action_pressed(Input, "move_right") && (direction += Vector3(1, 0, 0))
    is_action_pressed(Input, "move_left") && (direction -= Vector3(1, 0, 0))
    # In 3D, the XZ plane is the ground plane.
    is_action_pressed(Input, "move_back") && (direction += Vector3(0, 0, 1))
    is_action_pressed(Input, "move_forward") && (direction -= Vector3(0, 0, 1))

    animation = get_node(AnimationPlayer, self, "AnimationPlayer")
    if direction != Vector3_ZERO
        direction = normalized(direction)   # Prevent diagonal movement being very fast.
        get_node(Node3D, self, "Pivot").basis = looking_at(Basis, direction)
        animation.speed_scale = 4
    else
        animation.speed_scale = 1
    end

    # Ground velocity, then vertical velocity.
    v = self.target_velocity
    vy = is_on_floor(self) ? v.y : v.y - self.fall_acceleration * Float32(delta)
    is_on_floor(self) && is_action_just_pressed(Input, "jump") && (vy = self.jump_impulse)
    v = Vector3(direction.x * self.speed, vy, direction.z * self.speed)

    # Iterate through all collisions that occurred this frame.
    for index in 0:get_slide_collision_count(self)-1
        collision = get_slide_collision(self, index)
        mob = get_collider(collision)
        # Squash a mob hit from above and bounce.
        if mob isa Mob && dot(Vector3_UP, get_normal(collision)) > 0.1
            Godot.call(mob, :squash)
            v = Vector3(v.x, self.bounce_impulse, v.z)
            break   # Prevent further duplicate calls.
        end
    end
    self.target_velocity = v

    # Moving the character.
    self.velocity = v
    move_and_slide(self)
    pivot = get_node(Node3D, self, "Pivot")
    r = pivot.rotation
    pivot.rotation = Vector3(Mathf.PI / 6 * self.velocity.y / self.jump_impulse, r.y, r.z)
end

function die(self::Player)
    emit_hit(self)
    queue_free(self)
end

on_mob_detector_body_entered(self::Player, body::Node3D) = die(self)
