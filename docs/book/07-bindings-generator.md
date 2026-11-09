# 7. The Bindings Generator: Scale Through Generation

Phase 4 is where the project grows by two orders of magnitude.

Before it, Julia can call any Godot function, but only by hand, through raw pointers and method hashes. After it, Julia has the whole engine API: every class, method, property, signal, enum and constant. Each one comes with documentation, typed arguments and default values.

Here are the numbers from [parity matrix row 2.1](../csharp-parity-matrix.md): **1036 classes, 16.8k methods, 4162 properties, 0 skipped.**

No agent wrote those bindings. It wrote a **generator**, about 1,400 lines of Julia in [`julia/GodotBindgen/src/`](../../julia/GodotBindgen/src). The generator wrote the bindings. Its main output file, `classes.jl`, is about 269,000 lines.

This chapter shows you why that distinction matters so much when an agent does the work. It also covers the design decisions the prompt deliberately left to the agent, with one condition attached.

Where does the phase sit?

- **After the FFI layer**, because the generated code calls `FFI.ptrcall`, method binds and `StringName` caches.
- **Before the math types, Variant and the object model**, because those phases add hand-written code *around* the generated API, not inside it.

## The Prompt

[`.github/prompts/gdjl-04-bindings-generator.prompt.md`](../../.github/prompts/gdjl-04-bindings-generator.prompt.md):

```markdown
---
name: gdjl-04-bindings-generator
description: "Phase 4: GodotBindgen — generate the full Julia engine API from extension_api.json, matching C#'s bindings_generator."
agent: agent
---
Implement `julia/GodotBindgen` to generate `julia/Godot/src/generated/` from `extension_api.json` (with docs). Follow the [project instructions](../copilot-instructions.md). Behavioral reference: `modules/mono/editor/bindings_generator.cpp` and the generated output of `GodotSharp` / `GodotSharpEditor` (study what C# exposes and how it names/organizes it).

## Output Requirements

1. **Classes**: for every class, `abstract type X <: Parent end` (root: `GodotObject`) plus a concrete native wrapper for classes that can be instantiated or returned. Respect `api_type` (`core` → `Godot`, `editor` → `Godot.Editor`).
2. **Constructors**: `X()` for instantiable classes calls `classdb_construct_object2` and binds the wrapper (lifetime handled in phase 07; emit calls to its API).
3. **Methods**: one Julia method per engine method, first arg `self::X` (abstract type, so subclasses and user scripts inherit). Typed args/returns, default values from the API as Julia defaults, varargs for `is_vararg`. Static methods as functions on `Type{X}`: `ResourceLoader.load(...)`-style singleton access and `X.static_method(...)` via `getproperty(::Type{X}, ...)` dispatch or a nested module — document the choice.
4. **Properties**: `Base.getproperty`/`setproperty!` on the abstract type, resolved at compile time from `Symbol` constants (type-stable via `Val`-free `if` chains or generated functions). Also emit explicit getter/setter methods. Indexed properties supported.
5. **Signals**: per class, signal metadata (name, arg types) for phase 10 typed connect/emit helpers.
6. **Enums/bitfields/constants**: class-scoped and global. Enums as a typed integer wrapper with named instances and `show`; bitfields support `|`, `&`, `~`, `in`. Reachable as `Node.ProcessMode.PROCESS_MODE_INHERIT`-like nesting or `Node.PROCESS_MODE_INHERIT` — pick the most ergonomic option, ensure no world-age/type piracy issues, and record it in an ADR.
7. **Singletons**: `Input`, `Engine`, `OS`, ... resolve lazily via `global_get_singleton` and allow `Input.is_action_pressed("jump")`.
8. **Utility functions**: `GD`-equivalent module (`print`, `push_error`, `randf`, `load`, `str_to_var`, ...) avoiding clashes with `Base.print` (C# uses `GD.Print`; expose as `GD.print` and export non-clashing names).
9. **Virtual methods**: emit stub generic functions (`function _process end`) with docstrings, plus a registry mapping virtual names → Julia functions used by phase 08 to detect overrides via `hasmethod`.
10. **Docs**: convert class-reference BBCode (`[method foo]`, `[code]`, `[codeblocks]` — keep the C#/GDScript example as reference) to Markdown docstrings.
11. **Name hygiene**: rename `Object` → `GodotObject`; escape Julia keywords (`function`, `end`, `type`, `global`, ...) with a documented suffix; for names exported by `Base` (e.g. `Timer`), define but do not export. Generate a report of all renames.
12. **Builtin types** (`Vector2`, ...) are *not* generated here — phase 05 hand-writes them; generator only emits glue for builtin methods not covered by the hand-written versions.
13. **Extension classes**: support regenerating against an API dump that includes other GDExtensions' classes (parity with C# seeing extension classes).

## Quality

- Generated code is deterministic, formatted, and loads in < N seconds with precompilation (measure and record).
- `Godot` precompiles cleanly (`PrecompileTools` workload covering common calls).
- Unit tests in `julia/GodotBindgen/test` using a trimmed fixture API JSON.
- Integration test: create a `Node2D`, set `position`, call `get_child_count`, read `Engine.get_version_info()`.

Update parity rows 2.1–2.12.
```

