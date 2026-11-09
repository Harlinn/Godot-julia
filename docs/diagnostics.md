# Script diagnostics

Errors in a Julia script class are reported while the script loads or validates. They are shown in the editor and
in the output as `res://File.jl:<line>: GDJLnnnn: message`. They mirror the diagnostics of Godot's C# source
generators and analyzers (`Godot.SourceGenerators`, codes `GDnnnn`). C# rules that cannot occur in Julia (partial
classes, delegates, indexers, explicit interface implementations) have no Julia counterpart.

| Code | C# code | Raised when |
|------|---------|-------------|
| GDJL0001 | GD0001 | `@godot_class` is not applied to a `mutable struct` (C#: missing `partial` on a GodotObject class) |
| GDJL0003 | GD0003 | a script file defines more than one class named after the file |
| GDJL0004 | — | a script file defines no `@godot_class` named after the file (C#: the `[ScriptPath]` class is missing) |
| GDJL0005 | — | unknown `@godot_class` option or class-body annotation (e.g. `@export_bogus`) |
| GDJL0006 | GD0109, GD0203 | invalid declaration in the class body: methods, `const` fields, a malformed `@signal` (including a return type, C#'s GD0203), or `@export` combined with `@export_tool_button` (GD0109) |
| GDJL0007 | — | a member (field or tool button) is declared twice, including in base script classes, or uses the reserved name `__ptr` |
| GDJL0102 | GD0102 | the type of an exported member is not Variant-compatible |
| GDJL0103 | GD0103 | an exported member is read-only (`const`) |
| GDJL0105 | — | invalid arguments to an export or group annotation (e.g. `@export_range` without `min, max`) |
| GDJL0106 | — | an export hint does not apply to the member type (e.g. `@export_range` on a `String`) |
| GDJL0107 | GD0107 | a class not derived from `Node` exports a `Node` member |
| GDJL0108 | GD0108 | `@export_tool_button` in a class that is not `@tool` |
| GDJL0110 | GD0110 | `@export_tool_button` does not name a script function (C#: the member is not a `Callable`) |
| GDJL0202 | GD0202 | a signal parameter type is not Variant-compatible |
| GDJL0301 | GD0301 | the element type of an exported typed collection (`GDArray{T}`, `GDDictionary{K,V}`, `Vector{T}`) is not Variant-compatible (C#: `[MustBeVariant]`) |
| GDJL0401 | GD0401 | the class does not derive from `GodotObject` or a derived class |
| GDJL0402 | GD0402 | the class is generic (parametric) |
| GDJL0501 | — | invalid `@rpc` usage: unknown argument, or the first parameter is not typed with a script class |

## C# diagnostics without a Julia counterpart

Every diagnostic of `Godot.SourceGenerators` at Godot 4.7.2 is either mapped above or listed here.

| C# code | C# rule | Why Julia has no counterpart |
|---------|---------|------------------------------|
| GD0002 | missing `partial` on a type containing nested GodotObject classes | Julia has no nested types or `partial` |
| GD0101 | exported member is static | script fields are per instance; there are no static fields to annotate |
| GD0104 | exported property is write-only | fields are always readable |
| GD0105 | exported property is an indexer | Julia structs have no indexers |
| GD0106 | exported property is an explicit interface implementation | Julia has no interfaces |
| GD0111 | tool button must be an expression-bodied property | `@export_tool_button` names a function (GDJL0110 covers misuse) |
| GD0201 | signal delegate name must end with `EventHandler` | `@signal` declares the signal by name; there are no delegates |
| GD0302 | generic type parameter must be `[MustBeVariant]` | script classes cannot be generic (GDJL0402); element types are checked directly (GDJL0301) |
| GD0303 | parent symbol of a `[MustBeVariant]` argument not handled (engine bug) | internal error of the C# analyzer |
