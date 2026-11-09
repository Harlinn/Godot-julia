# 6. The FFI Layer: Generated, Measured, Owned

In chapter 5 we got Julia running inside Godot. Now Julia needs to *call* Godot.

Godot exposes its functionality to extensions through the **GDExtension C interface**. That's a few hundred C functions for creating strings, constructing objects, calling methods and converting values.

Phase 3 builds `Godot.FFI`, the low-level layer that reaches those functions directly from Julia with `ccall`. **FFI** stands for *foreign function interface*. It's the Julia counterpart of GodotSharp's `NativeInterop` folder.

No game developer will ever see this layer. But everything above it does:

- the generated API of phase 4,
- the math types of phase 5,
- Variant and collections in phase 6,
- objects in phase 7.

So the stakes are high. If this layer allocates, everything allocates. If it leaks, everything leaks. If its ownership rules are fuzzy, every later phase inherits the fuzziness.

That's why this phase's prompt is the first one with a *number* in its acceptance criteria.

The ordering is forced, too. It has to come after the runtime, because Julia must be running to call anything. And it has to come before the bindings generator, which emits code that calls into this layer.

## The Prompt

Here's the full prompt, [`.github/prompts/gdjl-03-ffi-layer.prompt.md`](../../.github/prompts/gdjl-03-ffi-layer.prompt.md):

```markdown
---
name: gdjl-03-ffi-layer
description: "Phase 3: low-level Julia FFI over the GDExtension C interface (function table, Variant ABI, method binds, StringName cache)."
agent: agent
---
Build the low-level interop layer in `julia/Godot/src/ffi/` that lets Julia call the GDExtension C interface directly via `ccall` on function pointers. Follow the [project instructions](../copilot-instructions.md). Behavioral reference: `modules/mono/glue/runtime_interop.cpp` and `GodotSharp/Core/NativeInterop/` (`NativeFuncs`, `InteropStructs`, `Marshaling`, `VariantUtils`).

## Requirements

1. **Interface table**: on `__init_runtime__`, resolve every needed function from `gdextension_interface.h` via `get_proc_address` into a `const` struct of `Ptr{Cvoid}` fields populated once (`Ref` filled at init). Wrap each in a typed `@inline` Julia function. Generate this table from the parsed header (`GodotBindgen` helper) rather than writing it by hand.
2. **Build configuration**: read `builtin_class_sizes` / `builtin_class_member_offsets` for the active configuration (`float_32`, `float_64`, `double_32`, `double_64`) and define `const real_t`. Assert at init that Julia struct sizes match.
3. **Opaque builtins**: `isbits` structs of the correct size for `Variant`, `String`, `StringName`, `NodePath`, `Array`, `Dictionary`, `Callable`, `Signal`, `Packed*Array` with constructors/destructors obtained via `variant_get_ptr_constructor`/`_destructor`. Ownership rules documented (who destroys what).
4. **Method calls**: `ptrcall` path (`object_method_bind_ptrcall`) for fixed-arity methods with stack-allocated argument arrays (no heap allocation for isbits args), and `call` path (`object_method_bind_call`) for varargs. Builtin-type methods via `variant_get_ptr_builtin_method`. Utility functions via `variant_get_ptr_utility_function`.
5. **Caches**: method binds by `(class, method, hash)` and `StringName`s created lazily once and kept for process lifetime — equivalent to C#'s static readonly caches. Provide `@sn_str` macro for compile-time-constant StringNames.
6. **Callbacks**: all `@cfunction` entry points (instance binding callbacks, script instance callbacks, custom callable callbacks) are top-level functions taking a userdata pointer — no closures.
7. **Error reporting**: thin wrappers over `print_error_with_message`, `print_warning_with_message`, `print_script_error` that accept Julia `LineNumberNode`/stack frames.

## Tests

- Unit tests (run in-engine via the integration harness) for String/StringName round-trips, Variant construct/destroy with no leaks (check `Performance.OBJECT_COUNT` / memory stats), ptrcall on `OS.get_name()`.
- Benchmark: 1M calls of a trivial ptrcall method report allocations = 0 (`@allocated`).

Update parity row 1.7 (partial).
```

## Anatomy of the Prompt

Let's walk through the elements that matter most.

### "Generate This Table … Rather Than Writing It by Hand"

