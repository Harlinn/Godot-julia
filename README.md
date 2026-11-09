# Godot-julia — Julia scripting for Godot 4

Godot-julia makes Julia a scripting language for Godot 4. The goal is feature parity with Godot's C#/.NET support; progress is tracked in [docs/csharp-parity-matrix.md](docs/csharp-parity-matrix.md).

It is a GDExtension, so it works with the official Godot editor and export templates. You do not need a special build. See [ADR 0000](docs/adr/0000-gdextension-vs-module.md).

## Status

Phases 01–16 are complete: the native host embeds Julia; the `Godot` package exposes the full generated engine API, builtin math, Variant and collections, and the object model; `.jl` files are Godot scripts with the C# authoring features (exports with every hint, groups, tool buttons, signals, global classes, RPC, static methods, analyzer-style diagnostics); signals take Julia closures, with async/await on signals and `WorkerThreadPool` support; scripts hot-reload with their state; the editor has a Julia Build button and panel, project bootstrap, package management, external editors, templates and syntax highlighting; Julia errors are script errors at `res://` lines with Julia frames in Godot's debugger, plus `Godot.@breakpoint` and a debug REPL (see [docs/debugging.md](docs/debugging.md)); and desktop exports ship the Julia runtime with the scripts compiled into a system image (see [docs/export.md](docs/export.md)). Phase 15's test tooling (one-command runner, in-engine `Test` runner, parity-test check, leak checks, benchmarks) passes locally; its CI and release workflows have not run on GitHub yet. Phase 16 adds the user guide ([docs/user/](docs/user/README.md), one page per C# documentation page, with every example run by the doc tests) and Julia ports of the official C# demos ([demos/](demos/README.md)). See the parity matrix for row-by-row status.

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Godot | see [GODOT_VERSION](GODOT_VERSION) (4.7.2-stable) | Standard (non-.NET) editor |
| Julia | ≥ 1.12 | `julia` on `PATH` or `JULIA_DIR` set to the install root |
| Python + SCons | Python ≥ 3.8, SCons ≥ 4.0 | `pip install scons` |
| C++ toolchain | as for Godot | Windows: Visual Studio 2022 "Desktop development with C++" (or MinGW); Linux: GCC/Clang; macOS: Xcode CLT |

## Getting the sources

```sh
git clone --recursive https://github.com/Harlinn/Godot-julia.git
cd Godot-julia
# or, in an existing clone:
git submodule update --init --recursive
```

## Building the native host

```sh
scons -C native target=editor            # used by the editor
scons -C native target=template_debug    # debug exports
scons -C native target=template_release  # release exports
# options: platform=windows|linux|macos arch=x86_64|arm64 precision=single|double julia_dir=<path>
#          dev_fallbacks=no (distributed builds) asan=yes (AddressSanitizer, GCC/Clang)
```

Libraries go into `addons/godot_julia/bin/`.

## Fetching the engine API

```sh
julia scripts/fetch_api.jl [path/to/godot]   # or set GODOT
```

This writes `extension_api.json` (with class docs) and `gdextension_interface.json` to `native/api/`. If no Godot binary is found, the script falls back to the copies bundled with godot-cpp, which do not include class docs.

