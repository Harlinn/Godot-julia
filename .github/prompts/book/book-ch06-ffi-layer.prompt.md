---
name: book-ch06-ffi-layer
description: "Book chapter 6: the logic behind gdjl-03-ffi-layer — a generated, allocation-free Julia FFI over the GDExtension C interface."
agent: agent
---
Write chapter 6 of the book, `docs/book/06-ffi-layer.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-03-ffi-layer](../gdjl-03-ffi-layer.prompt.md).

## Focus

- **"Generate this table from the parsed header rather than writing it by hand."** Steer the agent toward generators wherever a machine-readable source exists, because generators are reviewable, repeatable and correct at scale.
- **Quantified performance requirements.** "1M ptrcalls, `@allocated == 0`" is a test the agent can run, unlike "make it fast".
- **ABI correctness checks.** Assert at init that Julia struct sizes match `builtin_class_sizes` for the active build configuration. Cheap invariant checks catch whole classes of silent memory corruption.
- **Ownership rules written down** (who destroys what). FFI bugs are ownership bugs.
- **Constraints from the instructions applied here.** No `@cfunction` closures, caches equivalent to C#'s static readonly fields, `@sn_str` for constant `StringName`s.

## Leads to Verify

- How `real_t` and the build configuration (`float_32`, `float_64`, `double_32`, `double_64`) are chosen and asserted.
- Where method binds and `StringName`s are cached (per call site vs global), and how that relates to matrix row 2.10.
- The zero-allocation benchmark and where it lives (`tests/benchmarks/`, `tests/integration/ffi/`).

## Artifacts to Inspect

`julia/Godot/src/ffi/`, the interface-table generator in `julia/GodotBindgen/`, `julia/Godot/src/generated/interface.jl` and `layout.jl` (generated, gitignored; describe how they are produced), `tests/integration/ffi/`, `tests/benchmarks/`.

## Try It Yourself

Ask the agent to add a benchmark for another engine call and assert zero allocations, then deliberately introduce a boxing bug and watch the test catch it.

Parity rows: 1.7. Navigation: previous chapter 5, next chapter 7.
