# Performance Log

Measurements from the `GodotJL: Julia ...` startup line. Record each measurement with its date, machine, and versions.

## Cold start (native host → `Godot.Runtime` ready)

Machine: Windows x86_64 dev box. Godot 4.7.2-stable editor binary run with `--headless`. Julia 1.13.3 (juliaup). `Godot` package already precompiled. `editor` build of the extension. Default settings (1 thread, `-O2`).

| Date | Runtime source | locate | jl_init | `using Godot` + `__init_runtime__` | Total |
|------|----------------|-------:|--------:|-----------------------------------:|------:|
| 2026-11-02 | `julia` on PATH | ~400 ms | ~230 ms | ~300 ms | ~930 ms |
| 2026-11-02 | `JULIA_BINDIR` | 10 ms | ~225 ms | ~285 ms | ~520 ms |

Notes:

- The `PATH` fallback spawns `julia` to read `Sys.BINDIR`, which costs about 0.4 s. With juliaup the `julia` on `PATH` is a launcher, so its directory is not the real install. Set `julia/runtime/path` or `JULIA_BINDIR` to skip this step. Exported games use the bundled runtime (phase 14).
- `jl_init` loads the stock system image. Most of the remaining time is loading the `Godot` package image. A custom system image (phase 14) should remove most of it.
- Targets: under 600 ms in the editor (still open, ~0.9 s for `Godot.Runtime`). Exported games are measured in the export section below (0.70 s warm).

## Exported games (phase 14, ADR 0014)

Machine: Windows x86_64 dev box. Godot 4.7.2-stable official templates. Julia 1.13.3. `tests/export/game`, run with `--headless` through the console wrapper. Numbers come from `julia tests/export/run.jl` and from repeated runs of the exported game. "First run" is the first start after export, when Windows loads the freshly written runtime DLLs for the first time. "Warm" is the median of later runs. The system image uses the default multi-versioned x86_64 CPU target.

| Date | Mode | Export time | Payload (`data_*`) | System image | Julia startup, first run | Julia startup, warm (jl_init / `Godot.Runtime`) |
|------|------|------------:|-------------------:|-------------:|-------------------------:|------------------------------------------------:|
| 2026-11-05 | sysimage, debug | 672 s | 787 MiB | 393 MiB | 1.9–5.1 s | **0.70 s** (0.47 s / 0.21 s) |
| 2026-11-05 | sysimage, release | 612 s | 723 MiB | 329 MiB | 1.8–3.0 s | **0.70 s** (0.47 s / 0.21 s) |
| 2026-11-05 | jit, debug | 115 s | 796 MiB | — (stock image + pkgimages) | 1.9 s | 1.2 s (0.28 s / 0.91 s) |
| reference | editor run (pkgimages) | — | — | — | — | ~1.5 s (0.23 s / 0.87 s) |

Notes:

- The system image cuts the `Godot.Runtime` step (loading Godot, `__init_runtime__`, script loads) from about 0.9 s to 0.21 s. Scripts compiled into the image load without parsing.
- `jl_init` maps the system image (330–390 MiB) and makes up most of the remaining warm startup. With `GDJL_EXPORT_CPU_TARGET=generic` the image is about 320 MiB and builds in about 6.5 minutes instead of about 11.
- About 400 MiB of the payload is the Julia runtime libraries, kept so the JIT stays available: libjulia-codegen (122 MiB), LLVM (100 MiB), OpenBLAS (38 MiB), and libstdc++ (twice, 25 MiB each).
- Targets: warm Julia startup under 1 s for sysimage exports (met: 0.70 s), and under 300 ms for `Godot.Runtime` (met: 0.21 s). Payload under 1 GiB (met), with a follow-up to drop unused runtime libraries such as OpenBLAS and the duplicate libstdc++ once the dependency set is known.

## Benchmarks (phase 15)

`julia tests/benchmarks/run.jl` runs `tests/benchmarks/project` headlessly (editor binary, `editor` build of the extension, 1 Julia thread, `-O2`). Each benchmark is the best of 5 runs, reported in ns per operation, and is compared with `tests/benchmarks/baseline.toml`. A result fails when it is slower than 3× the baseline (`GDJL_BENCH_TOLERANCE`), because shared CI machines are noisy. `--update` rewrites the baselines.