Requirement 1 contains the most consequential instruction in the whole prompt: *"Generate this table from the parsed header (`GodotBindgen` helper) rather than writing it by hand."*

Consider the alternative. The GDExtension interface has 179 functions in Godot 4.7. An agent could type 179 `ccall` wrappers. It might even get them all right. But the result would be:

- a one-off artifact,
- unreviewable in practice,
- wrong the moment the interface changes.

A **generator** is the opposite. It's a few dozen lines you can read and test, and it produces every wrapper the same way. When Godot adds or deprecates functions, regenerating is one command.

You'll see this theme again and again in the project, and phase 4 takes it to its conclusion: **whenever a machine-readable source exists, have the agent write a generator, not the output.**

Godot 4.7 helps here. Since 4.6 it can dump the interface as JSON (`gdextension_interface.json`). So the prompt's "parsed header" became a parsed JSON file, with no C parsing needed.

### A Behavioral Reference into C#'s Interop Layer

The reference points to `runtime_interop.cpp` and `GodotSharp/Core/NativeInterop/`. It names exactly the C# files that solve the same problem:

- `NativeFuncs` for the function table,
- `InteropStructs` for opaque value layouts,
- `Marshaling` and `VariantUtils` for conversions.

The agent didn't need to port them. What they offer is a map: how a mature binding organizes the problem, and where the sharp edges are.

### A Quantified Performance Requirement

*"Benchmark: 1M calls of a trivial ptrcall method report allocations = 0 (`@allocated`)."*

That's an **acceptance test**, not an aspiration.

Compare it with "make method calls fast". An agent can satisfy that with any implementation and any amount of self-assurance. "Zero bytes over a million calls" is different:

- it's binary,
- it's cheap to measure,
- it's exactly what matters.

Why does it matter so much? In Julia, a single heap allocation per engine call means garbage-collection pauses in every game's frame loop.

Requirement 4 says *how* to get there: *"stack-allocated argument arrays (no heap allocation for isbits args)"*. The benchmark proves it happened.

### "Assert … That Julia Struct Sizes Match"

Requirement 2 asks for a cheap **invariant check**.

Godot's API file lists the size of every builtin type (`Variant`, `String`, `Vector2`, …) for each build configuration: single or double precision, 32 or 64 bits. The Julia structs that mirror them must have exactly those sizes. Otherwise every call that passes one corrupts memory.

A size mismatch is the nasty kind of bug. It makes a program misbehave somewhere completely unrelated, much later. A one-line comparison turns it into an error at startup or in a unit test.

### "Ownership Rules Documented (Who Destroys What)"

Requirement 3 hides a documentation requirement in parentheses. Don't skip past it.

FFI bugs are almost always **ownership** bugs. A Godot `String` constructed in Julia must be destroyed exactly once:

- destroy it twice and you corrupt the heap,
- never destroy it and you leak.

Arguments passed to a call are borrowed or copied. Returned values are owned by whoever receives them.

Without written rules, each later phase, and each new agent session, would reinvent them slightly differently.

### Caches with a C# Analogy

Requirement 5 asks for caches of method binds and `StringName`s, *"equivalent to C#'s static readonly caches"*.

Looking up a method bind requires a hash and two `StringName`s. Doing that on every call would be slow. C# avoids it with static fields initialized once.

Naming the C# mechanism tells the agent two things at once: *what* to cache, and *for how long* (the process lifetime).

The `@sn_str` macro gives Julia code a compile-time-constant `StringName`, written `sn"name"`.

### Callbacks Without Closures

Requirement 6 restates a project convention: *"top-level functions taking a userdata pointer — no closures."*

Julia can create C callbacks from closures on some platforms, but not all. The instructions forbid them everywhere. That way, code written today won't break on an architecture tested tomorrow.

Why repeat a rule that's already in the instructions? Because this is the phase that first creates callbacks. Repeating the rule here puts it right where the agent is looking.

### Tests That Name Their Instruments

The test section names concrete probes:

- string round-trips,
- construct/destroy with "no leaks", checked with *"`Performance.OBJECT_COUNT` / memory stats"*,
- a ptrcall to `OS.get_name()`.

It doesn't say "test the FFI". It says what to measure, and with which engine statistic. **Specific instruments produce specific tests.**

## What the Agent Built

### The Generated Interface Table

