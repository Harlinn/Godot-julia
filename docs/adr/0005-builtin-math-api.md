# ADR 0005: Builtin math types API

- Status: Accepted
- Date: 2026-11-04

## Context

Phase 05 ports GodotSharp's hand-written value types (`Vector2.cs` … `Projection.cs`, `Color.cs`, `Mathf.cs`) to Julia. Their memory layouts are generated from `builtin_class_member_offsets` (one set per `real_t` configuration); the methods are hand-written in `julia/Godot/src/builtins/`. A few C# conventions do not map directly onto Julia.

## Decision

- **Names**: Godot's snake_case method names (`angle_to`, `move_toward`, `get_euler`), taking the value as the first argument. Static constructors take the type: `from_euler(Basis, v)`, `create_perspective(Projection, …)`, `html(Color, "#fff")`. Constants follow ADR 0003: `Vector2_ZERO`, `Basis_IDENTITY`, `Color_ALICE_BLUE` (C#'s `Colors.AliceBlue`), generated from `extension_api.json`. Named colors are built from their 8-bit values, exactly like `Color::hex`.
- **Basis storage**: Godot stores `Basis` as rows, but `basis.x/y/z` are the columns in both GDScript and C#. The generated struct names its fields `row0..row2` and has a tagged rows constructor (`Basis(Internals.ROWS, r0, r1, r2)`); `Basis(x, y, z)` takes the columns and `b.x/b.y/b.z` return columns, as in C#. `b[i, j]` is row `i`, column `j` (1-based); the 9-number constructor and the text form are row-major, matching Godot's `var_to_str` and C#.
- **Base and LinearAlgebra**: operations with an existing Julia meaning extend Base (`+ - * /`, `==`, `<`, `isless`, `abs`, `sign`, `floor`, `ceil`, `round`, `min`, `max`, `clamp`, `length`, `angle`, `exp`, `log`, `merge`, `inv`, `transpose`, `zero`, `one`, `isapprox`, `show`) or LinearAlgebra (`dot`, `cross`, `norm`, `normalize`, `det`), so `using LinearAlgebra` and `using Godot` work together. LinearAlgebra is part of Julia's default system image, so this costs nothing at load time. Vectors are not iterable; `Base.length(v)` is the Euclidean length, consistent with the ADR 0003 rule that a Godot method named like a Base export extends Base.
- **Rounding and tolerances follow the engine**: `round` rounds half away from zero (`Math::round`), and `is_equal_approx` / `Mathf.EPSILON` use the engine's `CMP_EPSILON = 1e-5`. C#'s `Mathf.Epsilon` is `1e-6`; we follow the engine so Julia agrees with GDScript and with engine-side results (verified by golden tests). `isapprox(a, b)` without keywords means `is_equal_approx`; with `atol`/`rtol` it applies Julia's `isapprox` per component.
- **Indexing**: `v[i]` is 1-based (Julia convention); `v[Vector2_AXIS_X]` indexes by the Godot axis enum. C#'s 0-based indexers are not mirrored.
- **Optional results**: methods that GDScript returns as `Variant` (null on failure), such as `Plane.intersect_3` and `AABB.intersects_ray`, return `Union{Nothing, Vector3}`.
- **Computed properties**: C#/GDScript properties without storage are available through `getproperty`: `Rect2/AABB.end_` (keyword suffix per ADR 0003), `Transform2D.rotation/scale/skew`, `Basis.x/y/z/scale`, `Color.h/s/v/r8/g8/b8/a8/ok_hsl_h/ok_hsl_s/ok_hsl_l/luminance`. They are read-only, because the values are immutable.
- **Mathf**: `Godot.Mathf` holds the scalar helpers and constants that Base lacks (`smoothstep`, `wrap`, `pingpong`, `ease`, `deg_to_rad`, `TAU`, …). Functions shared with the vector types (`lerp`, `snapped`, `posmod`, `move_toward`, `cubic_interpolate`, …) are the same generic functions exported from `Godot`. Base equivalents (`sin`, `clamp`, `sign`, `sincos`, `isfinite`) are not duplicated.

## Consequences

- Every builtin math method in the API has a golden test case (enforced by the GodotBindgen tests), compared with values computed by Godot. The same tests pass with `real_t = Float64` bindings.
- Differences from C# are spelling only (snake_case, type-first static calls, `_`-prefixed constants, 1-based indices) plus the engine-valued `EPSILON`. User documentation (phase 16) must list them.