## Anatomy of the Prompt

### "Study What C# Exposes and How It Names/Organizes It"

The behavioral reference has two parts:

- the C# generator itself (`bindings_generator.cpp`),
- its *output*: the GodotSharp API that C# developers actually use.

The second part matters more.

The generator tells the agent how C# handles edge cases: varargs, default values, nested enums, editor-only classes. The output tells it what a good result *looks* like to someone writing a game.

Pointing at both changes the task. "Generate bindings" becomes "produce something a C# Godot developer would recognize, in Julia idioms".

### Thirteen Numbered Requirements, Each One Checkable

This is the longest prompt so far. Its length is deliberate.

A bindings generator involves dozens of decisions that are easy to forget until someone trips over them:

- What happens to default arguments?
- How are varargs passed?
- Where do enums live?
- What about a Godot class called `Timer`, when Julia's `Base` already exports a `Timer`?

Each numbered item either closes one of those questions or forces the agent to close it explicitly.

The requirements read like a checklist. That's exactly how the agent's report treated them: it went item by item and said which rows were `DONE` and which were `PARTIAL`.

### Delegated Design Authority, with an Obligation

Requirements 3 and 6 do something the earlier prompts didn't. They hand a real API design decision to the agent:

> Reachable as `Node.ProcessMode.PROCESS_MODE_INHERIT`-like nesting or `Node.PROCESS_MODE_INHERIT` — pick the most ergonomic option, ensure no world-age/type piracy issues, and record it in an ADR.

> … via `getproperty(::Type{X}, ...)` dispatch or a nested module — document the choice.

When we wrote the prompt, we knew the options. We didn't know which one would work best in Julia.

So the prompt does three things:

- names the candidates,
- names the constraints ("no world-age/type piracy issues"),
- lets the agent decide, and requires a written record.

That last part is what makes **delegation** safe. The decision became [ADR 0003](../adr/0003-generated-api-shape.md). It's visible to us for review, and it binds every later session.

As you'll see shortly, the agent used that authority to reject the prompt's own preferred spelling.

### A Scope Boundary Between Phases

Requirement 12 says what *not* to generate: *"Builtin types (`Vector2`, ...) are not generated here — phase 05 hand-writes them."*

Without that sentence, a capable agent would naturally generate `Vector2` methods from the same API file. Phase 5 would then either fight them or duplicate them.

**Explicit phase boundaries** stop two sessions from building the same thing two different ways.

### Name Hygiene with an Audit Trail

Requirement 11 lists the naming rules:

- rename `Object`,
- escape keywords,
- don't export Base clashes.

It ends with *"Generate a report of all renames."*

That report is the agent's **audit trail** of its own decisions. With tens of thousands of generated names, nobody can review the output line by line. But you *can* review a report of every name that was changed, and why.

