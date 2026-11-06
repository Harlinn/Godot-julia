# Global classes

Counterpart of Godot's [C# global classes](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_global_classes.html). A `@global_class` script is registered by name: it appears in the *Create New Node* and *Create Resource* dialogs and can be used as an export type or a base class (C#: `[GlobalClass]`).

```julia
using Godot

@global_class @icon "res://addons/godot_julia/icons/JuliaScript.svg" @godot_class mutable struct Stats <: Resource
    @export health::Int = 100
    @export speed::Float64 = 5.0
end
```

`@icon` sets the icon shown in the editor (C#: `[Icon]`). Instances of a global-class resource can be created in the inspector, saved as `.tres` files and exported from other scripts. Every Julia script can name a global class directly, as a field type, a method signature or a base class, just as any C# file can name a `[GlobalClass]`:

```julia
@godot_class mutable struct Unit <: Node
    @export stats::Union{Nothing, Stats} = nothing
end
```

```julia
s = Stats()
s.health = 42
u = Unit()
u.stats = s
@test u.stats.health == 42
free(u)
```

## Inheriting from a global class

Other scripts can extend a global class by its name, as in C# (`Boss <: Enemy`). Without `@global_class`, use `script_type("res://enemy.jl")` as the base.

```julia
@global_class @godot_class mutable struct Creature <: Node
    @export hp::Int = 10
end

hurt!(self::Creature, n::Int) = (self.hp -= n; self.hp)
```

```julia
@godot_class abstract mutable struct BigCreature <: Creature
    @export armor::Int = 2
end
```

`abstract` keeps a class out of the create dialogs while still allowing subclasses (C#: `abstract` classes).

```julia
T = Godot.script_type("res://julia_global_classes/BigCreature.jl")
@test T <: Creature && isabstracttype(T)
```

## Restrictions

As in C#, a global class must be the class defined by its file (`Stats.jl` defines `Stats`), and a class extending `Node` can only export nodes if it is itself a node.