[`julia/GodotBindgen/src/interface.jl`](../../julia/GodotBindgen/src/interface.jl) reads `gdextension_interface.json` and writes `julia/Godot/src/generated/interface.jl`.

That output file is about 2,750 lines. It holds all 147 C types and an `@inline` wrapper for each of the 179 interface functions.

The table itself is generated as a struct with one pointer field per function. It's resolved in one loop at startup:

```julia
function emit_table(io::IO, functions)
    println(io, "\"Function pointers resolved from `get_proc_address` (one field per GDExtension interface function).\"")
    println(io, "struct InterfaceTable")
    for f in functions
        println(io, "    $(f["name"])::Ptr{Cvoid}")
    end
    println(io, "end\n")
    println(io, "const INTERFACE = Ref{InterfaceTable}()\n")
```

Each wrapper carries the function's documentation from the JSON, including deprecation notes. Hover over `FFI.string_new_with_utf8_chars_and_len2` in an editor and you'll see Godot's own description.

### Build Configuration and Layout

The layout generator in [`julia/GodotBindgen/src/layout.jl`](../../julia/GodotBindgen/src/layout.jl) writes `generated/layout.jl` for one build configuration. It contains:

- the configuration name,
- `real_t`,
- every builtin size and member offset,
- opaque, fixed-size structs for the types Julia only passes around.

```julia
    words(n) = (n % 8 == 0 || error("size $n is not a multiple of 8"); n ÷ 8)
    println(io, "\"Opaque, ABI-sized Variant. Ownership: whoever constructs it must `destroy!` it exactly once.\"")
    println(io, "struct RawVariant\n    _data::NTuple{$(words(sizes["Variant"])), UInt64}\nend\n")
```

The sizes come from the same API file the engine was built from. So the opaque structs are correct **by construction**.

The prompt's "assert at init" became two checks:

- **In the unit tests**, every `Raw*` struct is compared with `BUILTIN_SIZES`.
- **At startup**, [`ffi/init.jl`](../../julia/Godot/src/ffi/init.jl) checks that the *configuration* the bindings were generated for matches the running engine:

```julia
    real_t_size == sizeof(real_t) ||
        error("Godot uses $(8 * real_t_size)-bit real_t but bindings were generated for $BUILD_CONFIGURATION; " *
              "regenerate them with `julia scripts/generate_bindings.jl --precision=$(real_t_size == 8 ? "double" : "single")`")
```

The engine's `real_t` size reaches Julia through the native host. That needed a new field in the shared function table and a bump of the native ABI to v2.

Look closely at the error message. It says exactly which command fixes the problem. Error messages that name the fix are as useful to an agent as they are to you.

### Ownership, Written Down

The rules requirement 3 asked for live in the docstring of the `FFI` module ([`ffi/FFI.jl`](../../julia/Godot/src/ffi/FFI.jl)). Anyone reading the code will find them there:

```julia
Ownership rules:
- A `Raw*`/`RawVariant` value returned by a constructor, `ptrcall`, or conversion is owned by the caller, who must
  `destroy!` it exactly once (types without a destructor make that a no-op).
- Values passed as call arguments are borrowed; the callee copies whatever it keeps.
- Values handed out by caches (`sn"..."`, `string_name_ptr`) are borrowed for the life of the runtime: never destroy them.
```

Three sentences settle every "who frees this?" question in the layer.

### Zero-Allocation Calls

[`ffi/calls.jl`](../../julia/Godot/src/ffi/calls.jl) implements the call paths. The interesting one is `ptrcall`.

It's a Julia `@generated` function. The first time it's called with a given return type and number of arguments, it writes specialized code for that combination.

The trick is spelled out in a comment:

```julia
# Arguments are boxed in `Ref`s whose pointers are gathered in a `Ref{NTuple}`; Julia keeps all of them on the
# stack, so calls with isbits arguments do not allocate.
```

Here's how it works:

- Each argument goes into its own `Ref`.
- The pointers go into a tuple.
- `GC.@preserve` keeps everything alive for the duration of the call.

For plain-value (**isbits**) arguments, Julia's compiler keeps all of this on the stack. Nothing touches the heap.

The same machinery serves builtin-type methods and utility functions.

A separate `ptrcall_gcsafe` variant marks the thread GC-safe during engine calls that may block, such as waiting on a mutex. It came later, when phase 10 brought worker threads.

