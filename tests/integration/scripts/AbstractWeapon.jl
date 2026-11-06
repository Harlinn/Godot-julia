using Godot

@global_class @icon "res://addons/godot_julia/icons/JuliaScript.svg" @godot_class abstract mutable struct AbstractWeapon <: Resource
    @export damage::Int = 1
end
