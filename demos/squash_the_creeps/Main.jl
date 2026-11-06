# Ported from godot-demo-projects mono/squash_the_creeps/Main.cs (MIT, Godot contributors).
using Godot

@godot_class mutable struct Main <: Node
    @export mob_scene::Union{Nothing, PackedScene} = nothing
end

Godot._ready(self::Main) = hide(get_node(Control, self, "UserInterface/Retry"))

function Godot._unhandled_input(self::Main, event::InputEvent)
    if is_action_pressed(event, "ui_accept") && get_node(Control, self, "UserInterface/Retry").visible
        reload_current_scene(get_tree(self))   # This restarts the current scene.
    end
end

function on_mob_timer_timeout(self::Main)
    # Create a new instance of the Mob scene.
    mob = instantiate(self.mob_scene)

    # Choose a random location on the SpawnPath.
    mob_spawn_location = get_node(PathFollow3D, self, "SpawnPath/SpawnLocation")
    mob_spawn_location.progress_ratio = GD.randf()

    player_position = get_node(Node3D, self, "Player").position
    Godot.call(mob, :initialize, mob_spawn_location.position, player_position)

    # Spawn the mob by adding it to the Main scene.
    add_child(self, mob)

    # Update the score when the mob is squashed (C#: `mob.Squashed += label.OnMobSquashed`).
    label = get_node(self, "UserInterface/ScoreLabel")
    connect(mob, :squashed, () -> Godot.call(label, :on_mob_squashed))
end

function on_player_hit(self::Main)
    stop(get_node(Godot.Timer, self, "MobTimer"))
    show(get_node(Control, self, "UserInterface/Retry"))
end
