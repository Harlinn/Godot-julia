# C#/.NET → Julia Parity Matrix

Status values: `TODO`, `PARTIAL`, `DONE`, `GAP` (cannot be matched — must link an ADR with justification and workaround).
"Phase" refers to the prompt in `.github/prompts/gdjl-NN-*.prompt.md` that owns the row.

## 1. Runtime, Packaging, Build

| # | C#/.NET capability | Julia equivalent | Phase | Status |
|---|--------------------|------------------|-------|--------|
| 1.1 | .NET runtime hosted in-process via hostfxr | `libjulia` embedded in the GDExtension | 02 | DONE (runtime loaded dynamically, ADR 0002; `tests/integration/runtime`) |
| 1.2 | Separate ".NET" editor build required | Works with the standard Godot editor via GDExtension | 01 | DONE (official 4.7.2 editor loads the extension; `tests/integration/smoke`) |
| 1.3 | `Godot.NET.Sdk` + `GodotSharp` NuGet packages, versioned with Godot | `Godot` Julia package in a registry, versioned with Godot | 01, 14, 15 | PARTIAL (package versioned with the pinned Godot 4.7.2 and shipped in the addon zip (`scripts/package_addon.jl`, tested locally); `release.yml` builds all platforms, publishes the zip and asks JuliaRegistrator to register `julia/Godot` on a version tag; not yet run: the repository is not published and the registrator app not installed) |
| 1.4 | Third-party libraries via NuGet | Third-party packages via `Pkg` | 12 | DONE (Project → Tools → Julia: Add/Remove/Update Packages, Package Status, run by a child Julia process with output in the Julia panel; the project environment is active in editor and game; add/status/rm tested offline in `julia/GodotEditor/test`) |
| 1.5 | Auto-generated `.csproj`/`.sln` on first script | Auto-generated `Project.toml` (+ `Manifest.toml`) on first script | 12 | DONE (creating the first script or *Create Julia Project* writes `Project.toml` depending on `Godot` via `[sources]`; *Build* instantiates `Manifest.toml`; tested in `tests/integration/editor`, ADR 0012) |
| 1.6 | "Build" button + MSBuild output panel | "Build" (instantiate + precompile) button + Julia output panel | 12 | DONE (toolbar/panel/menu Build runs instantiate, precompile and script validation in a child process without blocking the editor, then hot-reloads; optional build before Play; tested in `tests/integration/editor`) |
| 1.7 | Single and double precision (`real_t`) builds | `real_t` selected from build configuration | 03, 05, 15 | PARTIAL (bindings + math verified with `real_t = Float64` bindings; native `precision=double` library builds (Windows, tested locally); CI job building a double-precision Godot editor and running the suite is defined in `ci.yml` but has not run yet) |
| 1.8 | Startup performance (ReadyToRun / tiered JIT) | pkgimages / custom sysimage to minimize JIT latency | 02, 14 | DONE (editor: pkgimage + precompile workload; exports: system image with Godot, packages and compiled scripts, `Godot.Runtime` step ~0.2 s vs ~0.9 s, `docs/perf.md`, ADR 0014; `tests/export`) |

## 2. Generated Engine API