### Quality Criteria That Are Measurable

The quality section asks for:

- **determinism**: the same input must produce the same output, so diffs are meaningful,
- measured load time,
- a precompile workload,
- unit tests on a **trimmed fixture** of the API file,
- one concrete integration test: *"create a `Node2D`, set `position`, call `get_child_count`, read `Engine.get_version_info()`."*

That last sentence is a smoke test you can run in your head. If those four operations work, so do the generator, the FFI, properties, singletons and the Variant path for dictionaries.

## What the Agent Built

### A Generator in Three Layers

[`julia/GodotBindgen/src/`](../../julia/GodotBindgen/src) splits the problem:

- **`context.jl`** holds the naming and type-mapping rules. `Object` becomes `GodotObject`. Methods whose names Base exports as functions *extend* those functions. Names that would clash with keywords, non-function Base exports or the module-implicit `eval`/`include` get a trailing `_`. The rules are code, not prose:

  ```julia
  "Julia generic function used for a Godot method name (extends `Base` when Base exports a function of that name)."
  function method_function(ctx::Context, name::AbstractString)
      name in ctx.base_functions && return "Base.$name"
      # All method generic functions are owned by `Godot`, including those only editor classes implement.
      return qualify(ctx, false, name in ctx.reserved ? name * "_" : String(name))
  end
  ```

- **`classes.jl`, `globals.jl`, `structs.jl`, `builtin_methods.jl`, `layout.jl`, `interface.jl`** each emit one generated file.
- **`bbcode.jl`** converts Godot's class-reference markup into Markdown docstrings.

Output is sorted wherever order would otherwise depend on dictionary iteration (`sort(collect(keys(ctx.classes)))` and similar).

That's how the generator meets the "deterministic" requirement. The same API file produces the same output, so a diff between two generations shows only real API changes.

### What Generated Code Looks Like

Here's one method from `generated/classes.jl`, exactly as the generator writes it:

```julia
"""
    get_child_count(self::Node, include_internal::Bool = false)

Returns the number of children of this node.
If `include_internal` is `false`, internal children are not counted (see `add_child`'s `internal` parameter).
"""
function get_child_count(self::Node, include_internal::Bool = false)
    __mb = Internals.@method_bind(:Node, :get_child_count, 894402480)
    __a1 = include_internal
    __r = FFI.ptrcall(Int64, __mb, Internals.native_ptr(self), __a1)
    return __r
end
```

Everything the prompt asked for is visible:

- The docstring comes from the class reference.
- The receiver is typed as the *abstract* `Node`, so every subclass, and every user script that extends `Node`, inherits the method.
- The default value is translated.
- The call goes through a cached method bind and the zero-allocation `ptrcall` from chapter 6.

Properties are generated as a chain of `getproperty` methods, one per class. Each one handles its own properties and delegates the rest to its parent class with `invoke`:

```julia
Base.@constprop :aggressive @inline function Base.getproperty(self::Node2D, s::Symbol)
    s === :position && return get_position(self)
    s === :rotation && return get_rotation(self)
    ...
    return invoke(Base.getproperty, Tuple{CanvasItem, Symbol}, self, s)
end
```

Take a literal property name such as `n.position`. Julia's compiler propagates the constant symbol, removes every branch but one, and compiles the access down to a direct `get_position` call.

The integration test checks that claim: `@allocated position_of(n)` must be `0`.

### The Rename Report

Every generation writes `generated/binding_report.txt`. For Godot 4.7.2 it lists:

- one class rename (`Object -> GodotObject`),
- 24 Base functions that generated methods extend (`close`, `get`, `lock`, `show`, `open`, `wait`, …),
- two classes defined but not exported, because Base exports the same names (`Timer`, `WeakRef`),
- 113 builtin-type methods not bound, because Julia already has an equivalent (`String.length`, `String.split`, …).

That's a few dozen lines summarizing every naming decision across hundreds of thousands of generated lines.

### The API Shape: ADR 0003

