# Julia features

Counterpart of Godot's [C# language features](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_features.html): type conversion and casting, calling scripts in other languages, and conditional code with feature tags.

## Type conversion and casting

Every Godot class is a Julia abstract type in the same hierarchy (`Sprite2D <: Node2D <: CanvasItem <: Node <: GodotObject`), so Julia's `isa` and dispatch work on engine objects. Engine methods return the most specific wrapper, and an object with a Julia script returns the script instance itself.

```julia
root = Node2D()
sprite = Sprite2D()
set_name(sprite, "Sprite")
add_child(root, sprite)

@test get_node(Sprite2D, root, "Sprite") === sprite   # C#: GetNode<Sprite2D>("Sprite")
@test get_node(root, "Sprite") isa Sprite2D           # untyped: still the concrete wrapper
@test sprite isa Node2D                               # C#: sprite is Node2D
@test as(Camera2D, sprite) === nothing                # C#: sprite as Camera2D
@test as(Node2D, sprite) === sprite
@test_throws TypeError get_node(Camera2D, root, "Sprite")   # C#: InvalidCastException
free(root)
```

`get_node(T, node, path)` throws if the node does not exist or has another type. `get_node_or_null(node, path)` returns `nothing` for a missing node.

Numbers convert as in Julia. Godot's `float` is `Float64` in method arguments and `real_t` (usually `Float32`) inside vectors, so `Vector2(1, 2)` stores `Float32` components. Use `Float32(x)` when mixing a `Float64` with vector components in hot code.

```julia
v = Vector2(1, 2)
@test v.x isa Float32
delta = 0.016
@test v * Float32(delta) ≈ Vector2(0.016, 0.032)
```

## Calling other scripts and languages

Objects with a GDScript or C# script are reached through Godot's dynamic API, as C# does with `Call`, `Get` and `Set`. Julia scripts are called the same way from other languages.

```julia
node = Node()
set_meta(node, :hp, 10)
@test get_meta(node, :hp) == 10
@test Godot.call(node, :get_meta, :hp) == 10     # any method by name (C#: Call)
@test Godot.get(node, :name) == get_name(node)    # any property by name (C#: Get)
set!(node, :name, "Renamed")                      # C#: Set
@test get_name(node) === :Renamed
@test has_property(node, :process_mode)
free(node)
```

Properties defined by another language's script are also available as `obj.property`.

## Preprocessor defines → feature tags

C# uses compile-time symbols such as `GODOT_WINDOWS` with `#if`. In Julia, use Godot's feature tags:

- `Godot.has_feature(:tag)` checks a tag at runtime (`OS.has_feature`).
- `Godot.@feature(:tag)` is a compile-time constant in games exported with a system image, so the untaken branch is compiled out. Elsewhere it is a runtime check.

```julia
platform = if Godot.@feature(:windows)
    "windows"
elseif Godot.@feature(:linux)
    "linux"
elseif Godot.@feature(:macos)
    "macos"
else
    "other"
end
@test platform in ("windows", "linux", "macos", "other")
@test Godot.has_feature(:pc) == Godot.@feature(:pc)
```

| C# define | Julia |
|-----------|-------|
| `GODOT_WINDOWS`, `GODOT_LINUXBSD`, `GODOT_MACOS` | `@feature(:windows)`, `@feature(:linux)`, `@feature(:macos)` |
| `GODOT_PC`, `GODOT_MOBILE`, `GODOT_WEB` | `@feature(:pc)`, `@feature(:mobile)`, `@feature(:web)` |
| `TOOLS` | `@feature(:editor)` |
| `DEBUG` | `@feature(:debug)` |
| custom export feature | `@feature(:my_feature)` |