| # | C#/.NET capability | Julia equivalent | Phase | Status |
|---|--------------------|------------------|-------|--------|
| 2.1 | Bindings for every ClassDB class, method, property | Generated from `extension_api.json` | 04 | DONE (1036 classes, 16.8k methods, 4162 properties, 0 skipped; `tests/integration/bindings`) |
| 2.2 | Inheritance hierarchy as C# classes | Abstract type hierarchy + concrete native wrappers | 04, 07 | DONE (hierarchy + `Godot.Native` wrappers; one wrapper per object, ADR 0007; `tests/integration/objects`) |
| 2.3 | Engine singletons as static classes (`Input`, `Engine`, `OS`) | Type-dispatched calls `is_action_pressed(Input, ...)` + `singleton(T)` (ADR 0003) | 04 | DONE |
| 2.4 | Enums, `[Flags]` bitfields, constants | Typed `GodotEnum`/`GodotBitfield` values, prefixed constants (ADR 0003) | 04 | DONE |
| 2.5 | Utility functions on `GD` (`GD.Print`, `GD.Load<T>`, random, etc.) | `Godot.GD` module incl. `GD.load(T, path)` | 04 | DONE |
| 2.6 | Vararg methods (`Call`, `EmitSignal`, `Rpc`) | Julia varargs | 04 | DONE |
| 2.7 | Default arguments | Julia default arguments | 04 | DONE (all Godot defaults translated) |
| 2.8 | XML doc comments from the class reference | Docstrings from the class reference (BBCode → Markdown) | 04 | DONE |
| 2.9 | Editor API in separate assembly (`GodotSharpEditor`) | `GodotEditor` package bound as `Godot.Editor`, loaded only in the editor (ADR 0004) | 04 | DONE (`tests/integration/bindings`: loaded in `--import` editor run, absent in game run) |
| 2.10 | Cached `MethodName`/`PropertyName`/`SignalName` StringNames | Generated constant StringName caches | 04, 09 | DONE (per-call-site method-bind/StringName caches; per-script `SignalName(T)`/`PropertyName(T)`/`MethodName(T)` tables, ADR 0009) |
| 2.11 | Virtual methods (`_Ready`, `_Process`, `_Input`, ...) overridable | `Godot._ready(self::T)` method extensions | 04, 08 | DONE (engine calls dispatch to `Godot._ready(self::T)` etc.; unimplemented callbacks are not reported, so Godot skips them; ADR 0008; `tests/integration/scripts`) |
| 2.12 | GDExtension-registered classes visible in C# | Classes from other extensions reachable (by name / regenerated bindings) | 04 | DONE (by name: wrapped as nearest known ancestor, tested with `JuliaRuntime`; typed: `fetch_api.jl --project=...` + regenerate, generator-tested incl. `editor_extension`) |

## 3. Builtin Types

| # | C#/.NET capability | Julia equivalent | Phase | Status |
|---|--------------------|------------------|-------|--------|
| 3.1 | Managed reimplementation of Vector2/2i/3/3i/4/4i, Rect2/2i, Transform2D/3D, Basis, Quaternion, Plane, AABB, Projection, Color | isbits Julia structs, ABI-compatible, full method parity | 05 | DONE (ADR 0005; every API method golden-tested against Godot, allocation-free; `julia/Godot/test/builtins.jl`) |
| 3.2 | Operators (`+ - * /`, `==`, `IsEqualApprox`) | Julia operator overloads, `isapprox` | 05 | DONE |
| 3.3 | `Mathf` | `Godot.Mathf` | 05 | DONE (engine `CMP_EPSILON` for `EPSILON`, ADR 0005) |
| 3.4 | `Variant` struct with implicit conversions | `Variant` type with `convert`/constructors | 06 | DONE (ADR 0006; `tests/integration/variant`) |
| 3.5 | `string` ↔ Godot String marshalling | `String` ↔ Godot String marshalling | 06 | DONE (UTF-8 ↔ UTF-32 via the interface; String methods generated on `AbstractString`) |
| 3.6 | `StringName`, `NodePath` (implicit from string) | `StringName`, `NodePath` (convert from `String`/`Symbol`) | 06 | DONE (`StringName === Symbol`, ADR 0006) |
| 3.7 | `Godot.Collections.Array`, `Array<T>` | `GDArray`, `GDArray{T}` (typed arrays) as `AbstractVector` | 06 | DONE |
| 3.8 | `Godot.Collections.Dictionary`, `Dictionary<K,V>` | `GDDictionary`, `GDDictionary{K,V}` as `AbstractDict` | 06 | DONE |
| 3.9 | Packed arrays marshalled as `T[]` / `Span` | `Packed*Array` as `AbstractVector` with zero-copy views | 06 | DONE (`Vector{T}` ↔ packed via memcpy; `unsafe_wrap(Array, p)`) |
| 3.10 | `Callable` (incl. `Callable.From(lambda)`) | `Callable` incl. from any Julia function/closure | 06, 10 | DONE (custom callables tied to the captured engine object; released after the last Godot reference; tested) |
| 3.11 | `Signal` struct | `Signal` struct | 10 | DONE (`Signal(obj, :name)` with `connect`/`disconnect`/`is_connected` for Julia functions, `emit`, `get_connections`, `wait(signal)`; tested in `tests/integration/signals`) |
| 3.12 | `Rid` | `RID` | 06 | DONE |
| 3.13 | `[MustBeVariant]` analyzer for generic args | `isvarianttype(T)` trait + macro-time errors | 06, 09 | DONE (`isvarianttype` trait; GDJL0102/GDJL0202/GDJL0301 diagnostics for exports, signal parameters and typed-collection elements) |

## 4. Object Model & Lifetime