[ADR 0003](../adr/0003-generated-api-shape.md) records the decisions the prompt delegated:

- **Classes** are abstract types mirroring Godot's tree, with concrete wrappers in `Godot.Native`.
- **Methods** are generic functions with the receiver first: `add_child(node, child)`.
- **Static methods and singletons** take the class *type* as the receiver: `file_exists(FileAccess, path)`, `is_action_pressed(Input, "jump")`.
- **Class enums and constants** are module-level names with a class prefix: `Node_PROCESS_MODE_ALWAYS`, `Node_NOTIFICATION_READY`.
- **Properties** use dot syntax through the generated `getproperty`.
- **Utility functions** live in `GD`, as in C#.

Notice what's missing: `Input.is_action_pressed("jump")`, the spelling requirement 7 asked for. The ADR explains why:

> The obvious way to imitate `Class.MEMBER` in Julia is to overload `Base.getproperty(::Type{Node}, s::Symbol)`. Every such method intersects the `getproperty(::DataType, ::Symbol)` specialization that Base uses everywhere (`T.name`, `T.parameters`, ...). Loading the package would then invalidate a large amount of compiled Base code. We rejected this.

**Invalidation** means Julia throws away compiled code because a new method could change its behavior. Loading a package that invalidates large parts of Base makes everything after it slower to start.

The agent recognized that the prompt's suggestion, natural for a C# developer, would hurt every Julia user of the package. It chose a different spelling and stated the consequence honestly:

> The C# parity row for singleton/static call syntax is met in capability, not in spelling.

This is the delegated-authority pattern working as intended.

- The prompt said "pick the most ergonomic option" *and* "ensure no … type piracy issues".
- The agent weighed the two and wrote down why.
- You're left with a decision you can review in one page.

### The Editor API: ADR 0004

Requirement 1 says editor-only classes (`api_type` `editor`) belong in `Godot.Editor`. The first implementation generated them as a submodule compiled into `Godot`.

[ADR 0004](../adr/0004-editor-api-package.md) explains why that wasn't good enough. Julia compiles a package into a single cache. So every game paid to load 82 editor classes (722 methods) it could never use, and exports would have to ship them.

The fix moved them into a separate package, `GodotEditor`. It's loaded only when the Godot editor is actually running, the same condition C# uses for GodotSharpEditor. Warm `using Godot` dropped from 0.59 s to 0.47 s.

That ADR came out of the second phase-4 run (chapter 3). The driver noticed that rows 2.9 and 2.12 were still `PARTIAL`, and went back to finish them before starting phase 5.

### Virtuals, Signals and `GD`

- **Virtuals.** For every virtual method (`_ready`, `_process`, `_input`, …), the generator emits an empty generic function with a docstring. It also emits a registry of virtual names and signatures. Phase 8 uses it to detect which callbacks a script overrides.
- **Signals.** Signal metadata is emitted per class, for phase 10's typed `connect_<signal>`/`emit_<signal>` helpers.
- **`GD`.** The `GD` module combines generated utility functions with a small hand-written file, [`core/gd.jl`](../../julia/Godot/src/core/gd.jl), which the generated code includes. That file adds `GD.load(T, path)`, the equivalent of C#'s `GD.Load<T>`.

Note the direction: hand-written code is included *by* the generated code, never patched *into* it.

## Where Reality Pushed Back

### Startup Doubled

The first phase 4 report flagged its own regression:

> **Startup got slower.** The Julia part of engine startup went from about 0.7 s to about 1.4 s; Godot's total startup is about 2 s. Outside the engine, `using Godot` takes 0.59 s, and precompiling takes about 56 s.

Loading 1036 classes costs time.

The follow-up run brought the in-engine step down to about 0.76 s with two changes:

- the editor split of ADR 0004,
- a precompile workload.

Precompiling grew to about 71 s. That's a cost you pay once per change to the package.

Every step is recorded in [`docs/perf.md`](../perf.md). The remaining gap was handed to phase 14's custom system image, which brought exported games to about 0.21 s.

