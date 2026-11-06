# ADR 0008: Script language, script classes and the script bridge

- Status: Accepted
- Date: 2026-11-06

## Context

Phase 08 makes `.jl` files Godot scripts, like `.cs` files with C#. The reference implementation is `modules/mono/csharp_script.cpp` (`CSharpLanguage`, `CSharpScript`, `CSharpInstance`) and `GodotSharp/Core/Bridge/ScriptManagerBridge.cs` / `CSharpInstanceBridge.cs`. C# is an engine module; we use the GDExtension API (`ScriptLanguageExtension`, `ScriptExtension`, `script_instance_create3`) per ADR 0000.

## Decision

- **Thin native shims** (`native/src/julia_script.{h,cpp}`): `JuliaLanguage`, `JuliaScript`, `ResourceFormatLoaderJulia` and `ResourceFormatSaverJulia` implement every virtual. Static language data (name, extension, reserved words, delimiters, PascalCase file names) lives in C++. Everything else is forwarded to Julia.
- **Bridge ABI v3**: `GDJLJuliaAPI` gains one entry, `script_call(method, self, args, argc, r_ret)`. `method` is a string literal naming a handler in `Godot.Runtime.BRIDGE` (`runtime/bridge.jl`), `self` is the engine object of the language or script, and arguments and the result are Variants. This mirrors C#'s `ScriptManagerBridge`. One generic entry point keeps the C ABI stable while handlers evolve. It returns nil when Julia is not running, so the shims degrade gracefully.
- **Script instances are created in Julia**: `script_instance_create3` is called with a process-wide `GDExtensionScriptInstanceInfo3` table of `@cfunction`s (`runtime/instances.jl`). The instance data is a rooted `ScriptInstance` (user struct, class info, script pointer). The user struct becomes the object's wrapper (`bind_wrapper!`, ADR 0007). In Godot 4.7, `Object::get_script()` returns `script_instance->get_script()`, so the instance **owns a reference to its script** (like `GDScriptInstance`). The reference is released in `free_func`, which also unbinds the struct (`unbind_wrapper!`).
- **Class model**: `@godot_class mutable struct Player <: Node2D ... end` defines `abstract type Player <: Node2D` (what users dispatch on and what script subclasses extend) plus a concrete `mutable struct var"Player#Instance" <: Player` with `__ptr` and every field, inherited ones first. Field initializers run per instance. Fields declared as an engine type without a default become `Union{Nothing, T}` (C# reference fields are null by default). `godot_class_name(::Type{<:Player})` is the native base, and `Player()` creates the engine object with the script attached (C#'s `new Player()`).
- **One file, one class, one module per generation**: loading evaluates the source into a fresh `Module(:Script_<Name>_<gen>)` with `using Godot`. Struct redefinition is never needed, and hot reload (phase 11) swaps generations. The file must define exactly one `@godot_class` whose name matches the file name (exactly, or ignoring case and underscores).
- **Inheritance**: the base is a Godot class, `script_type("res://base.jl")`, or a Julia `@global_class` name. Derived classes inherit fields, signals and methods. Method lookup walks the class chain's modules.
- **Dispatch**: a method name resolves once per generation (cached in `ScriptClassInfo`) to either an engine callback (a stub generic function in `Godot`, e.g. `Godot._ready`) or a function of the script module. In both cases only methods whose first argument is declared as a supertype of the instance type (not `Any`) count. So helpers and Godot's own functions are not exposed, and unimplemented callbacks are not reported to the engine, which then skips them. Arguments are converted from Variants per the declared types. Arity and conversion failures become `GDEXTENSION_CALL_ERROR_*`. User exceptions are reported with the Julia stack trace and the call returns nil.
- **Properties**: fields whose types are Variant-compatible are Godot properties. `@export` fields are stored and shown in the inspector; the others are script variables. Fields of other Julia types stay private to Julia.
- **Errors**: parse and evaluation errors are reported as `res://File.jl:<line>: <message>`, and the script is left invalid (not instantiable). `_validate` parses with `Base.JuliaSyntax` and lowers each top-level expression with macros expanded, without running anything. `_get_global_class_name` is parse-only.
- **Placeholders**: in the editor, non-`@tool` scripts get `placeholder_script_instance_create` instances that expose exported fields with their defaults.

## Consequences

- Each engine call into a script costs a StringName→Symbol lookup (cached by interned pointer), a method-cache lookup, Variant conversion and a dynamic call (`invokelatest`). Faster paths (typed thunks per method) can come later without changing the ABI.
- Script objects outlive their scripts' Julia types only as long as the engine keeps the resource. `script_type` pins resources for the session (C# keeps assemblies loaded).
- `_init` runs inside `instance_create`, before Godot attaches the instance to the object. Engine calls that need the script instance (script signals, script properties through `Object.get`) are not available in `_init`. This is the same constraint as C# constructors. Use `_ready` or `_enter_tree` for such work.
