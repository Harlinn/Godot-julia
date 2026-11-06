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
| GDJL0006 | — | invalid declaration in the class body (methods, `const` fields, malformed `@signal`) |
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
