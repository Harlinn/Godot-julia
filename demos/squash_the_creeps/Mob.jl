# Ported from godot-demo-projects mono/squash_the_creeps/Mob.cs (MIT, Godot contributors).
using Godot

@godot_class mutable struct Mob <: CharacterBody3D
    @signal squashed()          # Emitted when the player jumped on the mob.
    @export min_speed::Int = 10 # Minimum speed of the mob in meters per second.
    @export max_speed::Int = 18 # Maximum speed of the mob in meters per second.
end

Godot._physics_process(self::Mob, delta::Float64) = (move_and_slide(self); nothing)

# This function will be called from the Main scene.
function initialize(self::Mob, start_position::Vector3, player_position::Vector3)
    # Place the mob at start_position, looking at the player.
    look_at_from_position(self, start_position, player_position, Vector3_UP)
    # Rotate randomly within -45..45 degrees so it doesn't move straight at the player.
    rotate_y(self, GD.randf_range(-Mathf.PI / 4, Mathf.PI / 4))
    random_speed = GD.randi_range(self.min_speed, self.max_speed)
    # A forward velocity in the direction the mob is looking.
    self.velocity = rotated(Vector3_FORWARD * random_speed, Vector3_UP, self.rotation.y)
    get_node(AnimationPlayer, self, "AnimationPlayer").speed_scale = random_speed / self.min_speed
end

function squash(self::Mob)
    emit_squashed(self)
    queue_free(self)   # Destroy this node.
end

on_visible_on_screen_notifier_screen_exited(self::Mob) = queue_free(self)
