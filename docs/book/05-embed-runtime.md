# 5. Embedding the Runtime: Invariants First

Phase 2 puts a second language runtime inside Godot's process. From here on, two worlds share one address space.

- **Godot** is C++ with its own threads, its own memory management and its own crash handler.
- **Julia** has its own garbage collector, its own threads, its own signal handlers and its own exceptions.

Nothing in either world knows about the other unless we tell it.

Most bugs at this boundary don't show up in a quick test. They show up later:

- as a deadlock when a worker thread calls in,
- as a hang at exit,
- as a crash an hour into a session.

So this phase does something unusual for an early milestone. It builds almost no features and a lot of machinery:

- thread adoption,
- garbage-collector safety,
- an error boundary,
- output redirection,
- a pin table.

All of it arrives before any feature needs it.

It has to come right after scaffolding, for two reasons. Phase 3's FFI layer calls Godot *from* Julia, so Julia must already be running. And every callback that later phases add (instance bindings, script instances, custom callables) calls Julia *from* Godot. The rules for entering Julia safely must exist before those callbacks do.

## The Prompt

Here's the full prompt, [`.github/prompts/gdjl-02-embed-runtime.prompt.md`](../../.github/prompts/gdjl-02-embed-runtime.prompt.md):

```markdown
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
```

## Anatomy of the Prompt

### A Behavioral Reference for Hosting, Not for Code

The prompt opens with a pointer: *"Behavioral reference: `modules/mono/mono_gd/gd_mono.cpp` (how C# locates, initializes, and tears down .NET via hostfxr)."*

Nobody wants a line-by-line port of .NET hosting code into Julia. What the prompt wants is the **behavior**:

- the order in which C# searches for a runtime,
- what happens when none is found,
- when initialization and teardown happen.

Requirement 1 makes the most important of these explicit: *"Fail gracefully (error + language disabled, editor still usable) if not found — mirror how the editor behaves when .NET SDK is missing."*

Left to its own devices, an agent would most likely treat a missing runtime as a fatal error. Naming the reference behavior sets a better bar.

### An Ordered Search, Logged

The runtime search goes from most specific to most general:

- bundled next to the extension,
- then a project setting,
- then `JULIA_BINDIR`,
- then `julia` on `PATH`.

Each step has a reason. Exported games ship their own runtime. Projects can pin one. You can override with an environment variable. The `PATH` lookup is the last resort.

*"Log the resolved path"* is a small requirement with a big effect on debugging. When something goes wrong, the first line of output tells you which Julia was used and where it was found.

### Invariants as Requirements

Requirements 4, 5 and 7 aren't features. They're **invariants**: rules that must hold for every future line of code.

- Every entry from Godot into Julia goes through `JuliaThreadGuard`.
- Every `@cfunction` body is wrapped in `@godot_entry`, so no Julia exception unwinds through C++ frames.
- C++ holds Julia values only through the pin table.

The same rules appear in the project instructions under *Conventions*, almost word for word. That repetition is deliberate.

- The instructions are read in every session, so the rules apply to every phase.
- The phase prompt makes them **deliverables**: something the agent must build here, as reusable machinery that later phases can simply call.

An invariant without machinery is a hope. With machinery, it becomes the path of least resistance.

### "Document the Decision"

Requirement 2 contains a judgment call the prompt doesn't make: should Julia install its own signal handlers? They can conflict with Godot's crash handler.

Instead of deciding, the prompt says *"disable on platforms where … conflict …; document the decision."*

You'll see this pattern throughout the prompts. When we didn't know the right answer, we asked the agent to find out and write down what it found.

The decision ended up in [ADR 0002](../adr/0002-runtime-loading.md):

- Signal handling stays **enabled by default**, because Julia's garbage-collector safepoints require it.
- The consequence: *"Julia installs its own fault handlers, which take precedence over Godot's crash handler."*
- You can switch it off with the project setting `julia/runtime/handle_signals`.

### Forward References

*"Implement `ScriptLanguageExtension::_thread_enter/_thread_exit` hooks later in phase 08 using this."*

