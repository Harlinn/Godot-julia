# 8. Builtin Math: The Engine as the Oracle

Every game script does arithmetic on vectors, transforms, quaternions and colors. Many times per frame.

In Godot these are **builtin value types**: `Vector2`, `Vector3`, `Basis`, `Transform3D`, `Quaternion`, `Color` and a dozen more. The engine implements them in C++. C# re-implements them in C# (`GodotSharp/Core/Vector2.cs` and friends), so scripts never cross the native boundary just to add two vectors.

Phase 5 does the same for Julia. You get about 2,200 lines of hand-written math in [`julia/Godot/src/builtins/`](../../julia/Godot/src/builtins):

- 16 types plus `Mathf`,
- every operation allocation-free.

Math code is the ideal place to watch an agent be confidently wrong. Formulas are easy to write plausibly and hard to verify by reading. A sign error in `slerp`, a row/column swap in `Basis`, or an epsilon that is ten times too small all *look* fine.

So the central idea of this phase is simple: the agent never decides what the right answer is. **Godot does.** Every math method is checked against values the engine itself computed.

Where does this phase sit?

- It follows the bindings generator, which already emits the memory layout of these types from the API file.
- It precedes Variant and collections, which need these types to convert to and from engine values.

## The Prompt

[`.github/prompts/gdjl-05-builtin-math.prompt.md`](../../.github/prompts/gdjl-05-builtin-math.prompt.md):

```markdown
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
```

## Anatomy of the Prompt

### "Port Every Public Member of the Corresponding C# File"

Requirement 2 turns an open-ended task ("implement vector math") into a closed one with a checklist. C#'s `Vector2.cs` *is* the list of what `Vector2` needs.

Two details do the heavy lifting:

- The example member names in parentheses (`Angle`, `AngleTo`, `Bounce`, …) show the agent how to read the reference.
- The instruction to use Godot's snake_case names tells it how to translate them.

"Every" is the important word. Agents tend to implement the members that tests or examples mention, and then stop. A complete reference file makes the gaps visible.

The same requirement asks for *"an attribution comment per file referencing the C# source."* Godot is MIT-licensed, and the project instructions require attribution when porting logic. Asking for it per file makes **licensing hygiene** part of the work, not a later cleanup. The 13 builtin source files carry comments such as:

```julia
# Ported from Godot's core/math/vector*.h/.cpp and GodotSharp/Core/Vector*.cs (MIT, Godot contributors).
```

### The Golden-Test Requirement

The first test bullet is the heart of the prompt:

> Golden tests: for each method, compare Julia results against values produced by running the same operations in Godot (generate a fixture with a GDScript or C# tool script, check it into `julia/Godot/test/fixtures/`).

This sentence decides *who knows the right answer*. Not the agent. Not the C# port. Not a textbook. The engine, at the pinned version.

Three properties make this **oracle** work:

- **Independent.** The expected values come from a different implementation (Godot's C++) than the one under test (Julia). A shared misunderstanding is unlikely to produce matching wrong answers.
- **Executable.** A script produces the fixture. Nobody types expected values by hand.
- **Checked in.** The fixture lives in the repository. The unit tests run without Godot, and a regenerated fixture shows up as a reviewable diff.

### An Explicit Scope Fence

> **Swizzle-free**: C# has no swizzling; do not add it (keep parity, avoid scope creep).

**Swizzling** means writing `v.xy` or `v.zyx` to rearrange components. GLSL and some engines offer it as a convenience.

It's exactly the kind of feature a helpful agent might add unprompted: easy, attractive, and fun to implement. It would also add surface area to test, document and maintain, with no parity benefit.

One sentence with a reason ("keep parity, avoid scope creep") prevents it. Today there is no swizzling anywhere in `builtins/`.

The lesson: name the tempting extras and rule them out. An agent can't read your mind about what you *don't* want.

### Julia Idioms, Stated Precisely

Requirement 3 lists the idioms:

- field access,
- operators,
- `isapprox` *with Godot epsilon semantics*,
- `hash`, `show`, `zero`/`one`,
- conversions,
- indexing by axis.

It also sets two constraints: *no `StaticArrays` dependency* and *no heap allocation*.

Why ban the dependency? Without that line, an agent would reasonably reach for StaticArrays.jl, the standard Julia package for small fixed-size vectors. But that would put a third-party package in every game's load path. The native host deliberately keeps that load path minimal (chapter 5).

### Precision Without Type Parameters

Requirement 5 settles a design question in advance. Types depend on the global `real_t` (single or double, chosen when bindings are generated), *"not on a type parameter, so user code writes `Vector2(1, 2)`."*

A `Vector2{Float32}` design would be more "Julian" in the abstract. It would also be much worse for game scripts, which would have to spell out the precision everywhere. Fixing this in the prompt kept the agent from optimizing for generality over usability.

### `${input:types:all types}`

The argument lets a session tackle a subset if the full set is too much for one run. For example: `/gdjl-05-builtin-math Vector2 Vector3`.

In practice the phase ran in one go. Still, the option costs nothing and makes the prompt robust to context limits.

## What the Agent Built

### Layouts from the Generator, Methods by Hand

The split is clean:

- The **memory layout** of each type comes from the API file, through the generator of chapter 7.
- The **methods** are hand-written.

[ADR 0005](../adr/0005-builtin-math-api.md) records that split. It means requirement 1 (layout equals Godot's for the active `real_t`) holds by construction for both precisions. Regenerate with `--precision=double` and every struct changes size to match.

Much of the method code is generated too, but by Julia metaprogramming at load time, not by an external generator. Operations shared by `Vector2`, `Vector3`, `Vector4` and their integer variants are written once and expanded per type ([`vectors.jl`](../../julia/Godot/src/builtins/vectors.jl)):

```julia
for (V, fs, Axis, _) in (_FLOAT_VECTORS..., _INT_VECTORS...)
    n = length(fs)
    @eval begin
        $V() = $(_each(V, fs, _ -> 0))
        Base.zero(::Type{$V}) = $V()
        Base.one(::Type{$V}) = $(_each(V, fs, _ -> 1))
        Base.:+(a::$V) = a
        Base.:-(a::$V) = $(_each(V, fs, c -> :(-a.$c)))
        Base.:+(a::$V, b::$V) = $(_each(V, fs, c -> :(a.$c + b.$c)))
```

Each method expands to straight-line code on the struct's fields. No loops, no arrays. That's what makes "no heap allocation" achievable across hundreds of operations.

### ADR 0005: Where C# and Julia Disagree

[ADR 0005](../adr/0005-builtin-math-api.md) records the decisions where a literal port would have been wrong for Julia or for Godot:

- **Base and LinearAlgebra.** Operations with an existing Julia meaning extend Base (`+`, `==`, `abs`, `clamp`, `length`, `inv`, `isapprox`, `show`, …) or LinearAlgebra (`dot`, `cross`, `norm`, `normalize`, `det`). So `using LinearAlgebra` and `using Godot` work together without name clashes.
- **Indexing is 1-based.** `v[1]` is `x`, the Julia convention, and `v[Vector2_AXIS_X]` indexes by Godot's axis enum. C#'s 0-based indexers are not mirrored.
- **Optional results.** Methods that return `null` on failure in GDScript, such as `Plane.intersect_3`, return `Union{Nothing, Vector3}`.
- **Constants** follow ADR 0003's naming: `Vector2_ZERO`, `Basis_IDENTITY`, and the 148 named colors (`Color_ALICE_BLUE`) are generated from the API file.

And there are two decisions where the agent sided with **the engine over C#**:

> **Rounding and tolerances follow the engine**: `round` rounds half away from zero (`Math::round`), and `is_equal_approx` / `Mathf.EPSILON` use the engine's `CMP_EPSILON = 1e-5`. C#'s `Mathf.Epsilon` is `1e-6`; we follow the engine so Julia agrees with GDScript and with engine-side results (verified by golden tests).

The prompt said to port C#. But C#'s epsilon is ten times smaller than the engine's. Borderline `is_equal_approx` cases would give different answers in Julia than in GDScript.

So the agent:

- followed the engine,
- checked the result with the golden tests,
- wrote down the deviation.

Matrix row 3.3 records it: *"engine `CMP_EPSILON` for `EPSILON`, ADR 0005"*.

When the reference implementation and the ground truth disagree, choose the ground truth and record the choice.

### The Golden Pipeline

The oracle has four pieces:

1. **Cases.** [`julia/Godot/test/fixtures/math_cases.txt`](../../julia/Godot/test/fixtures/math_cases.txt) contains about 650 GDScript expressions, one per line:

   ```text
   # --- Vector2
   Vector2(3, 4).angle()
   Vector2(1, 2).angle_to(Vector2(-3, 0.5))
   Vector2(1, 2).angle_to_point(Vector2(-3, 0.5))
   ```

2. **Evaluation by Godot.** [`scripts/make_math_golden.jl`](../../scripts/make_math_golden.jl) runs headless Godot on [`tests/golden/make_golden.gd`](../../tests/golden/make_golden.gd). That script compiles each line as a tiny GDScript function and records the result with Godot's own `var_to_str`:

   ```gdscript
   		var script := GDScript.new()
   		script.source_code = "static func f():\n\treturn " + line + "\n"
   		if script.reload() != OK:
   			output.store_line(line + "\t!COMPILE_ERROR")
   			continue
   		output.store_line(line + "\t" + var_to_str(script.call("f")))
   ```

3. **The golden file.** [`math_golden.txt`](../../julia/Godot/test/fixtures/math_golden.txt) is headed `# GENERATED by scripts/make_math_golden.jl with Godot 4.7.2-stable (official)` and holds 646 expression/value pairs:

   ```text
   Vector2(1, 2).direction_to(Vector2(-3, 0.5))	Vector2(-0.9363292, -0.35112345)
   Vector2(3, 4).limit_length(2.5)	Vector2(1.5, 2)
   ```

4. **Translation and comparison in Julia.** [`julia/Godot/test/builtins.jl`](../../julia/Godot/test/builtins.jl) parses each GDScript expression *with Julia's own parser*. GDScript's expression syntax is close enough. It then rewrites the expression to the Julia API using the naming rules of ADR 0003:

   ```julia
   "Translate a GDScript expression (parsed by Julia) to the Julia API (ADR 0003 naming)."
   function translate(ex)
       ex isa Symbol && return get(GD_CONSTANTS, ex, ex)
       ex isa Expr || return ex
       if ex.head === :call
           f = ex.args[1]
           args = map(translate, ex.args[2:end])
           if f isa Expr && f.head === :.
               return Expr(:call, f.args[2].value, translate(f.args[1]), args...)   # recv.m(args) / Type.static(args)
           end
   ```

   `Vector2(1, 2).angle_to(v)` becomes `angle_to(Vector2(1, 2), v)`, `Vector2.ZERO` becomes `Vector2_ZERO`, and so on. The result is evaluated and compared component by component. A small tolerance (`2e-4`, absolute plus relative) absorbs the difference between single-precision Julia structs and the decimal text Godot prints.

The translator brings a nice bonus. Every golden case is translated mechanically, so the test also verifies that ADR 0003's naming rules are applied consistently. If a Julia method were spelled differently from what the rules predict, its case would fail.

### Coverage That Cannot Silently Drop

Who checks that the 646 cases cover every method? Another test.

The GodotBindgen test suite (chapter 7) contains a test named *"every builtin math method has a golden case"*. It reads `extension_api.json` and `math_cases.txt` and fails if any math method in the API has no case.

Picture a future Godot version that adds a method. Regenerating the bindings makes that test fail until:

- someone writes a case for it,
- the case is evaluated by Godot,
- the Julia implementation matches.

Coverage is enforced, not hoped for.

### Allocation Tests

The same test file runs a list of 27 operations and asserts each one allocates nothing. The list runs from `rotated(Vector2(1, 2), 0.3)` through `spherical_cubic_interpolate` on quaternions to `from_ok_hsl(Color, …)`:

```julia
        for op in ops
            op()
            @test (@allocated op()) == 0
        end
```

The first call compiles the operation. The second measures it.

## Where Reality Pushed Back

### Godot 4.7 Rewrote Two `Projection` Functions

The phase 5 report:

> Two `Projection` functions initially differed because Godot 4.7 rewrote them; I ported the exact 4.7 formulas from the engine source.

The agent's first implementation followed an older formulation. Godot 4.7 computes several `Projection` properties in closed form: near and far planes, field of view, and the level-of-detail multiplier.

Here's what happened next:

- The golden tests failed.
- The agent fetched `core/math/projection.cpp` at the pinned tag.
- It ported the current formulas.

The code now says which version it follows ([`projection.jl`](../../julia/Godot/src/builtins/projection.jl)):

```julia
# These assume a projection along Z with a rectangular projection plane, as in Godot 4.7.
"Far clipping distance."
get_z_far(p::Projection) = (_c(p, 3, 3) - _c(p, 3, 2)) / (_c(p, 2, 3) - _c(p, 2, 2))
"Near clipping distance."
get_z_near(p::Projection) = (_c(p, 3, 3) + _c(p, 3, 2)) / (_c(p, 2, 3) + _c(p, 2, 2))
```

This is the golden-test design paying for itself. Without engine-computed expected values, the older formulas would have passed any test the agent wrote for itself. Why? The agent would have written those tests from the same stale understanding.

The rule went into the agent's memory notes: *"fetch core/math/\*.cpp at the 4.7.2-stable tag when unsure."*

### Rows Versus Columns in `Basis`

`Basis` is a 3×3 rotation/scale matrix, and it's a classic trap:

- Godot stores it as three *rows* in memory.
- But `basis.x`, `basis.y` and `basis.z` mean the *columns* in both GDScript and C#.
- The constructor `Basis(x, y, z)` takes columns too.

A port that mixes the two up produces transforms that look almost right and rotate the wrong way.

ADR 0005 settles it explicitly:

- The generated struct names its fields `row0..row2`, so nobody confuses storage with meaning.
- A tagged constructor `Basis(Internals.ROWS, r0, r1, r2)` builds from rows.
- `Basis(x, y, z)` and `b.x/b.y/b.z` use columns, as in C#.

A unit test pins all of it down in two lines:

```julia
        b = Basis(Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9))
        @test b.x == Vector3(1, 2, 3) && b.z == Vector3(7, 8, 9)          # columns, as in GDScript and C#
        @test b.row0 == Vector3(1, 4, 7) && b[1, 3] == 7 && get_column(b, 2) == Vector3(4, 5, 6)
```

The integration tests add the engine's view: `Basis` text and memory layout must agree with Godot's `var_to_str`.

When a domain has a well-known confusion:

- name it in the code (`row0`, not `x`),
- decide it in an ADR,
- write the test that would catch the mistake.

### Startup Grew Again

The report noted its own cost:

- Warm `using Godot` went from 0.47 s to 0.54–0.67 s.
- The in-engine `Godot.Runtime` step went from about 0.76 s to 0.88 s.

The agent checked where the time went (*"in the package itself, not `LinearAlgebra`"*) and handed the problem to phase 14's system image.

Every phase so far had added a line to [`docs/perf.md`](../perf.md). Because that history exists, you can see the gradual cost of features and the moment the system image recovered it.

### Double Precision Tested Without a Double-Precision Engine

The prompt asked for engine round-trips *"for both single and double precision builds in CI."* There was no double-precision Godot build and no CI yet.

The agent did what it could. It regenerated the bindings with 64-bit floats in a temporary copy and ran all the math tests there. They all passed.

It then left row 1.7 `PARTIAL`, with an exact note of what was missing. *"Double precision against a real engine is untested"* is a better status than a green checkmark that means less than it seems.

## Closing the Loop

Three commands cover the math types:

```powershell
julia --project=julia/Godot -e "using Pkg; Pkg.test()"       # golden, layout, idiom and allocation tests (no engine)
julia --project=julia/GodotBindgen -e "using Pkg; Pkg.test()" # includes: every math method has a golden case
julia scripts/make_math_golden.jl                              # regenerate golden values with the pinned Godot
```

The integration suite adds engine round-trips. The `bindings` project:

- sets and reads back `Node2D`/`Node3D` transforms,
- compares `Basis` layout and text with Godot's own,
- has Godot's `Expression` class compute the same results as Julia.

The golden tests carry `# parity: 3.1–3.3`, tying them to the matrix rows the phase owns.

Notice that the workflow for extending the math API never involves the agent deciding what is correct:

1. add a GDScript case to `math_cases.txt`;
2. run `make_math_golden.jl` to let Godot compute the answer;
3. implement or fix the Julia method until the golden test passes.

## Techniques to Reuse

- **Let the reference compute the expected values.** Generate fixtures by running the real system, check them in, and compare against them. Never let the agent write both the code and the answers.
- **Enforce coverage mechanically.** A test that every API member has a case keeps a growing API from outpacing its tests. It's chapter 3's "turn rules into scripts" applied to an API.
- **Fence off tempting extras.** Name the features you don't want ("no swizzling") and say why.
- **Follow the ground truth over the reference port, and record it.** When the engine and the C# port disagree, match the engine and write an ADR.
- **Name the trap in the code.** `row0..row2` instead of `x/y/z` makes a classic confusion impossible to make by accident.
- **Attribute as you port.** Require an attribution comment per ported file. It's cheaper than a licensing audit later.

## Try It Yourself

1. Add a new case to `julia/Godot/test/fixtures/math_cases.txt`, for example `Vector3(1, 2, 3).bounce(Vector3(0, 1, 0))`. Run `julia scripts/make_math_golden.jl`, then run the `Godot` package tests. Next, deliberately break the Julia `bounce` and confirm the golden test catches it.
2. Open the **Ask** agent and ask: *"Why does Godot-julia's `Mathf.EPSILON` differ from C#'s `Mathf.Epsilon`, and where is that decided and tested?"* A good answer cites ADR 0005, matrix row 3.3, and the `Mathf.EPSILON == 1e-5` test.
3. Ask the agent to implement swizzling (`v.xy`). Watch whether it points out the prompt's scope fence and the parity argument before writing code. Then discuss with it whether the fence still makes sense.

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 3.1 | Vector2/2i/3/3i/4/4i, Rect2/2i, Transform2D/3D, Basis, Quaternion, Plane, AABB, Projection, Color | DONE (ADR 0005; every API method golden-tested against Godot, allocation-free; `julia/Godot/test/builtins.jl`) |
| 3.2 | Operators (`+ - * /`, `==`, approximate equality) | DONE |
| 3.3 | `Mathf` | DONE (engine `CMP_EPSILON` for `EPSILON`, ADR 0005) |
| 1.7 | Single and double precision (`real_t`) builds | PARTIAL (math verified with `real_t = Float64` bindings; a double-precision engine run in CI has not happened yet) |

---
[← Previous: The Bindings Generator](07-bindings-generator.md) · [Contents](README.md) · [Next: Variant and Collections →](09-variant-collections.md)
