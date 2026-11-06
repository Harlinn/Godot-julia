# Style guide

Counterpart of Godot's [C# style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_style_guide.html). It follows the [Julia style guide](https://docs.julialang.org/en/v1/manual/style-guide/) and Godot's naming, so that code reads the same as the engine API.

## Naming

| Item | Convention | Example |
|------|-----------|---------|
| Script file and class | PascalCase, file named after the class | `PlayerController.jl` → `PlayerController` |
| Functions, methods, fields, signals | snake_case | `take_damage`, `max_speed`, `@signal health_changed` |
| Mutating functions | `!` suffix | `reset!(self)` |
| Constants | UPPER_SNAKE_CASE | `const MAX_SPEED = 400` |
| Engine callbacks | Godot's names | `Godot._physics_process(self::Player, delta::Float64)` |

Name the receiver `self` and give it the script type as its first argument. This is what makes a function a script method that other languages can call.

## Layout of a script

```julia
using Godot

const MAX_SPEED = 400.0

# Class: signals, then exported fields, then private fields.
@godot_class mutable struct Ship <: Node2D
    @signal destroyed()
    @export max_speed::Float64 = MAX_SPEED
    @export thrust::Float64 = 120.0
    velocity::Vector2 = Vector2_ZERO
end

# Engine callbacks.
function Godot._physics_process(self::Ship, delta::Float64)
    self.position += self.velocity * Float32(delta)
end

# Public methods, then helpers.
function boost!(self::Ship)
    self.velocity = Vector2(min(Godot.length(self.velocity) + self.thrust, self.max_speed), 0)
    return nothing
end
```

```julia
ship = Ship()
boost!(ship)
@test ship.velocity == Vector2(120, 0)
free(ship)
```

## Other conventions

- Indent with 4 spaces and keep lines at 120 characters or fewer.
- Type the fields of a `@godot_class`. They are the script's storage and its inspector interface, and concrete types keep code fast.
- Type `self` and the arguments of engine callbacks. Type the arguments of public methods when GDScript or C# call them, because the types drive conversions and argument errors.
- Prefer `get_node(T, self, path)` to an untyped `get_node`, and write `Godot.Timer` for the classes whose names clash with Base.
- Put shared code in a package in the project environment rather than in scripts.
