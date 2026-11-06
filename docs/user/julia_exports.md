# Exported properties

Counterpart of Godot's [C# exported properties](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_exports.html). Fields marked with `@export` (C#: `[Export]`) appear in the inspector, are saved in scenes and resources, and are visible to other languages.

## Basics

```julia
using Godot

@enum Element Fire Water Earth

@godot_class mutable struct Mage <: Node2D
    @export spell::String = "Fireball"          # C#: [Export] public string Spell { get; set; } = "Fireball";
    @export mana::Int = 50
    @export element::Element = Fire             # Julia enums export as an enum hint
    @export target::Node2D                      # a node; nothing until assigned
    @export staff::Resource                     # any resource type
    cooldown::Float64 = 0.0                     # not exported: plain Julia field
end
```

Exported fields need a Variant-compatible type: numbers, `String`, `Symbol`, builtin math types, engine objects, `GDArray`, `GDDictionary`, `Vector{T}` of such types, packed arrays, and Julia `@enum`s. A field of a node or resource type without a default value starts as `nothing`. Values set in the inspector override the defaults written in the struct. The defaults are also used for the inspector's revert button.

```julia
m = Mage()
@test m.spell == "Fireball" && m.target === nothing
@test Godot.get(m, :mana) == 50              # visible through the engine like any property
set!(m, :mana, 75)
@test m.mana == 75
free(m)
```

## Hints

Each C# export hint attribute has a Julia macro:

```julia
@godot_class mutable struct Tuning <: Node
    @export_range (0, 100, 1; or_greater = true) health::Int = 100     # [Export(PropertyHint.Range, "0,100,1,or_greater")]
    @export_range (0.0, 1.0; step = 0.05, suffix = "m") ratio::Float64 = 0.5
    @export_enum ("Small", "Large:5") size::Int = 0                    # PropertyHint.Enum
    @export_flags ("Fire", "Water", "Earth") elements::Int = 0         # PropertyHint.Flags
    @export_flags_2d_physics layers::Int = 1                           # PropertyHint.Layers2DPhysics
    @export_file ("*.png", "*.jpg") image::String = ""                 # PropertyHint.File
    @export_dir folder::String = ""                                    # PropertyHint.Dir
    @export_multiline notes::String = ""                               # PropertyHint.MultilineText
    @export_placeholder "Name..." title::String = ""                   # PropertyHint.PlaceholderText
    @export_exp_easing ("attenuation",) falloff::Float64 = 1.0         # PropertyHint.ExpEasing
    @export_color_no_alpha tint::Color = Color(1, 1, 1)                # PropertyHint.ColorNoAlpha
    @export_node_path (Sprite2D,) sprite_path::NodePath = NodePath("") # PropertyHint.NodePathValidTypes
    @export_storage saved_only::Int = 3                                # saved, not shown
    @export_custom (Godot.PROPERTY_HINT_PASSWORD, "", Godot.PROPERTY_USAGE_DEFAULT) password::String = ""
end
```

```julia
props = Dict(String(p["name"]) => p for p in get_property_list(Tuning()))
@test props["health"]["hint"] == Int(Godot.PROPERTY_HINT_RANGE)
@test props["health"]["hint_string"] == "0,100,1,or_greater"
@test props["size"]["hint_string"] == "Small,Large:5"
```

## Groups, subgroups and categories

`@export_category`, `@export_group` and `@export_subgroup` organize the inspector (C#: `[ExportCategory]`, `[ExportGroup]`, `[ExportSubgroup]`):

```julia
@godot_class mutable struct Car <: Node
    @export_category("Car")
    @export_group("Engine"; prefix = "engine_")
    @export engine_power::Float64 = 150.0
    @export engine_torque::Float64 = 300.0
    @export_subgroup("Gears")
    @export gears::Int = 6
    @export_group("")
    @export color::Color = Color(1, 0, 0)
end
```

## Tool buttons

`@export_tool_button` shows a button in the inspector that runs a script function. It needs a `@tool` class (C#: `[ExportToolButton]`):

```julia
@tool @godot_class mutable struct Spawner <: Node
    @export count::Int = 3
    @export_tool_button ("Spawn", "Add") spawn_button = spawn!
end

spawn!(self::Spawner) = (self.count += 1; nothing)
```

## Typed collections, nodes and resources

```julia
@godot_class mutable struct Inventory <: Node
    @export item_names::GDArray{String}                # Array[String]
    @export prices::GDDictionary{String, Int}          # Dictionary[String, int]
    @export points::Vector{Vector2}                    # PackedVector2Array
    @export friends::GDArray{Node}                     # node array, assigned in the inspector
end
```

```julia
inv = Inventory()
push!(inv.item_names, "Potion")
inv.prices["Potion"] = 10
@test length(inv.item_names) == 1 && inv.prices["Potion"] == 10
free(inv)
```

Custom resources are `@global_class` scripts extending `Resource`, and can be used as export types. See [global classes](julia_global_classes.md).
