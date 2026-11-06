# Ported from godot-demo-projects mono/dodge_the_creeps/Mob.cs (MIT, Godot contributors).
using Godot

@godot_class mutable struct Mob <: RigidBody2D
end

function Godot._ready(self::Mob)
    animated_sprite = get_node(AnimatedSprite2D, self, "AnimatedSprite2D")
    mob_types = get_animation_names(animated_sprite.sprite_frames)
    play(animated_sprite, mob_types[rand(1:length(mob_types))])
end

on_visible_on_screen_notifier2d_screen_exited(self::Mob) = queue_free(self)