To get typed bindings for classes registered by other GDExtensions (as C# does), dump from a project that loads them and regenerate: `julia scripts/fetch_api.jl --project=path/to/project`. This also writes `native/api/project_extension_api.json`, and the generator adds that file's extension classes to the engine API. Without regenerating, objects of such classes are still reachable by name (`get_singleton(Engine, :Name)`, `Godot.call(obj, :method)`) and are wrapped as their nearest known ancestor class.

## Generating the Julia bindings

```sh
julia scripts/generate_bindings.jl                     # single precision (default)
julia scripts/generate_bindings.jl --precision=double  # for double-precision Godot builds
```

This writes `julia/Godot/src/generated/` and `julia/GodotEditor/src/generated/` (both gitignored). It contains the GDExtension interface table and wrappers, the builtin layout for the chosen build configuration, the method-hash table, and the full engine API (`classes.jl`, `globals.jl`). It also writes `binding_report.txt`, which lists counts and every renamed identifier. Run it again after changing `GODOT_VERSION`. The integration test runner generates the bindings automatically if they are missing.

The generated API follows [ADR 0003](docs/adr/0003-generated-api-shape.md). In short:

```julia
add_child(node, child)                       # node.AddChild(child)
node.position = Vector2(1, 2)                # node.Position = ...
is_action_pressed(Input, "jump")             # Input.IsActionPressed("jump")
file_exists(FileAccess, "res://a.txt")       # FileAccess.FileExists(...)
set_process_mode(node, Node_PROCESS_MODE_ALWAYS)
GD.print("hi"); scene = GD.load(PackedScene, "res://main.tscn")
Godot.Editor.EditorPlugin                    # editor-only API, loaded only in the editor (ADR 0004)
rotated(Vector2(1, 0), Mathf.TAU / 4)        # Vector2(1, 0).Rotated(Mathf.Tau / 4); math types per ADR 0005
from_euler(Basis, Vector3(0.1, 0.2, 0.3))    # Basis.FromEuler(...); Basis_IDENTITY, Color_ALICE_BLUE, ...
v = Variant(42); Int(v)                      # (int)variant; typed containers and marshalling per ADR 0006
nodes = get_children(node)                   # GDArray{Node} <: AbstractVector, shared with the engine
connect(node, :ready, Callable(() -> println("ready")))   # Callable.From(() => ...)
```

### Objects, lifetime and threads

Objects follow [ADR 0007](docs/adr/0007-object-model.md):

```julia
n = Node(); add_child(root, n)
get_child(root, 0) === n                     # one Julia wrapper per engine object
s = get_node(Sprite2D, root, "Player/Sprite")   # GetNode<Sprite2D>(...); TypeError if the type does not match
as(Node2D, n)                                # `n as Node2D` -> nothing on mismatch; `n isa Node2D` is `is`
free(n); is_instance_valid(n)                # false; calling into `n` throws FreedObjectError
r = Resource(); finalize(r)                  # Dispose(): drop Julia's reference now (RefCounted are otherwise GC-managed)
helper.score; set!(helper, :score, 3); Godot.call(helper, :add, 1)   # members of GDScript (or any) scripts
```

Threading rules: the same engine rules apply as in C# (scene tree on the main thread, resources and servers as documented by Godot). Wrapping and creating objects from several Julia threads is safe. Finalizers never call Godot; they queue releases that run on the main thread. Set the Julia thread count with the `julia/runtime/threads` project setting.

### Scripts

A script file `Player.jl` defines one class named after the file ([ADR 0008](docs/adr/0008-script-language.md)). Attach it to a node in the editor or in a `.tscn` like any script:

```julia
using Godot

@godot_class mutable struct Player <: CharacterBody2D
    @export speed::Float64 = 300.0      # [Export] public double Speed = 300
    health::Int = 100                    # script variable
    target::Node                         # engine objects default to `nothing`
    @signal hit(damage::Int)             # [Signal] delegate void HitEventHandler(int damage)
end

Godot._ready(self::Player) = println("ready, speed = ", self.speed)
Godot._physics_process(self::Player, delta::Float64) = nothing

function take_damage(self::Player, amount::Int)    # callable from GDScript: player.take_damage(5)
    self.health -= amount
    emit_signal(self, :hit, amount)
end
```

Engine callbacks are methods of Godot's functions (`Godot._ready`, `Godot._process`, `Godot._input`, `Godot._notification`, `Godot._get`, `Godot._set`, ...). Callbacks a script does not define are not reported to the engine, as with C#. Inherit from another script with `@godot_class mutable struct Boss <: script_type("res://Player.jl")`, or by name if the base is a `@global_class`. Prefix with `@tool`, `@global_class` or `@icon "res://icon.svg"` for the C# `[Tool]`, `[GlobalClass]` and `[Icon]` attributes. `Player()` creates a scripted object from Julia (C#'s `new Player()`). Syntax and load errors are reported as `res://Player.jl:<line>: ...`.

Export annotations and the other C# attributes ([ADR 0009](docs/adr/0009-script-authoring.md)); arguments are a tuple after a space:

```julia
@tool @global_class @godot_class mutable struct Turret <: Node2D
    @export_category("Combat")
    @export_range (0, 100, 1; or_greater = true) health::Int = 100
    @export_enum ("Small", "Large") size::Int = 0          # Julia @enum and Godot enum fields get ENUM hints automatically
    @export_group("Visuals"; prefix = "visual_")
    @export_color_no_alpha visual_tint::Color = Color(1, 1, 1)
    @export_file ("*.png",) visual_icon::String = ""
    @export target::Node2D                                  # Node/Resource/typed collections get the right hints
    @export_storage cooldown::Float64 = 0.0                 # saved, not shown in the inspector
    @export_tool_button ("Reset", "Reload") reset = reset!  # editor button running `reset!(self)`
    @signal fired(power::Int)                               # generates emit_fired(self, p) / connect_fired(self, f)
end

reset!(self::Turret) = (self.health = 100; nothing)
@rpc :any_peer :call_local function shoot(self::Turret, power::Int)   # rpc(turret, :shoot, 3)
    emit_fired(self, power)
end
max_health(::Type{Turret}) = 100                           # static method; engine: script.call_static("max_health")
```

`SignalName(Turret).fired`, `PropertyName(Turret).health` and `MethodName(Turret)` are the C# `SignalName`/`PropertyName`/`MethodName` tables. Mistakes are reported with codes mirroring the C# analyzers (see [docs/diagnostics.md](docs/diagnostics.md)).

### Signals and async

Any Julia function or closure can be connected to a signal ([ADR 0010](docs/adr/0010-signals-async.md)). A closure that captures an engine object is disconnected automatically when that object is freed, like a C# delegate whose `Target` is a `GodotObject`:

```julia
c = connect(button, :pressed, () -> println("pressed"))   # returns the Callable; flags = GodotObject_CONNECT_ONE_SHOT, ...
disconnect(button, :pressed, c)
connect_pressed(button, on_pressed)                         # per-signal helpers, like C# `button.Pressed += OnPressed`
call_deferred(() -> println("end of frame"))
```

`await` runs in Godot tasks: Julia tasks pinned to the main thread whose continuations resume during the engine's frame, as with C#'s `GodotSynchronizationContext`:

```julia
function Godot._ready(self::Turret)
    godot_task() do                                         # or: @async_godot begin ... end
        args = @await to_signal(self, :fired)               # signal arguments as a tuple
        wait(delay(self, 0.5))                              # await get_tree().create_timer(0.5).timeout
        wait(next_frame(self))                              # await get_tree().process_frame
    end
end
```

If the awaited object is freed, the task ends quietly instead of leaking. Unhandled task errors go to `push_error` with the Julia stack trace. CPU work can run on `WorkerThreadPool` (`add_task(WorkerThreadPool, f)`) or `Threads.@spawn`; hand results back to the main thread with `Godot.post(f)`.

### Hot reload