Varargs methods use the slower `variant_call` path. It throws a typed `GodotCallError` (*"invalid argument (argument 2 should be variant type 4)"*) instead of a bare error code.

### Caches

Method binds are cached by `(class, method, hash)`. The hashes themselves are generated into a table from the API file, so callers rarely need to know them.

`StringName`s live in a dictionary of boxed values whose addresses stay stable. On top of that, the `sn"..."` macro adds a per-call-site cache ([`ffi/strings.jl`](../../julia/Godot/src/ffi/strings.jl)):

```julia
macro sn_str(s)
    cache = Ref{Ptr{RawStringName}}(C_NULL)
    name = QuoteNode(Symbol(s))
    return quote
        p = $cache[]
        if p == C_NULL
            p = $string_name_ptr($name)
            $cache[] = p
        end
        unsafe_load(p)
    end
end
```

The `Ref` is created when the macro *expands*, so each call site gets its own slot. After the first call, `sn"position"` costs one pointer load.

### Tests at Two Levels

The phase has two kinds of test. The split is worth copying.

**Unit tests without an engine** ([`julia/Godot/test/ffi.jl`](../../julia/Godot/test/ffi.jl)) replace Godot's function table with *fake native functions*, written as Julia `@cfunction`s. They check the argument layout and the allocation count in a plain Julia process:

```julia
            FFI.INTERFACE[] = fake_interface(;
                object_method_bind_ptrcall = @cfunction(fake_method_ptrcall, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Ptr{Cvoid})))
            @test FFI.ptrcall(Int64, C_NULL, Ptr{Cvoid}(5), Int64(10), 2.4, true) == 10 + 2 + 1 + 5
            ptrcall_loop(10)
            @test (@allocated ptrcall_loop(1_000_000)) == 0
```

These run in seconds, with no Godot binary. Swapping in a fake was easy because the generated table is a plain struct. At the end of phase 3, the `Godot` package had 100 unit tests, all passing.

**In-engine tests** ([`tests/integration/ffi/test_ffi.jl`](../../tests/integration/ffi/test_ffi.jl), tagged `# parity: 1.7`) run inside headless Godot. They cover:

- string round-trips with Unicode, empty and 10,000-character strings,
- `StringName` and `NodePath`,
- Variant conversions,
- a leak check that compares Godot's static memory usage before and after 100,000 create/destroy cycles,
- real ptrcalls to `OS.get_name`, `OS.has_feature` and `OS.get_processor_count`,
- a builtin method (`String.length`),
- a utility function (`sin`),
- the Variant call path, including its error case,
- the benchmark itself:

```julia
    @testset "zero-allocation ptrcall benchmark" begin
        mb = FFI.method_bind(:Time, :get_ticks_usec)
        time = FFI.singleton(:Time)
        ticks_loop(mb, time, 10)
        allocated = @allocated ticks_loop(mb, time, 1_000_000)
        elapsed = @elapsed ticks_loop(mb, time, 1_000_000)
        println("ptrcall Time.get_ticks_usec: ", round(elapsed * 1000; digits = 1), " ns/call over 1M calls, ", allocated, " bytes allocated")
        @test allocated == 0
    end
```

The first recorded result, in [`docs/perf.md`](../perf.md): **43.5 ns per call, 0 bytes allocated over 1M calls**.

Phase 15's benchmark suite still tracks the equivalent path: an engine method call through the cached method bind, with a baseline of 37 ns.

## Where Reality Pushed Back

### A Shutdown Crash in Static C++ Objects

The phase 3 report lists this under *Fixed along the way*:

> **Exit crash in our code:** the static `JuliaHost` object held Godot `String`s whose destructors could run after Godot shut down. They are now plain `std::string`s.

Here's what was going on. C++ destroys static objects after `main` returns. That's after Godot has torn down its memory system. A `godot::String` destructor running at that point touches freed memory.

The rule went into the agent's memory notes in one line: *"Static C++ singletons must not hold godot::String"*. You can see its effect throughout [`julia_host.cpp`](../../native/src/julia_host.cpp): names like `home_utf8`, `version_utf8` and `bindir_utf8` are `std::string` members.

The Julia side follows the same discipline. Its caches hold Godot `StringName`s, so `FFI.shutdown!()` destroys them explicitly. Its docstring says *"must run while Godot is still alive"*, and the runtime's `_shutdown` calls it before Godot tears down.