Here the prompt tells the agent that something it builds now will be used later, and by whom. That keeps the thread guard general, instead of tailored to phase 2's one test.

### Tests That Target the Scary Cases

The four tests aren't just "it starts". They are:

1. a value round-trips (`eval_string` returns the right result);
2. an exception becomes a Godot error *and the process survives*;
3. a GDScript `Thread` can call into Julia;
4. cold-start time is measured and recorded.

Tests 2 and 3 aim at the two failure classes that would otherwise surface much later: exceptions crossing into C++, and foreign threads. Test 4 makes performance a tracked quantity from day one.

### Partial Rows, by Design

*"Update parity rows 1.1, 1.8 (partial), 4.10 (partial), 9.4."*

The prompt itself admits that two rows can only be partly satisfied here:

- **Startup performance (1.8)** needs custom system images from phase 14.
- **Thread safety (4.10)** needs the object model and the scheduler from phases 7 and 10.

When a prompt says up front that a row spans several phases, an honest `PARTIAL` becomes the expected outcome rather than a failure.

## What the Agent Built

### The Native Host

The C++ side lives in [`native/src/julia_host.cpp`](../../native/src/julia_host.cpp).

Its `initialize()` follows requirement 1 literally:

- locate,
- load,
- check the version,
- start,
- bootstrap,
- log one line with the timing breakdown.

If no runtime is found, it reports an error and returns. The script language is still registered (see [`register_types.cpp`](../../native/src/register_types.cpp)). So `.jl` files load as invalid scripts instead of failing, and the editor keeps working.

Following [ADR 0002](../adr/0002-runtime-loading.md), libjulia is **not linked**. The host loads it with `LoadLibraryExW`/`dlopen` and resolves a small table of exported symbols.

Runtime options aren't written into Julia's `jl_options` struct, as the prompt suggested. Instead, they go through Julia's own option parser with a **synthetic command line**:

```cpp
	// Thread count goes through options: on Windows Julia's C getenv does not see variables set at runtime.
	args = {
		"godot-julia",
		"--startup-file=no",
		"--history-file=no",
		"--threads=" + std::to_string(threads),
		"-O" + std::to_string(optimize),
		std::string("--handle-signals=") + (handle_signals ? "yes" : "no"),
	};
```

That deviation is worth noticing.

- Writing to `jl_options` would tie the extension to the struct's memory layout in one Julia version.
- Going through `jl_parse_opts` depends only on documented command-line options. The same binary works with any Julia ≥ 1.12.

The comment also records a Windows detail found along the way. Setting `JULIA_NUM_THREADS` in the environment at runtime has no effect, because Julia's C `getenv` doesn't see variables set after the process started.

The bootstrap step also isolates the game from your global Julia environment, *"like C# projects only see referenced packages"*. In order, it:

- resets `LOAD_PATH`,
- activates the game's own `Project.toml`,
- only then runs `using Godot` and `Godot.Runtime.__init_runtime__(...)`.

### The Thread Guard

The RAII guard is ten lines long. Every call from Godot into Julia uses it:

```cpp
JuliaThreadGuard::JuliaThreadGuard(const JuliaCAPI &p_api) :
		api(p_api) {
	if (!api.jl_get_pgcstack()) {
		api.jl_adopt_thread();
		adopted = true;
	}
	previous_state = api.jl_gc_unsafe_enter();
}

JuliaThreadGuard::~JuliaThreadGuard() {
	api.jl_gc_unsafe_leave(previous_state);
	if (adopted) {
		// Adopted threads start GC-unsafe; park them in the safe state while they run Godot code.
		api.jl_gc_safe_enter();
	}
}
```

Two concepts explain it.

- **Adoption.** A thread Julia has never seen must be *adopted* before it can run Julia code.
- **GC-safe state.** Julia's garbage collector can only run when every Julia-aware thread is *GC-safe*, meaning it promises not to touch Julia objects. A thread executing Julia code is GC-unsafe. A thread busy in Godot code should be GC-safe, or every collection waits for it, forever.

That second point led to one of the first real discoveries of the phase. It's recorded in a comment in `initialize()`:

```cpp
	// From now on the main thread runs Godot code; let Julia's GC proceed without waiting for it.
	main_gc_state = api.jl_gc_safe_enter();
```

Without that line, picture the first time a Godot worker thread triggers a garbage collection. The collector waits for the main thread. The main thread is happily running Godot's frame loop and never reaches a safepoint.

The phase 2 report described it in one sentence: *"Without this, a Godot worker thread triggering Julia's garbage collector would wait forever on the main thread."*

### The Julia Side

The inverse machinery lives in [`julia/Godot/src/runtime/`](../../julia/Godot/src/runtime).

**The error boundary** is in [`entry.jl`](../../julia/Godot/src/runtime/entry.jl):

```julia
macro godot_entry(default, body)
    return quote
        try
            $(esc(body))
        catch err
            report_unhandled(err, catch_backtrace())
            $(esc(default))
        end
    end
end
```

Every function whose address is handed to C++ wraps its body in this macro.

The same file defines `@gcsafe_ccall`, the Julia-side inverse of the thread guard for long native calls. It's a thin wrapper over `@ccall gc_safe=true`.

**The pin table** is in [`pins.jl`](../../julia/Godot/src/runtime/pins.jl). It's a lock-protected dictionary from integer handles to Julia values. The file's first line states its purpose:

```julia
# The only way native code may hold on to Julia values (see project conventions on GC safety).

const PINS = Dict{UInt64, Any}()
const PINS_LOCK = ReentrantLock()
```

Two more pieces complete the picture:

- **output redirection** in `output.jl`,
- the **ABI handshake** in `abi.jl` and `init.jl`.

`__init_runtime__` refuses to start if the C++ and Julia sides disagree about the ABI version or the size of the shared function tables:

```julia
    api = unsafe_load(host)
    api.abi_version == ABI_VERSION || error("native host ABI v$(api.abi_version) does not match Godot.Runtime ABI v$(ABI_VERSION)")
    api.size >= sizeof(HostAPI) || error("native host API table is too small")
```

That check matters. The native ABI was bumped four times over the project, from v1 to today's v5 in [`gdjl_abi.h`](../../native/src/gdjl_abi.h):

- v2 added the `real_t` size in phase 3,
- v3 the script bridge in phase 8,
- v4 the guarded callbacks described below,
- v5 script-error reporting in phase 13.

With the handshake, a stale DLL or stale Julia sources fail at startup with a clear message instead of corrupting memory.

### The Test Project

[`tests/integration/runtime/main.gd`](../../tests/integration/runtime/main.gd) is a GDScript test that drives Julia through the debug-only `JuliaRuntime.eval_string`. It covers all of the prompt's test bullets, plus a few more:

```gdscript
	check(JuliaRuntime.eval_string("error(\"expected test failure\")") == "", "exception returns empty result")
	check(JuliaRuntime.eval_string("1 +") == "", "parse error returns empty result")
	check(JuliaRuntime.eval_string("2 * 21") == "42", "runtime usable after exceptions")

	var first: Array = _run_on_thread()
	check(first[0] != "" and first[0] != "1", "worker thread adopted (threadid=%s)" % first[0])
	check(first[1] == "true", "GC on worker while main thread runs Godot code")
```

Its companion, [`expect_errors.txt`](../../tests/integration/runtime/expect_errors.txt), lists the errors the test *expects* to see:

- `expected test failure`,
- `ParseError`,
- `warning from julia`.

The harness fails on any Godot error that isn't listed there. Expected errors are **declared, not ignored**, so an unexpected one can never hide among them.

### The Performance Log

[`docs/perf.md`](../perf.md) starts with the phase 2 measurement.

With Julia found on `PATH`, startup took about 930 ms:

- about 400 ms to locate,
- 230 ms for `jl_init`,
- 300 ms for `using Godot` plus `__init_runtime__`.

With `JULIA_BINDIR` set, it took about 520 ms. The difference comes from the `PATH` fallback, which spawns a `julia` process just to ask where it lives.

The table has kept growing ever since, as later phases appended their own rows. In the editor, the `Godot.Runtime` step is still around 0.9 s. In exported games with a custom system image (phase 14), it drops to about 0.21 s.