Editing a script while the game runs (the editor's live script reload) or in the editor reloads it in place ([ADR 0011](docs/adr/0011-hot-reload.md)). Scripts that inherit from or `script_type` the edited one reload with it. Live instances keep the values of fields that still exist, including Julia-only values, enums and structs declared in the script. New fields get their initializers, and `_init` is not re-run. Fields of other instances and connected closures are moved to the new instances, and closures run the new code. If the new version does not load, the instances keep their state but run no code until a later reload succeeds; failed reloads from disk are retried for `julia/project/reload_attempts` frames. `JuliaRuntime.reload_scripts(["res://Player.jl"])` triggers a reload from GDScript. Load Revise.jl in your project to reload changed packages too.

### Editor

The editor tools ([ADR 0012](docs/adr/0012-editor-integration.md)) mirror C#'s GodotTools:

- **Project.** Creating the first Julia script, or *Project → Tools → Julia → Create Julia Project*, writes `Project.toml`. The package is named after `julia/project/package_name` or the Godot project, and depends on the `Godot` package of the addon. Games and the editor use this environment.
- **Build.** The toolbar button, the "Julia" bottom dock or the menu runs `Pkg.instantiate`, `Pkg.precompile` and a validation of every `.jl` file in a background Julia process, then hot-reloads scripts. Problems are listed with `file:line`; activating one opens the script there. Set `julia/build/build_on_play` to build before running the project.
- **Packages.** *Add/Remove/Update Packages* and *Package Status* in the Julia menu run `Pkg` with output in the Julia dock (C#'s NuGet).
- **Editors.** `julia/editor/external_editor` opens scripts in VS Code/VSCodium (with Julia-extension workspace settings), Emacs, Vim/Neovim or a custom command (`julia/editor/custom_exec_path[_args]` with `{file}`, `{line}`, `{col}`, `{project}`). The built-in script editor highlights Julia and marks validation errors.
- **Templates.** Create Script offers Object, Node, Resource, EditorPlugin and EditorScript templates. Project templates go in `res://script_templates/<Base>/*.jl`.
- **Editor scripts.** Editor plugins and editor scripts can be written in Julia: `@tool @godot_class mutable struct MyPlugin <: Godot.Editor.EditorPlugin`.

## Running the tests

Everything CI runs, with one command (needs Julia, SCons + a C++ toolchain, and a Godot editor binary; `julia scripts/fetch_godot.jl [--templates]` downloads the pinned one into `.tools/godot/`):

```sh
julia scripts/test_all.jl                 # build native/, bindings, unit tests, parity check, integration + leak checks, doc tests, demos
julia scripts/test_all.jl --exports       # + template libraries and export tests (slow: system images)
julia scripts/test_all.jl --benchmarks    # + benchmarks against tests/benchmarks/baseline.toml
julia scripts/test_all.jl --no-build --precision=double   # skip the native build; double-precision bindings
```

The individual steps follow.

Julia unit tests:

```sh
julia --project=julia/Godot -e "using Pkg; Pkg.test()"
julia --project=julia/GodotBindgen -e "using Pkg; Pkg.test()"
JULIA_LOAD_PATH="$PWD/julia:@stdlib" julia julia/GodotEditor/test/runtests.jl       # Windows: "$PWD\julia;@stdlib"
JULIA_LOAD_PATH="$PWD/julia:@stdlib" julia julia/GodotTestRunner/test/runtests.jl
```

The builtin math tests compare against golden values computed by Godot from `julia/Godot/test/fixtures/math_cases.txt`. After adding cases or changing `GODOT_VERSION`, regenerate them with `julia scripts/make_math_golden.jl`.

Parity coverage: `julia scripts/check_parity_tests.jl` fails when a `DONE` row of the parity matrix has no test tagging it with a comment such as `# parity: 5.6, 6.1–6.6`.

API surface: `julia --project=julia/Godot scripts/api_diff.jl [--strict] [--verbose]` compares GodotSharp's public API at the pinned Godot tag (sparse-cloned into `.tools/godot-mono`) with the `Godot` package under the documented naming rules, and lists C# members without a Julia counterpart.

Headless integration tests. These need the native library built (`target=editor`) and a Godot binary, found via `GODOT`, the gitignored `.tools/godot/` folder (on Windows, use the `_console.exe` build), or `PATH`:

```sh
julia tests/integration/run.jl            # all projects
julia tests/integration/run.jl runtime    # a single project
julia tests/integration/run.jl --leaks    # with --verbose; fails on leaked objects or resources
```

For each project, the runner copies the addon in, runs `--import` once to register the extension, and then runs the project (with the extra arguments in `run_args.txt`, e.g. `--editor` for the headless editor test). The project reports through `GodotTestRunner` (`julia/GodotTestRunner`): it runs `Test` test sets inside the engine and prints `GDJL_TEST_RESULT {"name":…,"passed":N,"failed":F,"errored":E,"broken":B}`. The runner checks the exit code, that result line, the lines listed in `expect_output.txt`, and that every `ERROR:`/`WARNING:` line is listed in `expect_errors.txt`. Package operations run offline (`JULIA_PKG_OFFLINE=true`).

Benchmarks: `julia tests/benchmarks/run.jl [--update]` measures engine calls, property access, Variant conversion, signal emits, engine → script calls and `_process` dispatch (with GDScript as the in-process reference) and compares them with `tests/benchmarks/baseline.toml` (see [docs/perf.md](docs/perf.md)).

Doc tests: `julia scripts/doctest_docs.jl [page.md...]` runs every ```` ```julia ```` block of `docs/user/*.md` in a headless Godot project (blocks defining a `@godot_class` become script files; mark snippets that cannot run with ```` ```julia {no-run} ````).

Demos: `julia demos/run.jl [demo...]` plays each demo headlessly through `demos/driver.gd` (the editor-plugin demo runs in the headless editor) and fails on errors, warnings or leaks. `julia scripts/port_csharp_demo.jl <godot-demo-projects> <mono demo> <dest>` converts the scenes and project of a C# demo as the starting point for a port.

Export tests. These need the `template_debug` and `template_release` libraries and the export templates (installed, or the official `Godot_v<version>_export_templates.tpz` in `.tools/godot/`). Each `sysimage` export compiles a system image, which takes several minutes:

```sh
julia tests/export/run.jl                          # sysimage-debug, sysimage-release, jit-debug
julia tests/export/run.jl sysimage-debug           # one configuration
```

The runner exports `tests/export/game` and the smoke project for the host platform with the headless editor, runs the exported games and prints export time, size and Julia startup time. `GDJL_EXPORT_CPU_TARGET=generic` shortens image builds while iterating.

## Julia runtime discovery

The extension loads Julia when it starts. Exported games use the runtime in their `data_*` folder ([docs/export.md](docs/export.md)). Otherwise it uses the first location that works:

1. a runtime bundled next to the extension library (`addons/godot_julia/bin/julia/`);
2. the project setting `julia/runtime/path`;
3. the `JULIA_BINDIR` environment variable;
4. `julia` on `PATH`;
5. in development builds only, the Julia used at build time.

The other `julia/runtime/*` project settings control the thread count, optimization level, signal handling, a custom system image, and an extra depot path. If no Julia is found, the editor reports an error and keeps working without Julia scripting.

## Repository layout

```
native/                 C++ GDExtension host (SCons, godot-cpp submodule)
julia/Godot/            User-facing Julia package
julia/GodotEditor/      Editor-only API package, loaded only in the editor (ADR 0004)
julia/GodotBindgen/     Bindings generator
julia/GodotTestRunner/  In-engine Test runner for integration projects (GDJL_TEST_RESULT line)
addons/godot_julia/     Distributable addon (.gdextension, binaries, icons, templates)
tests/integration/      Headless Godot test projects
tests/export/           Export test game and runner
tests/benchmarks/       Hot-path benchmarks and baselines
demos/                  Julia ports of the official C# demos, plus an editor-plugin demo
docs/                   Parity matrix, ADRs, design notes; docs/user/ is the user guide
scripts/                Developer tooling (test_all, fetch_godot, check_parity_tests, package_addon, ...)
.github/workflows/      CI (ci.yml) and release (release.yml)
```

## Continuous integration and releases

`.github/workflows/ci.yml` runs `scripts/test_all.jl` on Windows, Ubuntu and macOS with Julia 1 (current stable) and 1.12, including the export tests (Julia 1 entries), plus a double-precision job on Ubuntu that builds the Godot editor from source. It also runs the parity-test check, informational benchmarks, and an optional AddressSanitizer job. SCons objects (`SCONS_CACHE`) and the Julia depot are cached.

`.github/workflows/release.yml` runs on a `vX.Y.Z` tag that matches `julia/Godot/Project.toml`. It builds the editor, debug and release libraries for every platform, packages the addon with `scripts/package_addon.jl`, attaches the zip to a GitHub release, and asks JuliaRegistrator (the GitHub app must be installed on the repository) to register the `Godot` package (`subdir=julia/Godot`).

## License

Copyright 2026 Espen Harlinn. Licensed under the [Apache License, Version 2.0](LICENSE); see [NOTICE](NOTICE) for included third-party code. Code ported from Godot (MIT) keeps its attribution comments, and the demo ports in `demos/` remain under the MIT License ([demos/LICENSE.md](demos/LICENSE.md)).

Source files carry an SPDX header; `julia scripts/license_headers.jl` adds it to new files (`--check` lists files without one).
