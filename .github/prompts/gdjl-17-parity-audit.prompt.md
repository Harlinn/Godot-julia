---
name: gdjl-17-parity-audit
description: "Phase 17: audit Julia support against current Godot C#/.NET capabilities, refresh the parity matrix, and fix or document every gap."
argument-hint: "Optional: Godot tag to audit against (defaults to GODOT_VERSION)"
agent: agent
---
Audit GodotJL against Godot's current C#/.NET support. Godot tag: `${input:godotTag:value in GODOT_VERSION}`. Follow the [project instructions](../copilot-instructions.md).

## Steps

1. **Refresh the spec**: fetch, at the given tag, `modules/mono/` (C++ and `glue/GodotSharp`, `editor/GodotTools`, `editor/Godot.NET.Sdk`), the godot-docs C# pages, and the Godot release notes / changelog entries tagged C#/.NET since the previously audited version. List every user-visible C# capability (attributes, generator outputs, analyzer diagnostics, project/editor settings, editor UI, export options, supported platforms, builtin type members).
2. **Diff the matrix**: add rows to the [parity matrix](../../docs/csharp-parity-matrix.md) for any capability not yet listed; assign each to the owning phase prompt.
3. **Verify each row** by inspecting code and running the tests that reference it (`scripts/check_parity_tests.jl`). Downgrade statuses that are not backed by passing tests.
4. **API surface diff**: write `scripts/api_diff.jl` that compares GodotSharp's public members (builtin types, `GD`, `Mathf`, `GodotObject` helpers, collections) against the Julia `Godot` package names (accounting for documented naming rules) and outputs missing members. Fix trivial gaps directly; list the rest.
5. **Fix or justify**: for each gap, either implement it (following the owning phase prompt's requirements) or mark `GAP` with an ADR in `docs/adr/` explaining why (e.g. GDExtension limitation, Julia platform support) and the workaround.
6. **Report**: summarize in the chat: counts by status, new rows, fixes made, remaining `GAP`s with ADR links. Update `GODOT_VERSION` if auditing a newer tag and regenerate bindings.

## Done when

No row is `TODO`/`PARTIAL` without an assigned owner and plan, and every `GAP` links an ADR.