## Where Reality Pushed Back

### Julia Could Not Find Its Own Libraries

The first integration run aborted during Julia's startup.

The phase 2 report explains why. Julia's internals load bundled libraries such as `libpcre2-8` by bare name, and Godot's process couldn't find them. On Windows, the host now prepends Julia's `bin/` folder to the process `PATH` before loading the runtime:

```cpp
	// Julia's ccall loads its bundled DLLs (pcre2, gmp, ...) by bare name via the standard search path.
	String bin = p_home.path_join("bin").replace("/", "\\");
```

This is a typical embedding problem. A standalone `julia.exe` finds its DLLs because they sit next to it. An embedded runtime inherits the host's search path.

No prompt would have anticipated it. The integration test found it in minutes.

### The Headers Lied About a Function Signature

ADR 0002 records a detail that no amount of training data would supply.

- In Julia 1.13, the *exported* `jl_gc_{safe,unsafe}_{enter,leave}` functions live in `libjulia-internal`. They take no `ptls` argument; they act on the calling thread.
- The C *header macros* with the same names do take `ptls`.

The ADR says plainly that this *"was verified empirically."*

When reference material and reality disagree, an agent that can run an experiment beats one that can only read.

### The Prompt Said `jl_atexit_hook`, and It Hung

Requirement 3 asks for `jl_atexit_hook(0)` at shutdown. That's the documented way to shut down an embedded Julia.

It worked in phase 2's tests. There, worker threads entered Julia only through the host's guarded `eval_string`.

Three days later, in phase 10, Godot worker threads started calling Julia callbacks directly, through `WorkerThreadPool` and custom callables. Two bugs surfaced together. Here's the phase 10 report:

> **Garbage-collection stall:** after Godot worker threads called into Julia, the collector stalled. Julia's own callback wrappers left those threads in a state that blocks collection. All callbacks Godot can call from any thread now go through native wrappers that put the thread back in a safe state on return. This required a native ABI bump to v4.
>
> **Hang at exit:** Julia's normal exit routine (`jl_atexit_hook`) suspends those worker threads, so they blocked forever when Godot shut them down. The host no longer calls it. It runs user `atexit` hooks during shutdown and lets the Julia runtime end with the process, as Godot's C# support does with .NET.

The shutdown code now carries the reasoning in a comment, so nobody "fixes" it back:

```cpp
	// jl_atexit_hook is deliberately not called (the runtime ends with the process, as the CLR does for Godot's C#
	// module): it suspends every other Julia thread, including engine threads Julia adopted, and those threads then
	// block forever in Julia's thread-detach hook when Godot joins them. User atexit hooks run in `_shutdown`.
```

The decision is also recorded in two other places:

- [ADR 0010](../adr/0010-signals-async.md),
- the agent's memory notes (*"Never call jl_atexit_hook: it suspends adopted engine threads -> hang when Godot joins them."*).

The fix for the garbage-collection stall reshaped this phase's design.

Phase 2's `JuliaThreadGuard` protected calls that went through the host. But Godot calls many Julia callbacks *directly*:

- custom callables,
- instance bindings,
- script instances.

Julia's own `@cfunction` wrappers adopt an unknown thread, but leave it GC-unsafe afterwards.

The ABI v4 solution in [`gdjl_abi.h`](../../native/src/gdjl_abi.h) uses an **X-macro** that lists every such callback with its signature. For each one, the host generates a **trampoline** that wraps the call in the same `JuliaThreadGuard`:

```cpp
// Julia callbacks that Godot may call directly from any thread (custom Callables, script instances, instance
// bindings). Julia hands them to the host, which returns a trampoline with the same signature that adopts the thread
// and parks it GC-safe afterwards (Julia's @cfunction wrappers would leave a newly adopted thread GC-unsafe and stall
// every later collection). X(id, return type, argument types...); the order defines the ids used by Julia.
#define GDJL_CALLBACKS(X)                                                                \
	X(CALLABLE_CALL, void, void *, const void *const *, int64_t, void *, void *)         \
	X(CALLABLE_FREE, void, void *)                                                       \
```

This story carries three lessons:

1. **A prompt is a hypothesis.** `jl_atexit_hook` is the textbook answer, and it was wrong for this process model.
2. **Bugs in foundations surface when later phases stress them.** Phase 2's tests passed because phase 2 had no worker threads. Write the invariants early anyway, and expect to revisit their implementation.
3. **Generalize the fix into the invariant.** The fix wasn't "patch the one callback that failed". It was "route *every* callback Godot can call through the guard", enforced by a single list in a header.

## Closing the Loop

The runtime project is part of the integration suite:

```powershell
julia tests/integration/run.jl runtime
```

The harness:

- copies the addon in,
- runs Godot headless,
- checks `expect_output.txt` (for example the `Godot-julia: Julia 1.` startup line) and `expect_errors.txt`,
- parses the `GDJL_TEST_RESULT` line.

The test file carries `# parity: 1.1, 4.10, 9.4`, so `scripts/check_parity_tests.jl` ties those rows to it.

Thread behavior gets exercised again, much harder, by two later projects:

- the `objects` project of phase 7, which runs with four Julia threads,
- the `signals` project of phase 10.

The cold-start numbers aren't an automated test, but they are tracked. Every phase that changed startup appended a row to `docs/perf.md`. Phase 15's benchmark suite then turned the most important call paths into regression checks.

## Techniques to Reuse

- **Mirror reference behavior, not reference code.** Point at how an existing system behaves (search order, failure mode, teardown). Ask the agent to reproduce the behavior idiomatically.
- **Make invariants deliverables.** Write the rule in the instructions *and* make the phase build the machinery that enforces it (`JuliaThreadGuard`, `@godot_entry`, the pin table).
- **Ask the agent to decide and document.** Where you don't know the answer, require an investigation and an ADR rather than guessing in the prompt (the ADR habit from chapter 4).
- **Version your ABI and check it at startup.** A handshake with version and size checks turns mismatches into clear error messages instead of memory corruption.
- **Declare expected errors.** Tests that list the errors they expect, and fail on any other, keep error output meaningful.
- **Put the "why" next to surprising code.** A short comment at the `jl_atexit_hook` call site stops a future session from "fixing" a deliberate decision.

## Try It Yourself

1. Open the **Ask** agent and ask: *"Trace what happens from Godot's `SCENE` initialization level until `Godot.Runtime.__init_runtime__` returns."* Check its answer against `register_types.cpp`, `JuliaHost::initialize`, `bootstrap` and `init.jl`. Does it mention the main thread being parked GC-safe?
2. Run `julia tests/integration/run.jl runtime`. Then add a line to `main.gd` that evaluates `error("not expected")`. Watch the harness fail. Fix it by adding the message to `expect_errors.txt`.
3. Ask the **Plan** agent how it would add one more Godot-to-Julia callback (for example a new script-instance callback). A good plan touches `GDJL_CALLBACKS` in `gdjl_abi.h`, mirrors it in `runtime/abi.jl`, bumps `GDJL_ABI_VERSION`, and adds a test.

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 1.1 | Runtime hosted in-process (`libjulia` embedded in the GDExtension) | DONE (runtime loaded dynamically, ADR 0002; `tests/integration/runtime`) |
| 1.8 | Startup performance (pkgimages / custom system image) | DONE (editor: pkgimage and precompile workload; exports: system image, `Godot.Runtime` step ~0.2 s vs ~0.9 s; `docs/perf.md`, ADR 0014) |
| 4.10 | Thread safety; Godot threads and `WorkerThreadPool` | DONE (foreign-thread adoption through guarded callback trampolines, GC-safe blocking engine calls, `WorkerThreadPool` with Julia closures; ADR 0007, ADR 0010) |
| 9.4 | `println`/`@info` redirected to the Output panel | DONE (tested headless in the editor and in exported debug and release games) |

Rows 1.8 and 4.10 were `PARTIAL` when this phase ended, just as the prompt anticipated. Phases 14 and 10 completed them.

---
[← Previous: Scaffolding](04-scaffold.md) · [Contents](README.md) · [Next: The FFI Layer →](06-ffi-layer.md)
