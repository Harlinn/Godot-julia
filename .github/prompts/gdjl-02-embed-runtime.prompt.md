---
name: gdjl-02-embed-runtime
description: "Phase 2: embed libjulia inside the GDExtension (init, shutdown, threads, GC safety, error boundaries, output redirection)."
agent: agent
---
Embed the Julia runtime in the GDExtension host. Follow the [project instructions](../copilot-instructions.md). Behavioral reference: `modules/mono/mono_gd/gd_mono.cpp` (how C# locates, initializes, and tears down .NET via hostfxr) and `glue/GodotSharp/GodotPlugins/Main.cs`.

## Requirements

1. **Locate runtime** in this order: bundled runtime next to the extension library (export builds), project setting `julia/runtime/path`, env `JULIA_BINDIR`, `julia` on `PATH`. Log the resolved path. Fail gracefully (error + language disabled, editor still usable) if not found — mirror how the editor behaves when .NET SDK is missing.
2. **Initialize** at `MODULE_INITIALIZATION_LEVEL_SCENE`:
   - Set `jl_options` before `jl_init_with_image` / `jl_init`: sysimage path (custom sysimage if present), `handle_signals` (disable on platforms where Julia's handlers conflict with Godot's crash handler; document the decision), thread count from `julia/runtime/threads`, optimization level per build type.
   - Set `JULIA_PROJECT`/active project to the game's Julia project (`res://` globalized path) and `JULIA_DEPOT_PATH` (editor: user depot; export: bundled depot).
   - Load the `Godot` package and call `Godot.Runtime.__init_runtime__(get_proc_address, library_ptr, token)` passing GDExtension interface pointers as `Ptr{Cvoid}`.
3. **Shutdown** at deinit: run Julia finalizers that touch Godot objects *before* Godot frees them, then `jl_atexit_hook(0)`. No crash on editor quit or `get_tree().quit()`.
4. **Threads**: provide `JuliaThreadGuard` (C++ RAII) used at every entry from Godot into Julia: `jl_adopt_thread()` for unknown threads, GC-unsafe enter/leave. Provide the Julia-side inverse (`@gcsafe_ccall` macro or helper) for long engine calls. Implement `ScriptLanguageExtension::_thread_enter/_thread_exit` hooks later in phase 08 using this.
5. **Error boundary**: a single C++ helper that invokes a Julia function, checks `jl_exception_occurred()`, formats the exception + backtrace (`sprint(showerror, e, bt)`) and calls `push_error`. A Julia-side `@godot_entry` macro wraps every `@cfunction` body in `try/catch` returning a default value.
6. **Output**: redirect Julia `stdout`/`stderr` to Godot `print`/`printerr` (line-buffered, thread-safe), and install a `Logging` logger mapping `@info/@warn/@error` to `print`/`push_warning`/`push_error`.
7. **GC pin table**: `Godot.Runtime.pin(x)::UInt64` / `unpin(id)` / `deref(id)` backed by a lock-protected dictionary — the only way C++ may hold Julia values.

## Tests

- Integration test: headless project evaluates a Julia expression via a debug-only `JuliaRuntime.eval_string` exposed to GDScript and asserts the result.
- Exception thrown in Julia surfaces as a Godot error containing the Julia stack trace; process does not crash.
- Calling into Julia from a `Thread` created in GDScript works.
- Measure and record cold-start time in `docs/perf.md`.

Update parity rows 1.1, 1.8 (partial), 4.10 (partial), 9.4.
