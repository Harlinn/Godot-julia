---
name: gdjl-05-builtin-math
description: "Phase 5: hand-written Julia builtin math types (Vector*, Transform*, Basis, Quaternion, Color, ...) and Mathf, ported from GodotSharp."
argument-hint: "Optional: subset of types to implement first"
agent: agent
---
Implement Godot's builtin value types natively in Julia in `julia/Godot/src/builtins/`, as C# does in `GodotSharp/Core/*.cs`. Scope: `${input:types:all types}`. Follow the [project instructions](../copilot-instructions.md).

## Types

`Vector2`, `Vector2i`, `Vector3`, `Vector3i`, `Vector4`, `Vector4i`, `Rect2`, `Rect2i`, `Transform2D`, `Transform3D`, `Basis`, `Quaternion`, `Plane`, `AABB`, `Projection`, `Color`, and `Mathf`.

## Requirements

1. **ABI**: `isbits` immutable structs whose layout equals Godot's for the active `real_t` (verify against `builtin_class_member_offsets`). Passed to/from engine by pointer with zero conversion.
2. **API parity**: port every public member of the corresponding C# file (e.g. `Vector2.cs`: `Angle`, `AngleTo`, `Bounce`, `Clamp`, `Cross`, `DirectionTo`, `Lerp`, `Slerp`, `MoveToward`, `Normalized`, `Rotated`, `Snapped`, `IsEqualApprox`, constants `Zero`, `One`, `Up`, ...). Use Godot's snake_case names (`angle_to`, `move_toward`). Port `Color` named colors and `Color.from_html` etc. Add an attribution comment per file referencing the C# source.
3. **Julia idioms**: field access (`v.x`), operators (`+ - * /`, unary `-`, scalar ops, `*` for transform composition and transform×vector), `==`, `isapprox` (Godot epsilon semantics), `hash`, `show`, `zero`, `one` where meaningful, conversions between int/float variants, `getindex` by axis. No `StaticArrays` dependency; no heap allocation.
4. **Swizzle-free**: C# has no swizzling; do not add it (keep parity, avoid scope creep).
5. **Precision**: everything parametric on the global `real_t`, not on a type parameter, so user code writes `Vector2(1, 2)`.
6. **Mathf**: `Godot.Mathf` module porting `Mathf.cs`/`MathfEx.cs` (`lerp`, `inverse_lerp`, `remap`, `wrap`, `pingpong`, `snapped`, `move_toward`, `smoothstep`, `deg_to_rad`, `is_equal_approx`, `TAU`, `EPSILON`, ...). Where Julia `Base` already has an equivalent (`clamp`, `sign`), reuse it.

## Tests

- Golden tests: for each method, compare Julia results against values produced by running the same operations in Godot (generate a fixture with a GDScript or C# tool script, check it into `julia/Godot/test/fixtures/`).
- Allocation tests: all operations `@allocated == 0`.
- Round-trip through the engine (set `Node2D.transform`, read back) in integration tests, for both single and double precision builds in CI.

Update parity rows 3.1–3.3 and 1.7.