| # | C#/.NET capability | Julia equivalent | Phase | Status |
|---|--------------------|------------------|-------|--------|
| 4.1 | `new Node()` constructs engine objects | `Node()` constructs engine objects | 07 | DONE (`classdb_construct_object3` + `NOTIFICATION_POSTINITIALIZE` like godot-cpp's `memnew`, fixed in phase 12 (Controls created from Julia crashed editor docks); `tests/integration/objects`, `tests/integration/editor`, ADR 0007) |
| 4.2 | Stable identity: native object ↔ same managed object | Instance bindings guarantee same Julia object | 07 | DONE (Julia-owned binding token; `==` is identity) |
| 4.3 | Native object with C# script returns the script instance | Same: returns the user's `mutable struct` | 07, 08 | DONE (the script instance's struct is the object's wrapper: `get_node` returns it; `tests/integration/scripts`) |
| 4.4 | `RefCounted` integrated with GC | `RefCounted` integrated with Julia GC/finalizers | 07 | DONE (strong while the engine holds refs, weak otherwise; finalizer-queued release; Julia↔Resource closure chains collected) |
| 4.5 | `Dispose`, `Free`, `QueueFree`, `IsInstanceValid` | `finalize`, `free`, `queue_free`, `is_instance_valid` | 07 | DONE (`FreedObjectError` ≙ `ObjectDisposedException`; `close` not used: clashes with `FileAccess.close`) |
| 4.6 | `GodotObject.WeakRef` | `weakref(obj)` | 07 | DONE |
| 4.7 | Casting: `as`, `is`, `GetNode<T>` | `isa`, `convert`, `as(T, x)`, `get_node(T, self, path)` | 07 | DONE |
| 4.8 | Cross-language: C# → GDScript via `Call`/`Get`/`Set` | `call`, `get`, `set!` (+ `getproperty` fallback) | 07 | DONE (GDScript members via `obj.x`, `Godot.call`, `get`, `set!`, `has_property`) |
| 4.9 | Cross-language: GDScript → C# methods/properties/signals | GDScript calls Julia methods/properties/signals | 08 | DONE (GDScript calls Julia functions, reads/writes fields, connects to `@signal`s; arity/type errors are Godot call errors; `tests/integration/scripts`) |
| 4.10 | Thread safety; Godot threads & `Task.Run` | Julia threads + `WorkerThreadPool`; thread adoption | 02, 07, 10 | DONE (foreign-thread adoption through guarded callback trampolines, GC-safe blocking engine calls, `WorkerThreadPool.add_task`/`add_group_task` with Julia closures, `Threads.@spawn` + `post`; tested; ADR 0007, ADR 0010) |

## 5. Scripting

| # | C#/.NET capability | Julia equivalent | Phase | Status |
|---|--------------------|------------------|-------|--------|
| 5.1 | `CSharpLanguage` (ScriptLanguage) | `JuliaLanguage` (`ScriptLanguageExtension`) | 08 | DONE (all virtuals implemented, forwarding to `Godot.Runtime` over ABI v4, ADR 0008; reload hooks in phase 11, external-editor and path-validation hooks in phase 12, debugger hooks are stubs owned by phase 13; `tests/integration/scripts`, `tests/integration/reload`, `tests/integration/editor`) |
| 5.2 | `CSharpScript` resources, `.cs` loader/saver | `JuliaScript` resources, `.jl` loader/saver | 08 | DONE (one generation module per load; script-to-script inheritance; `tests/integration/scripts`) |
| 5.3 | Script instance with method/property/signal reflection | `GDExtensionScriptInstanceInfo3` implementation | 08 | DONE (full callback table in `runtime/instances.jl`; property/method lists, notifications, call errors; `tests/integration/scripts`) |
| 5.4 | Placeholder instances for non-tool scripts in editor | Placeholder instances | 08, 12 | DONE (placeholders with exported defaults, editable values, no Julia instance; checked in the headless editor test) |
| 5.5 | `partial class` + `[ScriptPath]` (generated) | `@godot_class` (file ↔ class binding) | 09 | DONE (one class named after the file, GDJL0003/GDJL0004; ADR 0008/0009; `tests/integration/scripts`) |
| 5.6 | `[Export]` with every `PropertyHint` | `@export` + hint macros | 09 | DONE (`@export_range/enum/flags/flags_2d_*/flags_3d_*/flags_avoidance/file/dir/global_file/global_dir/save_file/multiline/placeholder/exp_easing/color_no_alpha/node_path/storage/custom`; ADR 0009; unit + `tests/integration/scripts`) |
| 5.7 | `[ExportGroup]`, `[ExportSubgroup]`, `[ExportCategory]` | `@export_group`, `@export_subgroup`, `@export_category` | 09 | DONE (`tests/integration/scripts`) |
| 5.8 | `[ExportToolButton]` | `@export_tool_button` | 09 | DONE (virtual `Callable` property running a script function; requires `@tool`, GDJL0108; `tests/integration/scripts`) |
| 5.9 | Export Node/Resource types, typed collections, enums, flags | Same | 09 | DONE (Node/Resource/global-class hints, `GDArray{T}`/`GDDictionary{K,V}`/`Vector{T}` element hints, Julia `@enum` and Godot enums/bitfields; `.tscn` NodePath resolution; `tests/integration/scripts`) |
| 5.10 | Property default values for inspector revert | Generated default-value table | 09 | DONE (field initializers via `_get_property_default_value`; `tests/integration/scripts`) |
| 5.11 | `[Signal]` delegates → events + `EmitSignal<Name>` | `@signal` → typed `emit_<name>` + connect helpers | 09, 10 | DONE (typed `emit_<name>`/`connect_<name>` + `SignalName(T)`; awaiting script signals with `to_signal`/`wait(Signal)`; tested) |
| 5.12 | `[Tool]` | `@tool` | 09 | DONE (`is_tool`, instances in the editor only for tool scripts; `tests/integration/scripts`) |
| 5.13 | `[GlobalClass]`, `[Icon]` | `@global_class`, `@icon` | 09 | DONE (parse-only `_get_global_class_name`; class appears in `ProjectSettings.get_global_class_list()` with its icon; every script can name a Julia global class as a type (bound on load, like C# project-wide visibility); `tests/integration/scripts`) |
| 5.14 | Abstract global classes | `@global_class` on abstract scripts | 09 | DONE (`abstract` option, `is_abstract` in the global class list; `tests/integration/scripts`) |
| 5.15 | `[Rpc]` + `Rpc`/`RpcId` | `@rpc` + `rpc`/`rpc_id` | 09 | DONE (`_get_rpc_config` from `@rpc`, C# defaults; `rpc(node, :f, ...)` round trip; `tests/integration/scripts`) |
| 5.16 | Static methods visible to the engine | Script static methods | 09 | DONE (`f(::Type{T}, ...)`; `_has_static_method`, `METHOD_FLAG_STATIC`; engine calls via `script.call_static("f", ...)` because GDExtension scripts cannot intercept `Script.f()`, ADR 0009; `tests/integration/scripts`) |
| 5.17 | Custom `Resource` subclasses usable in inspector | Same | 09 | DONE (`@global_class` Resource script loaded from `.tres` and exported with `RESOURCE_TYPE` hint; `tests/integration/scripts`) |
| 5.18 | `_Get`, `_Set`, `_GetPropertyList`, `_ValidateProperty` overrides | Same | 08, 09 | DONE (plus `_property_can_revert`/`_property_get_revert`; `tests/integration/scripts`) |
| 5.19 | Source generator diagnostics (GD0001–GD04xx families) | Macro-expansion-time errors with equivalent codes/messages | 09 | DONE (`GDJLnnnn` codes mapped to `GDnnnn` in `docs/diagnostics.md`; every code unit-tested) |

## 6. Signals & Async

| # | C#/.NET capability | Julia equivalent | Phase | Status |
|---|--------------------|------------------|-------|--------|
| 6.1 | `Connect(signal, Callable.From(...))`, flags | `connect(obj, :sig, f; flags)` | 10 | DONE (closures, callable structs and `Callable`s, flags incl. `CONNECT_ONE_SHOT`; returns the Callable; tested) |
| 6.2 | C# events for signals (`+=`/`-=`) | `connect!`/`disconnect!` helpers per signal | 10 | DONE (generated `connect_<sig>`/`disconnect_<sig>` for every engine signal and `@signal` script signals; tested with `connect_timeout`) |
| 6.3 | Auto-disconnect when target object is freed | Same | 10 | DONE (Callable object = engine object captured by the closure, C#'s `Delegate.Target`; capture-less rule in ADR 0010; tested) |
| 6.4 | `await ToSignal(obj, name)` returning signal args | `wait(to_signal(obj, :name))` inside Godot-scheduled tasks | 10 | DONE (`wait`/`@await` return the args tuple; freed source cancels the task without leaks; tested) |
| 6.5 | `GodotSynchronizationContext` / `GodotTaskScheduler` (main thread continuations) | Main-thread Julia task scheduler pumped per frame | 10 | DONE (`godot_task`/`@async_godot` sticky main-thread tasks resumed in `_frame`, `post` from any thread, task exceptions reported; tested) |
| 6.6 | `CallDeferred`, `Callable.CallDeferred` | `call_deferred` | 10 | DONE (`call_deferred(obj, :method, ...)` generated, `call_deferred(f, args...)` for Julia functions; tested) |

## 7. Hot Reload

| # | C#/.NET capability | Julia equivalent | Phase | Status |
|---|--------------------|------------------|-------|--------|
| 7.1 | Reload assemblies after build (collectible ALC) | Re-evaluate script modules in fresh generation modules | 11 | DONE (`_reload_scripts`/`_reload_all_scripts`/`_reload_tool_script`/`_reload` + `JuliaRuntime.reload_scripts`; dependent scripts reloaded; old generations retired by deleting their methods, tested with repeated reloads; compiled code is not freed, see ADR 0011) |
| 7.2 | Serialize/restore instance state across reload | Same (fields, exports, signal connections) | 11 | DONE (fields, exports, script enums/structs transferred; removed/retyped fields handled; references from other instances and connected Julia closures re-targeted; tested in `tests/integration/reload`) |
| 7.3 | Tool scripts reload in editor | Same | 11, 12 | DONE (saving a `.jl` in the editor reloads it like GDScript's saver; `@tool` instances migrate in place keeping state; checked in the headless editor test) |
| 7.4 | `dotnet/project/assembly_reload_attempts` | `julia/project/reload_attempts` | 11 | DONE (failed reloads from disk retried per frame up to the setting; tested) |
| 7.5 | Graceful failure (placeholders) when build broken | Same | 11 | DONE (instances suspended with their state, no user code runs, restored by the next successful reload; deviation: not engine `PlaceHolderScriptInstance`s, ADR 0011; tested) |

## 8. Editor Integration

| # | C#/.NET capability | Julia equivalent | Phase | Status |
|---|--------------------|------------------|-------|--------|
| 8.1 | External editors: Visual Studio, VS Code, Rider, ... | VS Code (Julia ext), Emacs, Vim/Neovim, custom command | 12 | DONE (VS Code, VSCodium, Emacs, Vim/Neovim, custom command with `{file}`/`{line}`/`{col}`/`{project}`; VS Code workspace settings recommend the Julia extension; command construction unit-tested per OS, override checked in the editor test) |
| 8.2 | Open script at line/column from editor | Same | 12 | DONE (`_open_in_external_editor` with 1-based line/column; problems and Godot's own navigation route through `edit_script`; unit-tested) |
| 8.3 | Create Script dialog + C# templates | `.jl` templates (built-in + `script_templates/`) | 12 | DONE (Object/Node/Resource/EditorPlugin/EditorScript templates, editor bases as `Godot.Editor.X`, project `script_templates/` placeholders; every template validates, tested) |
| 8.4 | Global classes in Create Node/Resource dialogs with icons | Same | 12 | DONE (`@global_class` scripts in the global class list with base type and `@icon`; `_validate_path` checks class names; tested in the editor) |
| 8.5 | `dotnet/*` project & editor settings | `julia/*` project & editor settings | 12 | DONE (`julia/project/*`, `julia/runtime/*`, `julia/editor/*`, `julia/build/*`; registration tested in the editor) |
| 8.6 | Built-in script editor highlighting (reserved words, delimiters) | Same | 08, 12 | DONE (native `JuliaSyntaxHighlighter`: keywords, control flow, macros, strings incl. multi-line, comments incl. `#= =#`, numbers, calls, engine/user types, editor theme colors; also applied to tabs restored from the last session; tested in the editor) |
| 8.7 | Script validation errors surfaced in editor | Parse/lowering errors via `_validate` | 08, 12 | DONE (`_validate` errors mark the line in the script editor, checked in the headless editor test; unit-tested) |
| 8.8 | Build diagnostics panel with clickable file:line | Same | 12 | DONE ("Julia" dock in the bottom slot with problems list (activate → script at line), streamed log, Clear and Copy Log; tested in the editor) |

## 9. Debugging & Diagnostics

| # | C#/.NET capability | Julia equivalent | Phase | Status |
|---|--------------------|------------------|-------|--------|
| 9.1 | Attach external debugger (VS/Rider/VS Code) | Attach VS Code Julia debugger / Debugger.jl | 13 | PARTIAL (debug REPL server in debug builds (`julia/debugger/port`/`GDJL_DEBUG_PORT`, `wait_for_attach`), `Godot.@breakpoint` sessions with locals, `godot_repl.jl` client and generated VS Code task + launch config, all tested; line breakpoints with stepping in compiled Julia are not possible (Debugger.jl/Infiltrator need a TTY, ADR 0013); VS Code manual checklist in docs/debugging.md not yet run) |
| 9.2 | Unhandled exceptions → Godot error with stack trace | Same, with file:line mapped to `res://` | 13 | DONE (script errors via `print_script_error_with_message` at the innermost `res://` frame, full Julia stack trace with `res://` paths, break on error in the Godot debugger; tested in `debugging` project and unit tests) |
| 9.3 | Script debugger stack frames in Debugger panel | `_debug_get_stack_level_*` | 13 | PARTIAL (all `_debug_*` virtuals implemented: frames, locals, members, globals, expression evaluation, `debug_get_current_stack_info`; Julia frames in `ScriptBacktrace`s tested in engine, handlers unit tested; an interactive session in the editor's Debugger panel is a manual check in docs/debugging.md) |
| 9.4 | `GD.Print`/Console output in Output panel | `println`/`@info` redirected to Output panel | 13, 14 | DONE (stdout/stderr/logging redirected; tested headless in the editor and in exported debug and release games, `tests/export`) |
| 9.5 | Errors from engine calls with source location | Same | 13 | DONE (engine errors raised under Julia calls carry the Julia frames (`res://` file:line) in their script backtrace; `Engine.capture_script_backtraces` includes Julia; tested in `debugging` project) |

## 10. Export & Deployment

| # | C#/.NET capability | Julia equivalent | Phase | Status |
|---|--------------------|------------------|-------|--------|
| 10.1 | Export plugin bundles assemblies + runtime | Export plugin bundles runtime + compiled user code | 14 | DONE (native `JuliaExportPlugin` + `GodotEditor.Tools`: `data_<Package>_<platform>_<arch>/` with runtime, system image or package depot, environment; `.jl` sources replaced by stubs unless `julia/export/include_sources`; ADR 0014; `tests/export` exports and runs games) |
| 10.2 | Windows, Linux, macOS desktop exports | Same | 14, 15 | PARTIAL (Windows x86_64 exported and run in sysimage debug/release and jit; Linux/macOS layouts handled by the host and by `tests/export/run.jl` (macOS `.app` bundles), run by the `ci.yml` export step on ubuntu/macos runners, which has not run yet; macOS signing notes in docs/export.md; exports are made on the target platform) |
| 10.6 | NativeAOT / trimming | `juliac --trim` / PackageCompiler sysimage | 14 | PARTIAL (`sysimage` mode compiles Godot, packages and scripts ahead of time (`--output-o` + bundled lld); `juliac --trim` is not feasible for the eval-based script runtime, ADR 0014) |
| 10.7 | Debug vs Release configurations | Same | 14 | DONE (debug: `-O2 -g1`, `res://` backtraces, debug server/remote debugger; release: `-O3 -g0`; `jit` mode debug-only; both exported and run in `tests/export`) |
| 10.8 | Export feature tags / conditional compilation (`#if GODOT_WINDOWS`) | Feature-tag queries + compile-time constants | 14 | DONE (`Godot.has_feature(:tag)` runtime; `Godot.@feature(:tag)` is a compile-time constant in system-image exports, runtime check elsewhere; unit tests + `tests/export`) |

## 11. Documentation & Samples

| # | C#/.NET capability | Julia equivalent | Phase | Status |
|---|--------------------|------------------|-------|--------|
| 11.1 | Docs: basics, features, API differences, signals, exports, global classes, variant, collections, style guide | Equivalent Julia pages | 16 | DONE (`docs/user/`: one page per C# page plus async, debugging, export, a C# cheat sheet and performance tips; every Julia block runs headlessly via `scripts/doctest_docs.jl`) |
| 11.2 | Official C# demo projects | Julia ports of the same demos | 16 | DONE (`demos/`: Dodge the Creeps, Pong, Squash the Creeps, Multiplayer Pong ported from `godot-demo-projects/mono` via `scripts/port_csharp_demo.jl`, plus a Julia editor-plugin demo; each driven headlessly by `demos/run.jl`) |
