# Godot + Julia (GodotJL) — Project Instructions

## Goal

Make Julia a first-class scripting language for Godot 4, with **feature parity with Godot's C#/.NET support**.
The parity specification is [docs/csharp-parity-matrix.md](../docs/csharp-parity-matrix.md). Every change must move a row in that matrix toward `DONE` or explicitly mark it `GAP` with a justification.

## Reference Implementation

Godot's C# support lives in the `godotengine/godot` repository under `modules/mono/`. Treat it as the behavioral spec. Fetch files from GitHub at the pinned Godot tag (see `GODOT_VERSION`) when you need details. Key locations:

| Area | Path in godotengine/godot |
|------|---------------------------|
| Language / script / instance | `modules/mono/csharp_script.h`, `csharp_script.cpp` |
| Runtime hosting | `modules/mono/mono_gd/gd_mono.cpp` |
| Native ↔ managed interop | `modules/mono/glue/runtime_interop.cpp`, `glue/GodotSharp/GodotSharp/Core/NativeInterop/` |
| Script bridge | `glue/GodotSharp/GodotSharp/Core/Bridge/` (`ScriptManagerBridge.cs`, `CSharpInstanceBridge.cs`) |
| Bindings generator | `modules/mono/editor/bindings_generator.cpp` |
| Builtin math types | `glue/GodotSharp/GodotSharp/Core/*.cs` (`Vector2.cs`, `Basis.cs`, `Mathf.cs`, ...) |
| Async | `Core/SignalAwaiter.cs`, `Core/GodotSynchronizationContext.cs`, `Core/GodotTaskScheduler.cs` |
| Source generators / analyzers | `modules/mono/editor/Godot.NET.Sdk/Godot.SourceGenerators/` |
| Editor tooling | `modules/mono/editor/GodotTools/` |
| Assembly loading / hot reload | `glue/GodotSharp/GodotPlugins/Main.cs` |
| User docs | godot-docs: `tutorials/scripting/c_sharp/` |

Godot is MIT licensed; when porting logic, add an attribution comment referencing the source file.

## Architecture (decided — change only via an ADR in `docs/adr/`)

- **Delivery**: a GDExtension built on `godot-cpp` that registers a `ScriptLanguageExtension`. Works with official, unmodified Godot editor/export templates. If something C# achieves only because it is an engine module cannot be done via GDExtension, record it as `GAP` in the matrix with a workaround and an ADR.
- **Runtime**: `libjulia` embedded via the Julia C embedding API inside the GDExtension library. One Julia runtime per process.
- **Native host (`native/`)**: thin C++ — runtime bootstrap, `ScriptLanguageExtension`/`ScriptExtension` shims, resource loader/saver, editor/export plugin shims. Everything that can live in Julia lives in Julia.
- **Julia packages (`julia/`)**:
  - `Godot` — user-facing API: generated bindings + hand-written core (builtins, Variant, macros, signals, async). Analog of `GodotSharp`.
  - `GodotEditor` — separate package loaded only when the editor runs and bound as `Godot.Editor` (ADR 0004) — analog of `GodotSharpEditor`.
  - `GodotBindgen` — generator reading `extension_api.json`. Analog of `bindings_generator.cpp`.
  - `Godot.Runtime` (internal submodule) — script bridge called from C++. Analog of `ScriptManagerBridge`/`CSharpInstanceBridge`.
- **Script model**: one `.jl` file = one script = one `@godot_class` whose name matches the file name (PascalCase), mirroring C#'s class-name-equals-file-name rule. Each script file is evaluated into its own fresh module per reload generation (solves struct redefinition). Shared non-script code lives in a regular Julia package in the user's project and is loaded with `using`.
- **Type mapping**: every Godot class is a Julia **abstract type** mirroring the Godot hierarchy (`abstract type Node <: GodotObject end`). Each instantiable/returnable class gets a concrete native wrapper. User scripts are `mutable struct`s subtyping the abstract type (`@godot_class mutable struct Player <: CharacterBody2D`). Godot `Object` → `GodotObject` (same rename as C#). Names that clash with `Base` exports (e.g. `Timer`) are defined but not exported; users write `Godot.Timer`.
- **Naming**: keep Godot's snake_case for methods, properties, signals; PascalCase types. Virtual overrides are method extensions: `Godot._ready(self::Player)`.
- **Precision**: `real_t` is `Float32` or `Float64` depending on the Godot build configuration (C# supports both).

## Repository Layout

```
native/                 C++ GDExtension host (SCons or CMake, godot-cpp submodule)
julia/Godot/            User-facing Julia package (src/generated/ is build output, gitignored)
julia/GodotEditor/      Editor-only API package (src/generated/ is build output, gitignored)
julia/GodotBindgen/     Bindings generator
addons/godot_julia/     Distributable addon: .gdextension, binaries, editor assets, script templates
tests/integration/      Headless Godot projects driven by CI
demos/                  Ports of the official C# demo projects
docs/                   Parity matrix, ADRs, user documentation
GODOT_VERSION           Pinned Godot 4.x tag
```

## Conventions

- Julia: latest stable release (≥ 1.12, required for `juliac --trim`). Godot: the tag in `GODOT_VERSION`.
- Never hand-edit generated code; change the generator.
- Hot paths (method calls with isbits arguments, property access, builtin math) must be type-stable and allocation-free. Cache method binds and `StringName`s.
- **No Julia exception may unwind through C/C++ frames.** Every `@cfunction` entry point catches, converts to a Godot error (`push_error` with Julia stack trace), and returns a safe value.
- GC safety: root Julia values held by C++ (`JL_GC_PUSH*` or a global `IdDict` pin table); C++ never stores raw `jl_value_t*` without a pin.
- Threads: calls arriving on non-Julia threads must `jl_adopt_thread()`; long native calls from Julia must enter GC-safe regions.
- No `@cfunction` closures (unsupported on some architectures); pass userdata pointers instead.
- Each feature ships with tests: Julia unit tests in `julia/*/test/` and/or headless integration tests in `tests/integration/`.
- After each phase, update the status column in the parity matrix.

## Phase Order (prompts in `.github/prompts/`)

1. `gdjl-01-scaffold` → 2. `gdjl-02-embed-runtime` → 3. `gdjl-03-ffi-layer` → 4. `gdjl-04-bindings-generator` → 5. `gdjl-05-builtin-math` → 6. `gdjl-06-variant-collections` → 7. `gdjl-07-object-model` → 8. `gdjl-08-script-language` → 9. `gdjl-09-authoring-macros` → 10. `gdjl-10-signals-async` → 11. `gdjl-11-hot-reload` → 12. `gdjl-12-editor-integration` → 13. `gdjl-13-debugging` → 14. `gdjl-14-export` → 15. `gdjl-15-testing-ci` → 16. `gdjl-16-docs-demos` → 17. `gdjl-17-parity-audit`.

Use `gdjl-00-next` to resume work at the next incomplete phase.