### PrecompileTools Was Not Available

The prompt asked for a *"`PrecompileTools` workload covering common calls."* **PrecompileTools** is the standard Julia package for this. But inside the engine, the package can't use it.

The native host deliberately isolates the game's load path. Only Godot-julia's own packages and Julia's standard library are visible (chapter 5).

So the agent replaced it with plain `precompile` directives in [`precompile.jl`](../../julia/Godot/src/precompile.jl). Its header says why:

```julia
# Precompile workload. Dependency-free stand-in for PrecompileTools: inside the engine, LOAD_PATH holds only the
# Godot-julia packages and stdlibs. Engine calls cannot execute at precompile time, so they are compiled, not run.
```

The first report had listed the workload as not done. The second run added it.

Here's what happened, in short:

- One requirement in the prompt conflicted with a decision made in an earlier phase.
- The agent noticed.
- It picked the alternative that respects the earlier decision, and documented the substitution.

### Godot Would Not Dump Docs with Extensions Loaded

Requirement 13 asks for bindings to classes registered by *other* GDExtensions.

`scripts/fetch_api.jl --project=<project>` dumps the API with that project's extensions loaded, and the generator merges their classes in. But Godot 4.7 exits with an error when asked for the dump *with docs* once extensions are loaded.

The result: extension classes come in without docstrings, while engine classes keep theirs.

The limitation is stated in the script's comments and in the report. Nobody worked around it with a fragile hack.

### Small Generator Traps

A generator multiplies every small mistake by thousands. Here are a few rules the agent learned and recorded:

- **Declare variables before `try`.** When a call has arguments that must be destroyed afterwards, the generated code wraps the call in `try … finally`. In Julia, a variable first assigned inside a `try` block is local to that block. So the generator emits `local __r` before it. The relevant fragment of [`classes.jl`](../../julia/GodotBindgen/src/classes.jl):

  ```julia
      isempty(owned) || println(io, indent, "local __r")
      for (local_name, expr) in owned
          println(io, indent, "$local_name = $expr")
          println(io, indent, "try")
  ```

- **`eval` and `include` are reserved.** Every Julia module defines its own, so a Godot method with one of those names gets a trailing `_` (see `context.jl` above).
- **Include order matters.** `global_enums.jl` must be included before `classes.jl`, because method signatures refer to global enum types.

### A Name That Meant Two Things

Requirement 11 said to define but not export classes whose names Base already exports, such as `Timer`.

That protects *user* code. It sees Julia's `Timer` unless it writes `Godot.Timer`.

*Inside* module `Godot`, however, the generated classes shadow the Base names. In phase 7, code meant to create a Julia `WeakRef` called `WeakRef()`. It got Godot's `WeakRef` class instead, and recursed until the stack overflowed.

Package code now always writes `Base.WeakRef`, `Base.Timer` and so on (chapter 10 tells the full story).

The lesson for generators: a naming rule that protects your users can still change meaning inside your own package.

## Closing the Loop

Three layers of tests guard the generator.

**Unit tests on a trimmed fixture** ([`julia/GodotBindgen/test/runtests.jl`](../../julia/GodotBindgen/test/runtests.jl)) generate bindings for a small set of classes (`Object`, `RefCounted`, `Resource`, `Node`, `CanvasItem`, `Node2D`, `Engine`, `FileAccess`, …). They check:

- naming,
- type mapping,
- default values,
- BBCode conversion,
- merging of extension classes.

A *full generation into a temporary directory* checks that the complete output parses.

One test reaches across phases: *"every builtin math method has a golden case"*. If Godot adds a math method, the generator's tests fail until phase 5's golden tests cover it.

**An in-engine integration project** ([`tests/integration/bindings/test_bindings.jl`](../../tests/integration/bindings/test_bindings.jl), tagged `# parity: 2.1–2.12`) runs the prompt's smoke test and much more:

```julia
        n = Node2D()
        @test n isa Node2D
        @test n isa CanvasItem
        @test n isa GodotObject
        n.position = Vector2(3, 4)
        @test n.position == Vector2(3, 4)
```

