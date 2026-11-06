# ADR 0003: Shape of the generated Julia engine API

- Status: Accepted
- Date: 2026-11-04

## Context

C# exposes Godot classes as C# classes. Methods are called on instances (`node.AddChild(c)`), static members and nested enums hang off the class name (`Node.ProcessModeEnum.Inherit`, `FileAccess.Open(...)`, `Input.IsActionPressed("jump")`), and names are converted to PascalCase. Julia uses multiple dispatch and has no class-scoped namespaces.

The obvious way to imitate `Class.MEMBER` in Julia is to overload `Base.getproperty(::Type{Node}, s::Symbol)`. Every such method intersects the `getproperty(::DataType, ::Symbol)` specialization that Base uses everywhere (`T.name`, `T.parameters`, ...). Loading the package would then invalidate a large amount of compiled Base code. We rejected this.

## Decision

- **Classes.** Every Godot class is an abstract type that mirrors the inheritance tree (`abstract type Node2D <: CanvasItem end`), rooted at hand-written `GodotObject` (Godot's `Object`, renamed as in C#). The concrete engine wrappers are `Godot.Native.<Class>`. Editor-only classes live in package `GodotEditor`, bound as `Godot.Editor` in the editor (ADR 0004), with wrappers in `Godot.Editor.Native`.
- **Methods.** Methods are generic functions whose first argument is the receiver, using Godot's snake_case names: `add_child(node, child)`. When Base exports a function with the same name (`close`, `get`, `lock`, `show`, `open`, ... 24 names in 4.7), the generated methods extend the Base function instead of shadowing it. This is not type piracy, because the receiver is always a Godot type. Names that are Julia keywords, non-function Base exports, or module-implicit (`eval`, `include`) get a trailing `_`. Every rename is listed in `generated/binding_report.txt`.
- **Static methods** take the class type as the receiver: `file_exists(FileAccess, path)`, `open(FileAccess, path, FileAccess_READ)`.
- **Singletons** are reached the same way: `get_version_info(Engine)`, `is_action_pressed(Input, "jump")`. This forwards to `singleton(Input)`, which is cached. `singleton(T)` returns the instance, which also supports property syntax (`singleton(Engine).time_scale`). This replaces C#'s `Input.IsActionPressed`; see the Context section for why `Input.is_action_pressed` is not offered.
- **Class enums and constants** are module-level names with the class prefix, as Gtk4.jl does: enum types `Node_ProcessMode`, values `Node_PROCESS_MODE_ALWAYS`, constants `Node_NOTIFICATION_READY`. `Object`'s members use the renamed prefix (`GodotObject_CONNECT_DEFERRED`). Global enums keep their Godot names (`Error`, `OK`, `KEY_A`); `Variant.Type` becomes `VariantType`. Enum values are typed (`<: GodotEnum`, or `<: GodotBitfield` with `|`, `&`, `xor`, `~`, `in`), show their names, and method arguments also accept plain integers.
- **Properties** use dot syntax (`node.position = Vector2(1, 2)`) through generated `getproperty`/`setproperty!` on the abstract class types. They resolve at compile time for literal names; the tests check type stability and zero allocations.
- **Utility functions** live in `GD` (`GD.print`, `GD.randf`), as in C#.
- **Name clashes with Base exports.** Classes whose names Base already exports (`Timer`, `WeakRef`) are defined but not exported; use `Godot.Timer`.

## Consequences

- No invalidation of Base code from type-level `getproperty`. Warm package load is about 0.6 s with 1036 classes and about 17k methods.
- Spellings differ from GDScript and C# in a predictable way: `Node.PROCESS_MODE_ALWAYS` becomes `Node_PROCESS_MODE_ALWAYS`, and `Input.is_action_pressed(x)` becomes `is_action_pressed(Input, x)`. The user docs (phase 16) must include a translation table.
- The C# parity row for singleton/static call syntax is met in capability, not in spelling.
