using Godot

# Custom Resource usable in the inspector and in .tres files (C#: [GlobalClass] partial class Item : Resource).
@global_class @godot_class mutable struct Item <: Resource
    @export title::String = ""
    @export power::Int = 1
end
