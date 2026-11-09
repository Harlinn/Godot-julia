# 12. Authoring Macros: Attributes, Generators and Analyzers in Julia

A script language lives or dies by how it feels to write.

In C#, you decorate a Godot class with **attributes**: `[Export]`, `[Signal]`, `[Tool]`, `[GlobalClass]`, `[Rpc]`. Behind the scenes, a set of Roslyn *source generators* produces the glue the engine needs:

- property lists,
- default values,
- method tables,
- signal helpers,
- serialization code.

A set of *analyzers* reports mistakes while you type, with stable codes like `GD0102`. None of that shows up in your code. All of it matters.

Phase 9 builds the Julia equivalent. That means annotations inside `@godot_class` for every C# export form, plus:

- signals with typed helpers,
- tool buttons,
- global classes and icons,
- RPC configuration,
- static methods.

All of it is generated as static, type-stable code. Mistakes are reported with diagnostic codes that map one-to-one to C#'s.

This chapter tells two stories:

- **Mapping concepts across ecosystems.** Attributes become macros, source generators become macro expansion, analyzers become load-time errors.
- **Prompts that evolve with the code.** This is the first prompt in the project that an earlier phase rewrote *before* it ran.

## The Prompt

[`.github/prompts/gdjl-09-authoring-macros.prompt.md`](../../.github/prompts/gdjl-09-authoring-macros.prompt.md):

````markdown
---
name: gdjl-09-authoring-macros
description: "Phase 9: Julia authoring macros equivalent to C# attributes + source generators (@godot_class, @export*, @signal, @tool, @global_class, @icon, @rpc) with analyzer-style diagnostics."
agent: agent
---
Implement the user-facing script authoring API in `julia/Godot/src/macros/`. Follow the [project instructions](../copilot-instructions.md). Behavioral references: `Godot.SourceGenerators/` (`ScriptPathAttributeGenerator`, `ScriptPropertiesGenerator`, `ScriptPropertyDefValGenerator`, `ScriptMethodsGenerator`, `ScriptSignalsGenerator`, `ScriptSerializationGenerator`, `MustBeVariantAnalyzer`, `GlobalClassAnalyzer`, diagnostic descriptors), `GodotSharp/Core/Attributes/`, and docs `c_sharp_exports.rst`, `c_sharp_signals.rst`, `c_sharp_global_classes.rst`.

Phase 08 already provides the base: `@godot_class` (in `julia/Godot/src/object/scripting.jl`) handles plain `@export`, `@signal`, the `tool`/`global_class`/`abstract`/`icon` options and the `@tool`/`@global_class`/`@icon` wrappers. Body annotations are rewritten syntactically by `@godot_class` and are not standalone macros. Extend that expansion, feeding hints/usage/groups into `Runtime.ScriptField` and `Runtime.property_type`/`field_prop` (ADR 0008), rather than starting over. Add integration tests for the `_get`/`_set`/`_get_property_list`/`_validate_property` overrides (row 5.18, dispatch already implemented in `runtime/instances.jl`).

## Target Syntax (refine, but keep the spirit)

```julia
using Godot

@tool
@global_class
@icon("res://icons/player.svg")
@godot_class mutable struct Player <: CharacterBody2D
    @export_category("Movement")
    @export speed::Float64 = 300.0
    @export_range(0, 100, 1; or_greater = true) health::Int = 100
    @export_group("Visuals", prefix = "visual_")
    @export visual_tint::Color = Color(1, 1, 1)
    @export target::Union{Node2D, Nothing} = nothing
    @export items::GDArray{Item} = GDArray{Item}()
    @export_tool_button("Reset", "Reload") reset_action::Callable = Callable(reset!)
    cooldown::Float64 = 0.0          # not exported, still serialized across hot reload

    @signal health_changed(old::Int, new::Int)
end

@rpc(:any_peer, :call_local, :reliable) function shoot(self::Player, dir::Vector2) ... end

Godot._physics_process(self::Player, delta::Float64) = ...
```