| Benchmark | What is timed | 2026-11-05 baseline |
|-----------|---------------|--------------------:|
| `engine_call` | Julia → engine method (`get_child_count`) through the cached method bind | 37 ns |
| `property_get` | `node.position.x` on a `Node2D` (property getter + builtin struct) | 36 ns |
| `variant_round_trip` | `Vector2` → `Variant` → `Vector2` | 38 ns |
| `signal_emit_to_julia` | `emit_signal` of a user signal connected to a Julia closure | 734 ns |
| `engine_to_julia_script_call` | `Object.call(:noop, i)` on a Julia script instance (engine → bridge → Julia method) | 1101 ns |
| `engine_to_gdscript_call` | same call on a GDScript instance (reference) | 551 ns |
| `julia_process_dispatch` | one `_process` callback of a Julia script (propagated `NOTIFICATION_PROCESS` over 2000 nodes minus plain nodes) | 660 ns |
| `gdscript_process_dispatch` | same for a GDScript `_process` (reference) | 280 ns |

Machine: Windows x86_64, Intel Xeon Platinum 8272CL @ 2.6 GHz. Godot 4.7.2, Julia 1.13.3.

**C# comparison.** No .NET build of Godot is installed here, so C# numbers are not measured. Measure them with the mono editor of the same Godot version: a C# `[GlobalClass]` node with `int Noop(int x)` and `_Process`, timed with the same loops (`Object.Call`, propagated `NOTIFICATION_PROCESS`) from a C# test scene. Then add a column to this table. GDScript serves as the in-process reference. Julia engine → script calls and `_process` dispatch currently cost about 2.3× GDScript, dominated by the bridge round trip and `invokelatest` (ADR 0008).

## Package load (full engine bindings, phase 04)

| Date | Measurement | Value |
|------|-------------|------:|
| 2026-11-04 | Precompile `Godot` (12 MB generated `classes.jl`, 1036 classes) | ~56 s |
| 2026-11-04 | Warm `using Godot` (plain Julia, no engine) | 0.59 s |
| 2026-11-04 | `Godot.Runtime` step of in-engine startup | ~1.4 s (was ~0.7 s before full bindings) |
| 2026-11-04 | After editor split (ADR 0004) + precompile workload: precompile `Godot` | ~71 s |
| 2026-11-04 | Warm `using Godot` | 0.47 s |
| 2026-11-04 | Warm `GodotEditor` load (editor only) | 0.25 s plain Julia; 33 ms in-engine after `Godot` |
| 2026-11-04 | `Godot.Runtime` step of in-engine startup | ~0.76 s |
| 2026-11-04 | After builtin math (phase 05): warm `using Godot` | 0.54–0.67 s |
| 2026-11-04 | `Godot.Runtime` step of in-engine startup | ~0.88 s |
| 2026-11-04 | After Variant/collections (phase 06, +600 generated builtin methods): warm `using Godot` | 0.60 s |
| 2026-11-04 | `Godot.Runtime` step of in-engine startup | ~1.0 s |
| 2026-11-05 | After object model (phase 07, instance bindings): `Godot.Runtime` step of in-engine startup | 0.87–0.97 s |

Phase 14 result: exported games preload a system image; the `Godot.Runtime` step drops to ~0.21 s (see "Exported games").

## Call overhead

| Date | Path | Measurement |
|------|------|-------------|
| 2026-11-02 | `FFI.ptrcall` → `Time.get_ticks_usec` (in engine) | 43.5 ns/call, 0 bytes allocated over 1M calls |
| 2026-11-02 | `FFI.ptrcall` marshaling only (fake target, unit test) | 0 bytes allocated over 1M calls |
| 2026-11-06 | GDScript → Julia script method `noop(self, x::Int)` (in engine, 100k calls) | ~1.2 µs/call (StringName cache + method cache + Variant conversion + `invokelatest`; typed per-method thunks are a later optimization, ADR 0008) |
| 2026-11-06 | GDScript reads a Julia script field (`player.speed`) | ~1.1 µs/get |
| 2026-11-06 | Same, with generated type-stable field access (phase 09, ADR 0009) | ~0.16 µs/get |
| 2026-11-06 | GDScript → Julia method with compiled call thunks (phase 09) | 0.76–1.6 µs/call (noisy; dominated by the engine/bridge round trip and `invokelatest`) |
