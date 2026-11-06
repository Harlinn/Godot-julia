# ADR 0014: Exporting games

- Status: Accepted
- Date: 2026-11-05

## Context

C# exports publish the game's assemblies and the .NET runtime into a `data_<name>_<platform>_<arch>/` folder next to the executable. Release exports can also be precompiled (ReadyToRun) or fully compiled ahead of time (NativeAOT). Script sources are replaced by empty files in the PCK (GodotTools/Export/ExportPlugin.cs). A Julia game needs the following in its export:

- the Julia runtime libraries (libjulia, codegen/LLVM for the JIT, the libraries of the standard library);
- compiled Godot bindings and project packages;
- the scripts.

All of this has to work with official, unmodified export templates (ADR 0001).

## Decision

- **Export plugin.** The native `JuliaExportPlugin` (`EditorExportPlugin`) is registered by `JuliaEditorPlugin` and forwards `_export_begin`, `_export_file` (only `.jl` files) and `_export_end` to `GodotEditor.Tools` (`tools/export.jl`). Preset options:
  - `julia/export/mode`: `sysimage` (default) or `jit`.
  - `julia/export/include_sources`.
- **Payload folder.** `_export_begin` builds `data_<Package>_<platform>_<arch>/` under `.godot/julia_export/` with the worker (`tools/export_build.jl`) in a child process, then adds it with `add_shared_object`. Godot's PC exporter copies shared-object directories next to the executable. The folder contains:
  - `julia/`: runtime libraries plus Base and stdlib sources;
  - `sys.<dll|so|dylib>`: sysimage mode only;
  - `env/Project.toml`: the game's dependencies;
  - `scripts/`: sources of scripts that could not be compiled in;
  - `depot/`: jit mode only;
  - `godot_julia_export.cfg`.

  At startup the native host looks for a `data_*` folder containing that cfg file, next to its library or one level up on macOS. If one is found, it starts that runtime with that image and environment, ignoring `julia/runtime/*`. It also isolates `LOAD_PATH` and `DEPOT_PATH` to the folder and sets `Godot.Runtime.EXPORT_DIR`.
- **sysimage mode (ReadyToRun analog).** The worker runs `julia --output-o` on a build script.
  - The script loads `Godot` and the project's packages, then calls `Godot.Runtime.precompile_scripts!`. That function evaluates every script into its module, with base scripts and `script_type` targets first and global classes resolved from the editor's class list. It records the modules in `PRECOMPILED_SCRIPTS` by `res://` path, then precompiles their methods for the concrete instance types.
  - The object file is linked with Julia's bundled `lld` (`Base.Linking.link_image`), so neither PackageCompiler nor a C compiler is needed.
  - At runtime, `load_script!` takes the module from `PRECOMPILED_SCRIPTS` and loads its dependency scripts. No source is parsed and hot reload is unused.
  - Scripts whose top-level code needs the running engine (e.g. `const X = load(...)`) cannot be evaluated at build time. They produce an export warning, ship as sources in `scripts/`, and are evaluated at runtime. The JIT remains available.
- **jit mode (debug only).** Package sources go into `depot/packages/` (inside a depot, so the pkgimages stay valid when the folder moves). Their caches are compiled into `depot/compiled/`, and the default system image is shipped. Script sources stay in the PCK.
- **Debug vs release.**
  - Debug images: `-O2 -g1`. The runtime runs at `-O2`, keeping backtraces with `res://` file:line and the debug server and remote debugger, which are already limited to debug builds.
  - Release images: `-O3 -g0`. The runtime runs at `-O3` and native frames carry no line info.
- **Feature tags.** `Godot.has_feature(:tag)` checks at runtime. `Godot.@feature(:tag)` expands to a constant during an export build, using the preset's feature list, so the untaken branch is compiled out like C#'s `#if GODOT_WINDOWS`. Elsewhere it expands to a runtime check. `GodotEditor` is never loaded in exports and is not part of the image.
- **CPU target.** Images use Julia's multi-versioned default for x86_64 (`generic;sandybridge,…;haswell,…`), and `generic` elsewhere. For tests it can be overridden with `GDJL_EXPORT_CPU_TARGET`.
- **Host platform only.** The image and runtime are those of the editor's Julia, so a preset for another OS or architecture fails with an explanation. CI exports on each desktop OS. Android, iOS and Web are out of scope.
- **No `trimmed` mode (`juliac --trim`, the NativeAOT analog).** Trimming requires code that is statically resolvable and free of `eval`. The script runtime defines classes with `Core.eval`, dispatches dynamically on script types and keeps the JIT for scripts that are not compiled in. Parity row 10.6 therefore stays PARTIAL, and `sysimage` is the supported AOT mode.

## Consequences

- Exported games start Julia without compiling the bindings. The size and startup cost of each mode are recorded in docs/perf.md.
- The payload is large, because the runtime ships the JIT (LLVM, codegen) and the image contains the full generated bindings.
- On macOS, `libjulia` and the image in the `data_*` folder must be signed with the app. These are notes in docs/export.md and are untested here.
