# API differences from GDScript and C#

Counterpart of Godot's [C# API differences to GDScript](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_differences.html). The Julia API is generated from the same `extension_api.json` as C#'s, with these conventions.

## Naming

| Godot / GDScript | C# | Julia |
|------------------|----|-------|
| class `Node2D` | `Node2D` | type `Node2D` |
| method `add_child(node)` | `AddChild(node)` | `add_child(parent, node)`: the receiver is the first argument |
| property `position` | `Position` | `node.position`, or `get_position(node)` / `set_position(node, v)` |
| signal `body_entered` | `BodyEntered` event | `:body_entered`, `connect_body_entered(obj, f)` |
| constant `Node.NOTIFICATION_READY` | `Node.NotificationReady` | `Node_NOTIFICATION_READY` |
| enum value `Node.PROCESS_MODE_ALWAYS` | `Node.ProcessModeEnum.Always` | `Node_PROCESS_MODE_ALWAYS` (type `Node_ProcessMode`) |
| global enum `KEY_A` | `Key.A` | `KEY_A` |
| `Object` | `GodotObject` | `GodotObject` |
| `Array`, `Dictionary` | `Godot.Collections.Array`, `.Dictionary` | `GDArray`, `GDDictionary` |
| `StringName` | `StringName` | `Symbol` (`StringName === Symbol`) |
| `Timer`, `WeakRef` | same | `Godot.Timer`, `Godot.WeakRef` (not exported: Base already has `Timer`, `WeakRef`) |

Methods keep Godot's snake_case names. When Base already exports a function of the same name (`show`, `get`, `close`, `reset`, ...), the Godot methods are added to Base's function, so `show(node)` just works.

```julia
n = Node2D()
n.position = Vector2(10, 20)                  # C#: n.Position = new Vector2(10, 20);
@test n.position == Vector2(10, 20)
@test get_position(n) == n.position
set_name(n, "Thing")
@test get_name(n) === :Thing                  # StringNames are Symbols
hide(n)
@test !n.visible
show(n)                                       # CanvasItem.show (extends Base.show)
@test n.visible
@test Node <: GodotObject
t = Godot.Timer()
@test t isa Node
free(t)
free(n)
```

## Constructors, freeing and lifetime

`Node2D()` creates an engine object (C#: `new Node2D()`). Nodes are freed with `free` or `queue_free`. `RefCounted` objects such as resources are freed automatically when neither Julia nor the engine uses them. `is_instance_valid(obj)` tells whether an object still exists, and using a freed object throws `FreedObjectError` (C#: `ObjectDisposedException`).

```julia
n = Node()
free(n)
@test !is_instance_valid(n)
@test_throws FreedObjectError get_name(n)
```

## Singletons

Engine singletons (`Input`, `Engine`, `OS`, `ProjectSettings`, ...) are passed as the receiver, as their type. `singleton(T)` returns the object itself.

```julia
@test is_action_pressed(Input, "ui_accept") == false      # C#: Input.IsActionPressed("ui_accept")
@test get_frames_drawn(Engine) >= 0
@test singleton(Engine) === singleton(Engine)
@test get_setting(ProjectSettings, "application/config/name") == "Godot-julia doc tests"
```

## Global scope functions: `GD`

GDScript's global functions are in `Godot.GD`, as in C#'s `GD` class.

```julia
GD.print("printed by Godot")                   # C#: GD.Print
@test 0 <= GD.randf() < 1                      # C#: GD.Randf
@test GD.randi_range(1, 6) in 1:6
scene = GD.load(PackedScene, "res://main.tscn")   # C#: GD.Load<PackedScene>(...)
@test scene isa PackedScene
@test GD.instance_from_id(get_instance_id(DOC_ROOT)) === DOC_ROOT
```

Julia's own `println`, `rand` and so on also work. `println` and logging (`@info`, `@warn`) appear in Godot's Output panel.

## Enums and constants

```julia
@test Node_PROCESS_MODE_ALWAYS isa Node_ProcessMode
@test Int(KEY_A) == 65
mode = Node_PROCESS_MODE_DISABLED
@test string(mode) == "Node_PROCESS_MODE_DISABLED"
@test (GodotObject_CONNECT_DEFERRED | GodotObject_CONNECT_ONE_SHOT) isa GodotBitfield
```

## Math types and operators

The builtin types (`Vector2`, `Vector3`, `Transform2D`, `Basis`, `Quaternion`, `Color`, ...) are plain Julia structs with Godot's full method set. Operators and `≈` (`isapprox`, C#: `IsEqualApprox`) work as in C#. Godot's `Mathf` is `Godot.Mathf`.

```julia
v = Vector2(3, 4)
@test Godot.length(v) == 5
@test normalized(v) ≈ Vector2(0.6, 0.8)
@test v * 2 == Vector2(6, 8) && dot(v, v) == 25
@test rotated(Vector2(1, 0), Mathf.PI / 2) ≈ Vector2(0, 1)
@test Vector2_ZERO == Vector2(0, 0) && Vector3_UP == Vector3(0, 1, 0)   # C#: Vector2.Zero, Vector3.Up
@test Mathf.clamp(5, 0, 3) == 3
```

Builtin structs are immutable values, as in C#. To change one component, build a new value: `node.position = Vector2(node.position.x, 0)`.

## Typed lookups and strings

C#'s generic helpers take the type as the first argument: `GetNode<T>` is `get_node(T, node, path)`, and likewise `get_child(T, node, i)`, `get_parent(T, node)`, `get_owner(T, node)` and `instantiate(T, scene)`. The `OrNull` variants (`get_node_or_null`, `get_child_or_null`, `get_parent_or_null`, `get_owner_or_null`, `instantiate_or_null`) return `nothing` instead of throwing.

Godot's `String` methods work on Julia strings. Where Julia already has the function (`length`, `split`, `replace`, `lpad`, ...), use Julia's. Godot's wildcard `match` is `glob_match`, because `Base.match` is Julia's regex match.

```julia
root = Node()
add_child(root, Node2D())
@test get_child(Node2D, root, 0) isa Node2D && get_child_or_null(Sprite2D, root, 0) === nothing
@test get_parent(Node, get_child(root, 0)) === root
free(root)
@test glob_match("level_03.tscn", "level_*.tscn") && matchn("README.md", "*.MD")
```

## Vararg and default arguments

Godot's default arguments are Julia default arguments. Vararg methods (`call`, `emit_signal`, `rpc`) take Julia varargs.

```julia
node = Node()
@test get_child_count(node) == 0          # include_internal defaults to false
emit_signal(node, :ready)                 # vararg: no extra arguments
free(node)
```
