# Ported from godot-demo-projects mono/dodge_the_creeps/Main.cs (MIT, Godot contributors).
using Godot

@godot_class mutable struct Main <: Node
    @export mob_scene::Union{Nothing, PackedScene} = nothing   # Assigned in the editor (Main.tscn).
    score::Int = 0
end

function game_over(self::Main)
    stop(get_node(Godot.Timer, self, "MobTimer"))
    stop(get_node(Godot.Timer, self, "ScoreTimer"))

    # Methods of other Julia scripts are called through the engine, like C#'s `GetNode<HUD>(...)`.
    Godot.call(get_node(self, "HUD"), :show_game_over)

    stop(get_node(AudioStreamPlayer, self, "Music"))
    play(get_node(AudioStreamPlayer, self, "DeathSound"))
end

function new_game(self::Main)
    call_group(get_tree(self), "mobs", :queue_free)
    self.score = 0

    start_position = get_node(Marker2D, self, "StartPosition")
    Godot.call(get_node(self, "Player"), :start, start_position.position)

    start(get_node(Godot.Timer, self, "StartTimer"))

    hud = get_node(self, "HUD")
    Godot.call(hud, :update_score, self.score)
    Godot.call(hud, :show_message, "Get Ready!")

    play(get_node(AudioStreamPlayer, self, "Music"))
end

function on_start_timer_timeout(self::Main)
    start(get_node(Godot.Timer, self, "MobTimer"))
    start(get_node(Godot.Timer, self, "ScoreTimer"))
end

function on_score_timer_timeout(self::Main)
    self.score += 1
    Godot.call(get_node(self, "HUD"), :update_score, self.score)
end

function on_mob_timer_timeout(self::Main)
    if self.mob_scene === nothing
        GD.printerr("Mob scene is not set. You need to set it in the inspector.")
        return
    end
    # Create a new instance of the Mob scene.
    mob = instantiate(self.mob_scene)

    # Choose a random location on Path2D.
    mob_spawn_location = get_node(PathFollow2D, self, "MobPath/MobSpawnLocation")
    mob_spawn_location.progress_ratio = GD.randf()

    # Set the mob's direction perpendicular to the path direction, plus some randomness.
    direction = mob_spawn_location.rotation + Mathf.PI / 2 + GD.randf_range(-Mathf.PI / 4, Mathf.PI / 4)

    # Set the mob's position to a random location.
    mob.position = mob_spawn_location.position
    mob.rotation = direction

    # Choose the velocity for the mob.
    velocity = Vector2(GD.randf_range(150.0, 250.0), 0)
    mob.linear_velocity = rotated(velocity, direction)

    # Spawn the mob by adding it to the Main scene.
    add_child(self, mob)
end
