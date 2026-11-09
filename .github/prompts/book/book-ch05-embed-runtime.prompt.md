---
name: book-ch05-embed-runtime
description: "Book chapter 5: the logic behind gdjl-02-embed-runtime — hosting libjulia inside Godot with safe threads, GC, errors and shutdown."
agent: agent
---
Write chapter 5 of the book, `docs/book/05-embed-runtime.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-02-embed-runtime](../gdjl-02-embed-runtime.prompt.md).

## Focus

- **Behavioral reference instead of invention.** Pointing at `gd_mono.cpp` and `GodotPlugins/Main.cs` tells the agent to copy how C# locates, initializes and tears down .NET (search order, graceful failure when the runtime is missing).
- **Encoding invariants as requirements.** No Julia exception may unwind through C frames. Every entry is guarded. C++ holds Julia values only through the pin table. Explain why invariants like these belong in both the project instructions and the phase prompt.
- **Cross-cutting machinery early.** Thread adoption, GC-safe regions, the error boundary and output redirection are built before any feature needs them.
- **Measurement as a deliverable.** "Record cold-start time in `docs/perf.md`."

## Leads to Verify

- ADR 0002: libjulia is loaded at runtime, not linked. This deviates from the "embedded via the C API" wording, and the ADR explains why.
- The prompt says to call `jl_atexit_hook(0)` at shutdown. In practice this suspends adopted engine threads and hangs when Godot joins them, so `_shutdown` runs `Base._atexit` instead. This is a case where the prompt was wrong and the agent had to discover it.
- Julia 1.13 embedding: the exported `jl_gc_{safe,unsafe}_{enter,leave}` live in libjulia-internal and take no ptls argument, and `@ccall gc_safe=true` works.
- On Windows, Julia's `bin/` must be prepended to `PATH` before init, because ccall loads libraries such as libpcre2 by bare name.
- `@cfunction` targets must be defined before the function that uses them.
- Static C++ singletons must not hold `godot::String`, because the destructor runs after Godot teardown.
- Later ABI revision (v4): every Godot→Julia `@cfunction` goes through `Runtime.guarded(:ID, ptr)` and a native trampoline (X-macro `GDJL_CALLBACKS` in `gdjl_abi.h`), because Julia's own cfunction thread adoption left engine threads GC-unsafe and caused GC stalls. Show how a later phase reshaped this phase's design.

## Artifacts to Inspect

`native/src/` (runtime bootstrap, thread guard, ABI header), `julia/Godot/src/runtime/`, `docs/adr/0002-runtime-loading.md`, `docs/perf.md`, `tests/integration/runtime/`.

## Try It Yourself

Ask the Ask agent: "Trace what happens from Godot's SCENE initialization level until `Godot.Runtime.__init_runtime__` returns", and check its answer against the code.

Parity rows: 1.1, 1.8, 4.10, 9.4. Navigation: previous chapter 4, next chapter 6.