## Requirements

1. **`@godot_class`**: injects the native handle field, generates constructors (engine path + Julia path), field defaults, `getproperty`/`setproperty!` that prefer Julia fields then fall back to inherited Godot properties, and emits a metadata record consumed by `Godot.Runtime` (equivalent to the C# generated `GetGodotPropertyList`, `GetGodotMethodList`, `GetGodotSignalList`, `InvokeGodotClassMethod`, `SetGodotClassPropertyValue`, `GetGodotClassPropertyValue`, `HasGodotClassMethod`). Generated dispatch must be static (no `getfield(obj, sym)` with runtime symbols on hot paths).
2. **Methods exposed to the engine**: every function whose first argument is annotated with the script type and is defined in the script module is exposed (C# exposes all methods of the class). Static methods: functions taking `::Type{Player}`.
3. **Exports**: every C# export form, including all `PropertyHint`s: `@export_range`, `@export_enum`, `@export_flags`, `@export_flags_2d_physics/render/navigation/avoidance` (and 3D), `@export_file`, `@export_dir`, `@export_global_file/dir`, `@export_multiline`, `@export_placeholder`, `@export_exp_easing`, `@export_color_no_alpha`, `@export_node_path`, `@export_storage`, `@export_custom(hint, hint_string, usage)`, Node/Resource-typed exports, typed `GDArray{T}`/`GDDictionary{K,V}`, enums and bitfields (Julia `@enum` and generated Godot enums), groups/subgroups/categories, tool buttons.
4. **Default values**: record initializer expressions per property for `_has_property_default_value`/`_get_property_default_value` (inspector revert arrows).
5. **Signals**: `@signal name(args...)` generates signal metadata, a cached `StringName` (`Player.SignalName.health_changed` equivalent), typed `emit_health_changed(self, old, new)` and typed `connect_health_changed(self, f)` helpers (C# event parity).
6. **Attributes**: `@tool`, `@global_class` (name + base for Create dialog), `@icon(path)`, `@rpc(mode, sync, transfer_mode, channel)` feeding `_get_rpc_config`. Abstract scripts (`@godot_class abstract type ...` or an `abstract=true` flag) supported.
7. **StringName caches**: generated `MethodName`, `PropertyName`, `SignalName` constants per script.
8. **Diagnostics**: macro-expansion-time errors that mirror the C# analyzer diagnostics (e.g. class name ≠ file name, exporting non-Variant-compatible type, exporting a `Node` from a non-`Node` script, signal args not Variant-compatible, `@global_class` on a type not deriving from `GodotObject`, generic script types). Use stable codes `GDJL0001…` mapped to the C# `GD0xxx` codes in a table in `docs/diagnostics.md`.

## Tests

- Unit tests for macro expansion (metadata snapshot tests) and every diagnostic.
- Integration: inspector-visible property list (via `get_property_list()` from GDScript) matches an expected list including hints/usage/groups; default revert values; RPC config dictionary; global class appears in `ProjectSettings.get_global_class_list()`.

Update parity rows 2.10, 3.13, 5.5–5.19.
````

## Anatomy of the Prompt

### "Phase 08 Already Provides the Base"

Read the first line of the body. Then read the second paragraph.

The first line still asks for the script authoring API in a new `julia/Godot/src/macros/` folder. That's the original plan. The second paragraph contradicts it:

> Phase 08 already provides the base: `@godot_class` (in `julia/Godot/src/object/scripting.jl`) handles plain `@export`, `@signal`, the `tool`/`global_class`/`abstract`/`icon` options and the `@tool`/`@global_class`/`@icon` wrappers. … Extend that expansion, … rather than starting over.

The agent wrote that paragraph at the end of phase 8. Its report listed *"a note in the phase 09 prompt on what already exists"* (chapter 11).

Here's why it mattered. Phase 8 had to build a working `@godot_class` just to attach scripts at all. Along the way, it built more of the authoring syntax than its prompt asked for. Without the note, phase 9 would have started from its own first line:

- a fresh `macros/` folder,
- a second `@godot_class`,
- two implementations to reconcile.

The note does four things:

- It says **what exists**, and where: `object/scripting.jl`.
- It says **how it works**: *"Body annotations are rewritten syntactically by `@godot_class` and are not standalone macros"*.
- It says **where to plug in**: *"feeding hints/usage/groups into `Runtime.ScriptField` and `Runtime.property_type`/`field_prop` (ADR 0008)"*.
- It says **what tests are still owed**: row 5.18's override tests.

The stale first line is a small, honest artifact. In practice, the agent followed the newer, more specific paragraph, and no `macros/` folder exists.

If you revise prompts as the code moves, also tidy the sentences your revision contradicts. Nobody who comes later, human or agent, should have to guess which one wins.

The general lesson: **downstream prompts need updating when upstream phases land.** The plan was written before any code existed. By the time phase 9 runs, the repository knows things the plan didn't. An agent that keeps the prompts current turns hindsight into foresight for the next session.

### A Target Syntax: "Refine, but Keep the Spirit"

The prompt doesn't describe the syntax in prose. It shows a complete example script.

Examples communicate API intent far better than lists of rules. You see at a glance what a decorated class looks like, where groups go, and how signals and RPCs read.

The parenthetical *"refine, but keep the spirit"* gives the agent explicit permission to change details that don't work in Julia. That permission turned out to be necessary: the example contains a line that **is not valid Julia**. More on that below.

### Three Kinds of Reference

The behavioral reference names three layers of the C# implementation:

- **Source generators** (`ScriptPropertiesGenerator`, `ScriptMethodsGenerator`, `ScriptSignalsGenerator`, …) tell the agent *what code to generate*.
- **Attributes** (`GodotSharp/Core/Attributes/`) tell it *what users can write*.
- **Docs** (`c_sharp_exports.rst`, `c_sharp_signals.rst`, `c_sharp_global_classes.rst`) tell it *what users are told*.

Requirement 1 then names the generated C# methods one by one: `GetGodotPropertyList`, `InvokeGodotClassMethod`, `SetGodotClassPropertyValue`, and so on.

That gives the agent a precise list of capabilities the Julia expansion must provide. The mechanism is completely different (macros instead of Roslyn), but the checklist is the same.

### Static Dispatch as a Requirement

> Generated dispatch must be static (no `getfield(obj, sym)` with runtime symbols on hot paths).

When GDScript reads `player.speed`, the engine asks the script instance for property `:speed`.

The easy implementation is `getfield(obj, name)`, with the name known only at runtime. That's dynamic, allocating and slow.

C#'s source generators emit a `switch` over constant names instead. The requirement asks for the Julia equivalent: generated code that compares against **constant symbols**, so the compiler can see every field type.

### Diagnostics with Stable Codes

Requirement 8 asks for macro-expansion-time errors that *"mirror the C# analyzer diagnostics"*, with *"stable codes `GDJL0001…` mapped to the C# `GD0xxx` codes in a table in `docs/diagnostics.md`."*

Three design choices are packed into that sentence:

- **Stable codes** can be searched, documented and referenced in bug reports. A message text can change. A code shouldn't.
- **A mapping to C#** lets a C# developer find the Julia counterpart of a rule they already know. It also lets the agent use C#'s analyzer list as a checklist.
- **A documentation table** gives every code a home where people will actually look.

The tests then ask for *"every diagnostic"* to be unit-tested. That turns the table into a contract, not a wish.

## What the Agent Built

[ADR 0009](../adr/0009-script-authoring.md) records the design.

As the note asked, the code extends what was already there: [`julia/Godot/src/object/scripting.jl`](../../julia/Godot/src/object/scripting.jl) and [`runtime/scripts.jl`](../../julia/Godot/src/runtime/scripts.jl).

### Every Export Form, in One Test Script

The integration test script [`tests/integration/scripts/Exports.jl`](../../tests/integration/scripts/Exports.jl) reads like a catalogue of the authoring API:

```julia
@enum Mode Walk Run Fly

@tool @godot_class mutable struct Exports <: Node2D
    @export_category("Movement")
    @export speed::Float64 = 300.0
    @export_range (0, 100, 1; or_greater = true) health::Int = 100
    @export_group("Visuals"; prefix = "visual_")
    @export visual_tint::Color = Color(1, 1, 1)
    @export_color_no_alpha visual_bg::Color = Color(0, 0, 0)
    @export_subgroup("Text")
    @export_multiline notes::String = ""
    @export_placeholder "Name..." title::String = ""
    @export_group("")
    @export_enum ("Small", "Large:5") size::Int = 0
    @export mode::Mode = Walk
    @export_flags ("Fire", "Water", "Earth") elements::Int = 0
    @export_flags_2d_physics layers::Int = 1
    @export_file ("*.png", "*.jpg") image::String = ""
    ...
    @export target::Node2D
    @export item::Item
    @export items::GDArray{Int}
    @export lookup::GDDictionary{String, Int}
    @export_storage hidden_state::Int = 3
    @export_custom (Godot.PROPERTY_HINT_PASSWORD, "", Godot.PROPERTY_USAGE_DEFAULT) password::String = ""
    @export_tool_button ("Reset", "Reload") reset_button = reset!
    last_shot::Int = 0
    @signal changed(old::Int, new::Int)
end
```

Hints are derived from types wherever C# derives them:

- A Julia `@enum` field gets an enum hint.
- A `Node2D` field gets a node-type hint.
- `Item`, a Julia `@global_class` resource, gets a resource-type hint with the global class name.
- Typed collections get element hints in C#'s `type/hint:hint_string` format.

Annotations override any of them.

### Generated Code That Is Static

For each script class, `@godot_class` generates `script_get_field`/`script_set_field!` methods.

These are chains of constant-symbol comparisons. They're the Julia version of C#'s generated `GetGodotClassPropertyValue`.

They're evaluated into `Godot.Runtime` with `Core.eval` ([`runtime/scripts.jl`](../../julia/Godot/src/runtime/scripts.jl)), so the bridge can dispatch on the concrete class. Method calls go through per-method thunks. Each thunk is compiled on first use and converts Variants straight to the declared parameter types.

The ADR's consequences sum up the result in one number:

> Script properties read from GDScript cost about 0.16 µs (was 1.1 µs with dynamic access).

That's roughly a sevenfold speedup. The requirement behind it was one sentence long.

### Signals, Name Tables, RPC and Static Methods

- **Signals** generate typed helpers in the script module: `emit_changed(self, old, new)` and `connect_changed(self, f)`. That's C#'s event parity. They're deliberately *not* exposed as engine methods.
- **Name tables** answer C#'s `SignalName.Hit`, `PropertyName.Speed` and `MethodName`. Julia can't add properties to a type, so `T.SignalName` is impossible. The ADR chose functions that return constant named tuples instead: `SignalName(Exports).changed === :changed`.
- **`@rpc`** wraps a function definition and feeds `_get_rpc_config`. The ADR records a parity decision here. Defaults follow C#'s `[Rpc]` (authority, call_remote, **reliable**, channel 0), not GDScript's, which defaults to unreliable.
- **Static methods** are functions whose first parameter is `::Type{T}`: `double_it(::Type{Exports}, x::Int) = 2x`. One deviation is recorded rather than hidden:

  > a GDExtension script class cannot intercept arbitrary `Script.method()` calls (there is no `callp` virtual on `ScriptExtension`), so the engine calls them through the method `JuliaScript.call_static(method, args...)`. C# calls them as `Script.Method()` because it is an engine module.

  Row 5.16 is `DONE` *with* that note. The ADR explains why it isn't a `GAP`: static methods are visible to and callable from the engine, just through a different call syntax.

  Telling "different spelling" apart from "missing capability" is exactly the kind of judgment a parity matrix needs.

### Diagnostics: Code, Table and Test

Every rule raises a `ScriptDiagnostic(code, message)` at macro expansion or class definition. It's reported as `res://File.jl:<line>: GDJLnnnn: message`.

[`docs/diagnostics.md`](../diagnostics.md) lists 18 codes. Each one shows its C# counterpart where one exists. Where the rule is Julia-specific (an unknown annotation, a field declared twice), it shows a dash:

```markdown
| GDJL0102 | GD0102 | the type of an exported member is not Variant-compatible |
| GDJL0107 | GD0107 | a class not derived from `Node` exports a `Node` member |
| GDJL0202 | GD0202 | a signal parameter type is not Variant-compatible |
| GDJL0301 | GD0301 | the element type of an exported typed collection (`GDArray{T}`, `GDDictionary{K,V}`, `Vector{T}`) is not Variant-compatible (C#: `[MustBeVariant]`) |
```

The page also lists which C# rules have no Julia counterpart (*"partial classes, delegates, indexers, explicit interface implementations"*). If you come from C#, that list is as useful as the table itself.

Three of those codes (0102, 0202, 0301) sit on the `isvarianttype` trait that phase 6 designed for exactly this purpose (chapter 9). That finished parity row 3.13.

## Where Reality Pushed Back

### The Target Syntax Was Not Valid Julia

The prompt's example contains this line:

```julia
    @export_range(0, 100, 1; or_greater = true) health::Int = 100
```

In Julia, `@m(args)` written *without a space* is a complete macro call. The parenthesized arguments are all the macro gets. The following `health::Int = 100` is then a syntax error.

The agent hit this as soon as it tried the syntax. ADR 0009 records the resolution:

> Arguments are a tuple separated by a space (`@export_range (0, 100, 1; or_greater = true) hp::Int = 100`), because `@m(args) decl` is not valid Julia syntax. Single arguments may be bare (`@export_placeholder "Name..." s::String`). Groups use the call form (`@export_group("Visuals"; prefix = "visual_")`).

**One space changes the meaning.** With it, the macro receives the tuple *and* the declaration as two arguments.

That's exactly the kind of refinement *"refine, but keep the spirit"* anticipated. Remember where the prompt came from: an agent wrote it in the project's first turn, in C#-flavored pseudo-Julia. The implementing agent ran the code and found the closest valid form.

The rule also went into the agent's memory notes: *"`@m(args) decl` is INVALID Julia syntax → use `@m (args) decl`"*.

Now compare the rest of the target syntax with what shipped:

| Prompt's target | Shipped form | Why |
|-----------------|--------------|-----|
| `@export_range(0, 100, 1; …) health::Int` | `@export_range (0, 100, 1; …) health::Int` | Julia macro call syntax |
| `@export_tool_button("Reset", "Reload") reset_action::Callable = Callable(reset!)` | `@export_tool_button ("Reset", "Reload") reset_button = reset!` | Tool buttons became *virtual* properties that return a `Callable`, not stored fields (ADR 0009) |
| `@rpc(:any_peer, :call_local, :reliable) function …` | `@rpc :any_peer :call_local :unreliable_ordered channel = 1 function …` | Macro arguments separated by spaces; options as `key = value` |
| `Player.SignalName.health_changed` | `SignalName(Player).health_changed` | Julia types cannot carry extra properties |

Every change preserves the intent and adapts to the language. Each one is recorded in the ADR. Each one is exercised in `Exports.jl`.

### Small Language Traps

The agent's memory notes from this phase list three more Julia details a model can easily get wrong:

- **A field named `export` is impossible.** `export` is a Julia keyword, so internal code uses `spec` instead.
- **Empty comprehensions infer `Union{}`.** `[x for x in ()]` has element type `Union{}`, so a later `push!` fails. Lists that start empty must be typed (`String[...]`).
- **Changing `julia/Godot` forces recompilation at Godot startup** (more than 60 seconds). Short-timeout integration runs then fail for reasons that have nothing to do with your change. The workflow fix: precompile first with `julia --project=julia/Godot -e "using Godot"`.

That last one is a **process** lesson, not a code lesson. An agent that runs tests with timeouts has to understand what its build system is doing. Otherwise it will chase phantom failures.

### Matrix Bookkeeping Before Work

The phase 9 report opens with corrections, not features:

> **Matrix corrections first:** rows 1.7 and 5.4 still listed only earlier phases, although their remaining work belongs to phases 15 and 12. I added those phases to their columns.

That's Step 2 of the driver (chapter 3) at work again.

A `PARTIAL` row whose remaining work belongs to a later phase must say so in its phase column. Otherwise the selection rule (*"lowest-numbered phase that still owns `TODO` or `PARTIAL` rows"*) would keep pointing back at phases that can't finish them.

### One Row Left for Phase 10

Row 5.11 (signals as C# events, including awaiting them) stayed `PARTIAL`.

The typed helpers were done. But `await`ing a signal belongs to phase 10's scheduler. As before, the report said which phase would finish it.

## Closing the Loop

**Unit tests** ([`julia/Godot/test/scripts.jl`](../../julia/Godot/test/scripts.jl)) assert one diagnostic per line:

```julia
        @test code("@godot_class struct A1 <: Node end") == "GDJL0001"
        @test code("@godot_class mutable struct A2 end") == "GDJL0401"
        @test code("@godot_class mutable struct A3{T} <: Node end") == "GDJL0402"
        ...
        @test code("@godot_class mutable struct A14 <: Resource\n @export n::Node\nend") == "GDJL0107"
        @test code("@godot_class mutable struct A15 <: Node\n @export_tool_button (\"Go\",) go = f\nend") == "GDJL0108"
```

The best test in the phase comes right after them. It:

- reads every source file,
- collects every `GDJLnnnn` code that appears anywhere,
- requires each one to have a row in the documentation table.

```julia
        # Every code raised by the implementation is documented.
        doc = read(joinpath(REPO_ROOT, "docs", "diagnostics.md"), String)
        srcdir = joinpath(pkgdir(Godot), "src")
        files = [joinpath(root, f) for (root, _, fs) in walkdir(srcdir) for f in fs
                 if endswith(f, ".jl") && !occursin("generated", root)]
        for c in unique(x.match for f in files for x in eachmatch(r"GDJL\d{4}", read(f, String)))
            @test occursin("| $c |", doc)
        end
```

Add a diagnostic to the code without documenting it, and the build fails.

**Documentation drift** is one of the most common failures of AI-assisted (and human) projects. For this table, it's impossible.

**Integration tests** check the result from the engine's point of view. The scripts project's `check_authoring` function in [`main.gd`](../../tests/integration/scripts/main.gd) reads `get_property_list()` from GDScript and compares hints, usage flags and groups:

```gdscript
	check(props["health"]["hint"] == PROPERTY_HINT_RANGE and props["health"]["hint_string"] == "0,100,1,or_greater", "export_range")
	check(props["Visuals"]["usage"] == PROPERTY_USAGE_GROUP and props["Visuals"]["hint_string"] == "visual_", "export_group")
	...
	check(ex_script.has_method("double_it") and ex_script.call_static("double_it", 21) == 42, "static method")
```

It also checks:

- values loaded from the `.tscn` and an `.tres`,
- the tool button,
- revert defaults,
- the RPC config dictionary,
- global and abstract classes in `ProjectSettings.get_global_class_list()`, with their icon,
- the `_get`/`_set`/`_get_property_list`/`_validate_property` overrides that the note at the top of the prompt said were still owed.

The phase 9 report counted 61 in-engine checks in the project and 371 `Godot` unit tests.

```powershell
julia --project=julia/Godot -e "using Godot"        # precompile first, then:
julia tests/integration/run.jl scripts
```

## Techniques to Reuse

- **Keep downstream prompts current.** When a phase builds more (or less) than planned, have the agent update the next phase's prompt: what exists, how it works, where to plug in, and what's still owed. Then tidy the sentences the update contradicts.
- **Show a target example, and allow refinement.** An example script communicates API intent. "Refine, but keep the spirit" lets the agent fix what doesn't work in the target language.
- **Map concepts, not mechanisms.** Name the capabilities of the reference (generated methods, analyzers). Let the agent choose the native mechanism (macros, load-time errors).
- **Give diagnostics stable codes, a table and a test.** A test that every code in the source is documented makes the table a contract.
- **Turn performance into a sentence.** "No `getfield(obj, sym)` with runtime symbols" bought a roughly 7× faster property read.
- **Distinguish different spelling from missing capability.** Record a deviation as `DONE` with a note when the capability exists. Reserve `GAP` for what truly can't be done.

## Try It Yourself

1. Ask the agent to add a new diagnostic, for example for an `@export_file` filter that doesn't start with `*`. Check that it adds the check in `object/scripting.jl`, a row in `docs/diagnostics.md`, and a unit test. Then delete the row from the documentation and watch the "every code is documented" test fail.
2. Open the **Ask** agent. Have it compare the target syntax in `.github/prompts/gdjl-09-authoring-macros.prompt.md` with `tests/integration/scripts/Exports.jl`, and explain each difference with a reference to ADR 0009.
3. Start a Julia REPL. Compare `Meta.parse("@export_range(0, 1) x::Int = 0")` with `Meta.parse("@export_range (0, 1) x::Int = 0")`. Then ask the agent to explain the difference in the parse trees, and why the prompt's syntax couldn't work.

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 2.10 | Cached `MethodName`/`PropertyName`/`SignalName` | DONE (per-script `SignalName(T)`/`PropertyName(T)`/`MethodName(T)` tables) |
| 3.13 | `[MustBeVariant]` | DONE (GDJL0102/0202/0301 on the `isvarianttype` trait) |
| 5.5 | `[ScriptPath]` / file ↔ class binding | DONE (GDJL0003/0004) |
| 5.6 | `[Export]` with every `PropertyHint` | DONE |
| 5.7 | Export groups, subgroups, categories | DONE |
| 5.8 | `[ExportToolButton]` | DONE (virtual `Callable` property; requires `@tool`, GDJL0108) |
| 5.9 | Node/Resource exports, typed collections, enums, flags | DONE |
| 5.10 | Default values for inspector revert | DONE |
| 5.11 | `[Signal]` → typed emit/connect helpers | DONE (helpers here; awaiting signals added in phase 10) |
| 5.12 | `[Tool]` | DONE |
| 5.13 | `[GlobalClass]`, `[Icon]` | DONE |
| 5.14 | Abstract global classes | DONE |
| 5.15 | `[Rpc]` | DONE (C# defaults) |
| 5.16 | Static methods visible to the engine | DONE (engine calls via `script.call_static`, ADR 0009) |
| 5.17 | Custom `Resource` subclasses in the inspector | DONE |
| 5.18 | `_get`/`_set`/`_get_property_list`/`_validate_property` | DONE (plus revert overrides) |
| 5.19 | Source-generator diagnostics | DONE (`GDJLnnnn` ↔ `GDnnnn`, every code unit-tested) |

---
[← Previous: The Script Language](11-script-language.md) · [Contents](README.md) · [Next: Signals and Async →](13-signals-async.md)