### Godot's Own Exit Crash

The same report found a crash that was *not* in our code. A headless editor crashes at exit the first time it discovers a `.gdextension`.

The agent handled it well:

- It checked whether its own code was responsible, by reproducing the crash with Julia disabled.
- It found the upstream issues ([#111048](https://github.com/godotengine/godot/issues/111048), [#123511](https://github.com/godotengine/godot/issues/123511)).
- It worked around them in `scripts/prepare_test_projects.jl` (chapter 4).

That's a habit worth stealing, whether you're an agent or not. **Rule out your own code before blaming the platform**, then link the upstream issue in the workaround's comment.

### The Cost of a Bigger Package

Speed came at a price: startup.

The report noted honestly that the `Godot.Runtime` step of startup grew from about 0.3 s to about 0.7 s, *"mainly from loading the larger package"*. It also named the planned fix: a preloaded system image in phase 14.

Phase 14 delivered it. In exported games that step now takes about 0.21 s. The editor still pays roughly 0.9 s (chapter 5).

Report a regression together with its planned owner. That beats both hiding it and fixing it out of order.

### Row 1.7 Could Only Be Partial

The phase owns one row: single and double precision builds.

It made the bindings configuration-aware and checks the precision at startup. But a double-precision Godot build and the math types (phase 5) didn't exist yet.

So the agent moved row 1.7 from `TODO` to `PARTIAL`, as the prompt anticipated with *"(partial)"*.

It's still `PARTIAL` today. The native host builds in double precision, but the CI job that builds a double-precision editor and runs the whole suite hasn't run, because the repository isn't published yet.

## Closing the Loop

Three **oracles** cover this layer:

```powershell
julia --project=julia/Godot -e "using Pkg; Pkg.test()"   # includes the engine-free FFI tests
julia tests/integration/run.jl ffi                         # in-engine FFI tests and the 1M-call benchmark
julia tests/benchmarks/run.jl                              # regression benchmarks against stored baselines (phase 15)
```

Each one catches a different class of problem:

- **The fake-interface unit tests** catch layout and allocation regressions in seconds, before any Godot run.
- **The in-engine tests** catch everything that needs the real engine: ownership mistakes (through the leak check), wrong hashes and Unicode handling.
- **The benchmark suite** catches slow drift that no single test would notice. It fails a result that's more than three times slower than its baseline, because shared CI machines are noisy.

## Techniques to Reuse

- **Generate from the machine-readable source.** If a JSON, header or schema describes an interface, have the agent write and test a generator rather than the output.
- **Put a number in the acceptance criteria.** "0 bytes over 1M calls" is a test the agent can run; "fast" is an opinion.
- **Write ownership rules where the code lives.** Three sentences in the module docstring end every "who frees this?" question.
- **Make the boundary swappable for tests.** A function table held in a plain struct can be replaced by fakes, so most FFI tests run without the real engine.
- **Write error messages that name the fix.** When a check fails, say which command resolves it.
- **Rule out your own code before blaming the platform**, then link the upstream issue in the workaround.

## Try It Yourself

1. Ask the agent to add a benchmark for another engine method (for example `OS.get_processor_count`) to `tests/integration/ffi/test_ffi.jl`, asserting zero allocations. Then ask it to introduce a type instability on purpose, for example by reading the method bind from a non-`const` global variable. Watch the allocation test catch it.
2. Open the **Ask** agent and ask: *"According to the FFI module's ownership rules, who must destroy the value returned by `os_call(FFI.RawString, :get_name)`, and where in `test_ffi.jl` does that happen?"*
3. Run `julia scripts/generate_bindings.jl --precision=double`. Then start a single-precision Godot with a test project and read the startup error. Afterwards, regenerate with the default precision.

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 1.7 | Single and double precision (`real_t`) builds | PARTIAL (bindings and math verified with `real_t = Float64` bindings; native `precision=double` library builds on Windows; the CI job that builds a double-precision Godot editor and runs the suite is defined in `ci.yml` but has not run yet) |

Row 1.7 is co-owned by phases 03, 05 and 15. This phase moved it from `TODO` to `PARTIAL`.

---
[← Previous: Embedding the Runtime](05-embed-runtime.md) · [Contents](README.md) · [Next: The Bindings Generator →](07-bindings-generator.md)