It also checks:

- `@allocated child_count(n) == 0`,
- `get_version_info(Engine)["minor"] == 7`,
- enum `show` output,
- bitfield operators.

**The editor/game split** is tested from both sides. The integration runner checks [`expect_import_output.txt`](../../tests/integration/bindings/expect_import_output.txt) against the editor-mode (`--import`) run, which must print `Godot-julia: editor API (Godot.Editor) loaded`. The game run must *not* load it.

Regeneration is one command:

```powershell
julia scripts/generate_bindings.jl                     # single precision
julia scripts/generate_bindings.jl --precision=double  # for double-precision Godot builds
```

## Techniques to Reuse

- **Have the agent write the generator, not the output.** A generator of about 1,400 lines is reviewable and testable. A 269,000-line `classes.jl` is neither. This builds on chapter 6's "generate from the machine-readable source".
- **Delegate a decision, require a record.** Name the options and constraints, let the agent choose, and require an ADR you can review in one page. It's chapter 4's "decide, then write it down", applied to a decision the agent makes.
- **Draw explicit phase boundaries.** Say what this phase must *not* build when a later phase owns it.
- **Ask for an audit trail of automated decisions.** A rename report turns thousands of naming choices into a short list you can review.
- **Make generated output deterministic.** Sorted, byte-identical output makes diffs meaningful and regressions visible.
- **Include hand-written code from generated code**, never the other way around. That way, regeneration never destroys human work.

## Try It Yourself

1. Run `julia scripts/generate_bindings.jl` and open `julia/Godot/src/generated/binding_report.txt`. Ask the **Ask** agent to explain three entries and point to the rule in `julia/GodotBindgen/src/context.jl` that produced each one.
2. Ask the **Plan** agent: *"How would you add a new naming rule to the bindings generator, end to end?"* A good plan touches `context.jl`, adds a fixture test in `julia/GodotBindgen/test/runtests.jl`, regenerates, updates the report, and amends ADR 0003.
3. Read the *Context* section of ADR 0003. Then ask the agent to measure the invalidation cost of the rejected design in a scratch environment. A reasonable approach: define `Base.getproperty(::Type{X}, ::Symbol)` for a dummy type and inspect the invalidations with `SnoopCompileCore`. Compare the result with the ADR's claim.

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 2.1 | Bindings for every ClassDB class, method, property | DONE (1036 classes, 16.8k methods, 4162 properties, 0 skipped) |
| 2.2 | Inheritance hierarchy | DONE (abstract types plus `Godot.Native` wrappers; one wrapper per object since phase 07) |
| 2.3 | Engine singletons | DONE (`is_action_pressed(Input, ...)` and `singleton(T)`, ADR 0003) |
| 2.4 | Enums, bitfields, constants | DONE (typed `GodotEnum`/`GodotBitfield` values, prefixed constants) |
| 2.5 | Utility functions on `GD` | DONE (`Godot.GD`, including `GD.load(T, path)`) |
| 2.6 | Vararg methods | DONE |
| 2.7 | Default arguments | DONE (all Godot defaults translated) |
| 2.8 | Doc comments from the class reference | DONE (BBCode → Markdown docstrings) |
| 2.9 | Editor API in a separate assembly/package | DONE (`GodotEditor`, loaded only in the editor, ADR 0004) |
| 2.10 | Cached `MethodName`/`PropertyName`/`SignalName` | DONE (per-call-site caches; per-script tables from phase 09) |
| 2.11 | Overridable virtual methods | DONE (dispatch from phase 08) |
| 2.12 | Classes from other GDExtensions | DONE (by name, or typed via `fetch_api.jl --project=...` and regeneration) |

After the first phase-4 run, five of these were `PARTIAL`. The second run finished two, and phases 7, 8 and 9 completed the remaining three.

---
[← Previous: The FFI Layer](06-ffi-layer.md) · [Contents](README.md) · [Next: Builtin Math →](08-builtin-math.md)
