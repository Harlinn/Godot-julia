---
name: book-ch17-export
description: "Book chapter 17: the logic behind gdjl-14-export — shipping games with Julia: sysimage, trimmed and JIT modes, runtime bundling, platforms."
agent: agent
---
Write chapter 17 of the book, `docs/book/17-export.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-14-export](../gdjl-14-export.prompt.md).

## Focus

- **Analogies that carry requirements.** `sysimage` ≈ ReadyToRun, `trimmed` ≈ NativeAOT, the `data_*` folder like C#. Explain how naming the C# analog transfers expectations (startup time, size, restrictions) to the agent.
- **Feasibility left open, honesty required.** `juliac --trim` was requested, but the matrix (row 10.6) and ADR 0014 record why it is not feasible for an eval-based script runtime. Show how to write prompts that welcome a justified "no".
- **Platform scope fences.** "Android, iOS and Web are out of scope." `${input:platforms:…}` focuses a session.
- **Long-running steps.** Exports that take minutes change how an agent must run and monitor commands (asynchronous runs, logs, timeouts).

## Leads to Verify

- `julia tests/export/run.jl [sysimage-debug|sysimage-release|jit-debug]`. It needs template DLLs plus the export templates archive, which is extracted with `p7zip_jll` because the system `tar` fails on drive-letter paths.
- Sysimage export takes ~7 min (generic CPU target) / ~11 min (multi-versioned). `GDJL_EXPORT_CPU_TARGET=generic` speeds up iteration. Verify the figures in `docs/perf.md`/`docs/export.md`.
- `Base.Linking.link_image(obj, dll)` links `--output-o` objects without PackageCompiler or gcc.
- The runtime copy must skip stdlib `test/` folders (Windows MAX_PATH).
- Scripts evaluated at runtime need `invokelatest` for their constructors and methods (world age). This is a Julia-specific concept to explain briefly.
- Startup numbers (the `Godot.Runtime` step at ~0.2 s vs ~0.9 s) from matrix row 1.8.

## Artifacts to Inspect

The export plugin in `julia/GodotEditor/src/`, the host's runtime location logic in `native/src/`, `docs/adr/0014-export.md`, `docs/export.md`, `docs/user/julia_export.md`, `docs/perf.md`, `tests/export/`.

## Try It Yourself

Ask the Plan agent to design a Linux export verification job using `tests/export/run.jl`, then compare its plan with the export step in `.github/workflows/ci.yml`.

Parity rows: 1.3, 1.8, 10.1, 10.2, 10.6–10.8. Navigation: previous chapter 16, next chapter 18.
