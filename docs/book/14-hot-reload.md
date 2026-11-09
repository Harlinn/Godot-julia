# 14. Hot Reload: Working With the Language, Not Against It

**Hot reload** is the feature you notice most when it works, and resent most when it doesn't.

Here's the idea. You change a line in a script while the game runs, save, and the change takes effect without a restart. The player stays where it was. The score keeps its value. The enemy you were testing against is still mid-jump.

Godot's GDScript does this. So does C#: it rebuilds the project assembly, unloads the old one, and moves every scripted object's state to the new code.

Julia makes this unusually hard in one specific way: **it cannot redefine a struct.** Once `mutable struct Player` exists with certain fields, you cannot change its fields in the same module. You cannot unload compiled code either.

So a naive port of C#'s approach ("unload the old assembly, load the new one") has nothing to stand on.

Phase 11 is a case study in a few things:

- giving the agent the key insight up front, so it designs around a language constraint instead of fighting it;
- porting a **policy** (which state survives a reload and which doesn't), not just a mechanism;
- stating limitations honestly.

The phase builds on earlier work:

- the script model of chapter 11, which already evaluates each script into a fresh module per load (a decision made with this phase in mind);
- Callables (chapter 9);
- signals (chapter 13).

Phase 12's editor *Build* button triggers it.

## The Prompt

[`.github/prompts/gdjl-11-hot-reload.prompt.md`](../../.github/prompts/gdjl-11-hot-reload.prompt.md):

```markdown
---
name: gdjl-11-hot-reload
description: "Phase 11: hot reload of Julia scripts in the editor and running game with state preservation, matching C# assembly reload behavior."
agent: agent
---
Implement script hot reload. Follow the [project instructions](../copilot-instructions.md). Behavioral references: `csharp_script.cpp` (`CSharpLanguage::reload_assemblies`, `_reload_scripts`, `CSharpScript::reload`, state backup/restore of instances and placeholders, `assembly_reload_attempts`), `GodotPlugins/Main.cs` (collectible `AssemblyLoadContext` unload/reload), and `ScriptSerializationGenerator` (`SaveGodotObjectData` / `RestoreGodotObjectData`).

## Requirements

1. **Triggers**: editor file change / save (`_reload_tool_script`, `_reload_all_scripts`, `_reload_scripts`), the "Build" action (phase 12), and live-editing a running game via the remote debugger's script reload.
2. **Generations**: each reload evaluates the script into a new generation module. The old type is retired; instances are migrated to the new type (Julia cannot redefine structs — create new instances of the new type bound to the same native object).
3. **State transfer**: before reload, serialize every live instance's fields (exported and non-exported), per C# rules: values that are Variant-compatible are transferred by Variant, Julia-only values transferred when the field still exists with a compatible type; dropped fields are discarded; new fields get defaults. Signal connections made through Julia callables are restored where the target still exists.
4. **Shared packages**: when user packages (`using MyGameLib`) change, reload them (Revise.jl-based tracking where available, otherwise re-load in a fresh module chain) before reloading dependent scripts. Document limitations versus .NET ALC unloading.
5. **Failure handling**: if a script fails to load, keep instances as placeholders preserving their state and report errors (C# behavior when the build fails); retry up to `julia/project/reload_attempts`.
6. **Tool scripts**: running `@tool` instances in the editor reload in place without losing inspector state.
7. **Memory**: old generations become collectible once no instances reference them; verify no unbounded growth.

## Tests

- Integration: modify a script file during a headless run (driven by the test harness), trigger reload, assert field values preserved and new method behavior active.
- Removing a field / changing its type does not crash.
- Syntax error during reload keeps old state as placeholders; fixing it restores the instances.

Update parity rows 7.1–7.5.
```

## Anatomy of the Prompt

### The Key Insight, in a Parenthesis

The most important words in the prompt sit in requirement 2's parenthesis:

> (Julia cannot redefine structs — create new instances of the new type bound to the same native object)

Without them, an agent that knows C# hot reload well would plausibly try to imitate it. It might unload the old code, reload the module, or experiment with ways to redefine the struct in place.

Each of those is a dead end. And the agent would discover that only after a lot of work.

The parenthesis states the constraint *and* the strategy that works with it:

- Each reload creates a new module containing a new type with the new fields.
- Each live instance gets a *new* Julia struct of the new type, attached to the *same* engine object.
- The engine object never notices that its Julia half has been replaced.

That's the difference between a prompt that describes a goal and one that **transfers understanding**. If you know where the hard constraint is, say so. The agent will find out anyway, but finding out costs a session.

### Three References, Three Roles

The behavioral reference names three parts of C#'s implementation. Each one covers a different aspect of the problem:

- `CSharpLanguage::reload_assemblies` and friends: **orchestration**. Which instances to visit, in which order, what to do when the build fails, and how many times to retry (`assembly_reload_attempts`).
- The collectible `AssemblyLoadContext` in `GodotPlugins/Main.cs`: **unloading**. This is the thing Julia cannot do. Naming it lets the agent explain what replaces it.
- `ScriptSerializationGenerator` (`SaveGodotObjectData`/`RestoreGodotObjectData`): **the state-transfer policy**. Which fields survive, how they're converted, and what happens to delegates.

### Porting a Policy, Not Just Code

Requirement 3 is a policy statement:

- values are transferred when the field still exists with a compatible type;
- dropped fields are discarded;
- new fields get defaults;
- signal connections made through Julia callables are restored where the target still exists.

Your experience of hot reload is defined by these rules, not by the machinery.

"I renamed a field and it reset to its default" is fine if that's the documented rule. It's infuriating if it's an accident.

Writing the policy into the prompt makes the behavior a **design decision**. Otherwise it would be an emergent property of whatever the agent happened to build first.

### "Document Limitations Versus .NET ALC Unloading"

Requirement 4 ends with an instruction to write down what can't be matched.

Julia cannot unload packages or free compiled code. C# can, via collectible assembly load contexts.

Asking for the limitations in advance tells the agent something important: "here is what we can't do, and why" is a **deliverable**, not an admission of failure.

### Failure Handling as a First-Class Path

Requirement 5 says what happens when the new code *doesn't load*:

- keep the instances,
- preserve their state,
- report the error,
- retry.

You'll hit this path several times an hour. You save mid-edit, with a syntax error. Get it wrong, and you lose game state on every typo.

The test list makes sure it's covered:

> Syntax error during reload keeps old state as placeholders; fixing it restores the instances.

### Memory as a Requirement

Requirement 7, *"old generations become collectible … verify no unbounded growth"*, would be easy to forget.

Picture a reload that works perfectly but leaks a module, a type and hundreds of methods each time. A long editing session gets slower and slower.

Asking for verification turns a vague worry into a test.

## What the Agent Built

[ADR 0011](../adr/0011-hot-reload.md) records the design. [`julia/Godot/src/runtime/reload.jl`](../../julia/Godot/src/runtime/reload.jl) implements it.

The file's header names all three references. It also names a fourth that the agent added on its own: GDScript's `reload_scripts`.

```julia
# Hot reload of Julia scripts. Behavior ported from CSharpLanguage::reload_assemblies / CSharpScript::reload
# (modules/mono/csharp_script.cpp), ScriptSerializationGenerator and DelegateUtils (Godot.SourceGenerators,
# GodotSharp/Core/DelegateUtils.cs), and GDScriptLanguage::reload_scripts (modules/gdscript/gdscript.cpp)
# (MIT, Godot contributors). Design: ADR 0011.
```

That GDScript reference matters. The design ended up closer to GDScript than to C#.

The ADR's context section puts it this way: C# rebuilds every scripted object, whereas *"GDScript keeps its instances and remaps their members."* Julia's constraints made the GDScript model the natural fit.

### Triggers and Dependents

Godot has several reload entry points:

- `_reload_scripts`, from the remote debugger's live edit,
- `_reload_all_scripts`,
- `_reload_tool_script`,
- `JuliaScript::_reload`.

All of them funnel into one function, `reload_scripts!`.

For tests, and for phase 12's *Build* button, `JuliaRuntime.reload_scripts(paths)` does from GDScript what the debugger's message does. Reloading unchanged, valid source is a no-op.

Scripts that inherit from or reference the edited script (via `script_type`) reload with it, in dependency order, because their types refer to the old class. Each load records its dependencies, so the order can be computed.

### Migration in Place

For each live instance, the engine-side script instance stays where it is. Only its Julia struct changes.

`transfer_state` builds a new-generation struct and copies every field that still exists. Field initializers run, but `_init` does not, as with GDScript's soft reload:

```julia
"A new-generation struct for the object of `si`: field initializers run, then every field that still exists takes its old value."
function transfer_state(si::ScriptInstance, info::ScriptClassInfo, replaced::IdDict{Any, Any})
    obj = Base.invokelatest(construct_instance, info, si.owner)
    old = si.obj
    OT = typeof(old)
    for f in info.fields
        hasfield(OT, f.name) || continue                    # new field: default
        v = Base.invokelatest(migrate_value, getfield(old, f.name), f.type, replaced)
        v === NO_TRANSFER || setfield!(obj, f.name, v)      # type changed incompatibly: default
    end
    return obj
end
```

The two short comments carry the policy from requirement 3: *new field: default*, and *type changed incompatibly: default*.

`migrate_value` handles the rest:

- Values of the new type pass through unchanged.
- Convertible values are converted (`Int` to `Float64`).
- Vectors are migrated element by element.
- Enums and structs *declared in the script itself* are rebuilt as the same-named type of the new generation:

```julia
    # A struct declared in the script itself: rebuild it as the same-named struct of the new generation.
    S = typeof(v)
    if is_generation_type(S) && T isa DataType && isconcretetype(T) && nameof(T) === nameof(S) &&
       fieldnames(T) == fieldnames(S) && !(T <: GodotObject)
```

That last case exists because of the module-per-generation design. A `struct Stats` declared next to the script class is a *different type* in each generation.

Without the rebuild, every reload would reset such fields to their defaults.

### A Deliberate Deviation: No Variants

Requirement 3 said Variant-compatible values *"are transferred by Variant"*, as C# does. The agent didn't do that, and the ADR explains why:

> Values move directly in memory, not through Variants (C# serializes because the old assembly goes away), so Julia-only values survive.

C# *must* serialize. Once the old assembly is unloaded, objects of its types can no longer exist.

Julia never unloads anything. The old struct is still there during migration, so values can be moved directly.

That's simpler, faster and *more* capable. A `Dict`, a closure, or any Julia value with no Variant representation survives a reload too.

Here's the lesson. The prompt copied a **mechanism** (serialization) that was a consequence of C#'s constraints, not a goal in itself. The agent recognized the difference. It kept the goal (state survives) and dropped the mechanism.

That's the kind of deviation you want, provided it's written down. Here, it is.

### References and Callables

Two more kinds of state need updating:

- **Fields of other instances** that pointed at a migrated struct are re-pointed at its replacement, including elements of `Vector` fields. An enemy that stored a reference to the player still has a valid reference after the player's script reloads.
- **Connected Julia closures** are re-targeted. Closures defined in the old generation become the same-named closures of the new generation, with captured instances replaced.

The ADR notes the Julia detail that makes closure re-targeting possible: *"Julia 1.13 names closures per enclosing function (`#arm##0#arm##1`), so names are stable across edits that do not reorder closures in a function."*

A closure whose code no longer exists is disabled with a warning, *"as C# drops delegates it cannot deserialize."*

Re-targeting a closure means swapping the Julia function behind a Godot `Callable` without Godot noticing. But Godot has stored the Callable's hash in its connection maps, so the hash must not change.

This is why phase 11 changed phase 6's design (chapter 9). Custom Callables now pin a mutable box with a hash fixed at creation:

```julia
"What a custom Callable pins: the Julia callable (swapped on hot reload) and the hash Godot saw at creation."
mutable struct JuliaCallable
    f::Any
    const hash::UInt32
end
```

### Failure: Suspended Instances

If a script, or one it depends on, fails to load, its instances are **suspended**.

They keep their state, which stays readable and writable as properties in the inspector. But no user code runs:

- no methods,
- no notifications,
- no `_get`/`_set`.

A later successful reload migrates them.

Failed reloads from disk are retried once per frame, up to the new project setting `julia/project/reload_attempts`. It defaults to 3, matching C#'s `dotnet/project/assembly_reload_attempts`.

The ADR records one more deviation:

> `ScriptInstanceExtension` cannot become a `PlaceHolderScriptInstance` (the engine `static_cast`s placeholders), so suspended instances report `is_placeholder() == false`.

The prompt said *"keep instances as placeholders"*. But Godot's engine casts placeholder instances to its own internal type, so an extension's instance can't pretend to be one.

So the agent implemented the *behavior* of placeholders (state kept, no code run). It also wrote down why it couldn't use the *mechanism*. Parity row 7.5 carries the note.

### Retiring Old Generations

This is the closest Julia gets to unloading an assembly.

After each reload, generation modules that no loaded script and no live instance uses are **retired**. Every method they defined is deleted from Julia's global method table, and their class records are dropped:

```julia
    dead = Set{Module}(m for m in keys(GENERATIONS) if !(m in used) && !is_precompiled(m))
    isempty(dead) && return 0
    ms = Method[]
    Base.visit(Core.methodtable) do m
        m isa Method && m.module in dead && push!(ms, m)
    end
    foreach(Base.delete_method, ms)
```

Why delete methods at all?

Because every script generation adds methods to *shared* generic functions, such as `Godot._ready(self::Player)`, `getproperty` and the generated helpers. Without deletion, those functions' method tables would grow with every reload, and dispatch would slowly get more expensive.

The agent learned something along the way: deleted methods stay visible to `Base.visit`. That's one reason retired modules are removed from the generation registry, so they're never swept again. The lesson went into its memory notes.

According to the ADR, sweeping the method table costs about 40 ms per reload (55,000 methods). That's an acceptable pause when you've just saved a file.

### Honest Limitations

Requirement 4 asked for limitations versus .NET's unloading. The ADR's last section delivers them plainly:

> - **Compiled code is never freed in Julia.** Retiring removes methods and records, but each reload leaks the old generation's compiled code and type objects … This is small, but it grows with the number of reloads in a session.
> - **Tasks keep the old code.** Godot tasks (`godot_task`) suspended in old code resume on deleted methods and fail with a reported `MethodError`. …
> - **Package limits.** Struct redefinitions in packages need Revise's own limits or a restart: Julia cannot unload a package the way an ALC unloads assemblies.

The phase 11 report added one more. A less honest report would have left it out:

> Without Revise, changed packages are not reloaded, and the Revise path itself is untested because Revise isn't installed here.

The Revise integration exists: `Revise.revise()` runs before scripts reload, if Revise is loaded. But the agent didn't claim it works. It said exactly what was and wasn't verified.

## Where Reality Pushed Back

Phase 11 had fewer surprises than the earlier phases.

That's largely because the hard design questions were settled before it started. Phase 8 chose a module per generation, and the prompt stated the struct-redefinition constraint.

The surprises that did come were about the boundary with Godot:

- **Placeholders could not be impersonated** (see above). The engine's `static_cast` made the mechanism unavailable, so the behavior was rebuilt on Julia's side.
- **Callable hashes had to stay fixed**, which reshaped phase 6's custom-callable design.
- **The in-editor save path** for tool scripts could not be tested headlessly in phase 11. Row 7.3 stayed `PARTIAL` with the note *"same migration path, tested headless; the in-editor save path is checked in phase 12"*. Phase 12's headless editor test closed it.

One more detail from the agent's memory notes is worth knowing if you extend this code. Script instance fields `obj` and `info` are mutable, with a `suspended` flag, and *"user code only via `user_method(si, name)`"*.

Every call into user code goes through one function that checks for suspension. Centralizing that check is what makes "no user code runs while suspended" a **guarantee** rather than a hope.

## Closing the Loop

The integration project [`tests/integration/reload/`](../../tests/integration/reload) drives reload the way the editor and the remote debugger do.

It rewrites `res://Mover.jl` from a series of versions in [`versions/`](../../tests/integration/reload/versions) and calls `JuliaRuntime.reload_scripts` after each one.

Version 2 of the script adds a field, changes methods and changes a closure:

```julia
@godot_class mutable struct Mover <: Node
    @export speed::Float64 = 1.0
    count::Int = 0
    label::String = "v2"
    mode::Mode = Idle
    stats::Stats = Stats(0)
    extra::Int = 42
    @signal moved(n::Int)
end

version(self::Mover) = 2
...
arm(self::Mover) = (connect(self, :moved, n -> (self.label = "v2:$n"; nothing)); nothing)
```

The driver [`main.gd`](../../tests/integration/reload/main.gd), tagged `# parity: 7.1-7.5`, checks every rule of the policy:

```gdscript
	write_version("v2")
	reload()
	check(m.call("version") == 2, "new method behavior after reload")
	check(m.speed == 2.5 and m.count == 2, "exported and plain fields preserved")
	check(m.extra == 42, "new field takes its default")
	check(m.call("stats_hits") == 2, "struct declared in the script is transferred")
	check(m.call("mode_name") == "Run", "enum declared in the script is transferred")
	check(m.label == "v1", "field value kept over the new initializer")
	m.call("step")
	m.emit_signal("moved", 3)
	check(m.label == "v2:3", "closure connected by the old version runs the new code on the migrated instance")
```

The later versions push on the edge cases:

- **Version 3** removes a field and changes a type incompatibly.
- **Version 4** has a syntax error. The instance must keep its state and run no code, and so must the dependent script `Fancy.jl`.
- **Version 5** fixes the file *without* an explicit reload. Two frames later, the retry mechanism must have picked it up:

```gdscript
	write_version("v5")
	await get_tree().process_frame
	await get_tree().process_frame
	check(m.call("version") == 5 and m.speed == 4.0 and m.extra == 42, "retry picks up the fixed file and restores the instance")
```

Finally, requirement 7 becomes four numbers. The test records:

- the count of generation modules,
- class records,
- methods of a shared generic function,
- pinned values.

It then reloads six more times, alternating versions, and requires all four to be unchanged:

```gdscript
	check(jl("Godot.Runtime.live_generation_count()") == gens, "generation modules retired (%s)" % gens)
	check(jl("length(Godot.Runtime.SCRIPT_CLASSES)") == classes, "class records retired")
	check(jl("length(methods(Godot.godot_class_name))") == meths, "methods of old generations deleted")
	check(jl("Godot.Runtime.pin_count()") == pins, "no pinned values leak")
```

The phase 11 report counted 26 checks in this project, passing on three consecutive runs. It also added 21 new unit tests in `julia/Godot/test/reload.jl`.

```powershell
julia tests/integration/run.jl reload
```

## Techniques to Reuse

- **State the hard constraint and the strategy.** "Julia cannot redefine structs — create new instances bound to the same native object" saves the agent a dead-end session.
- **Port the policy, not the mechanism.** Copy *what* survives a reload. Let the target language decide *how*. Here, direct transfer beats serialization.
- **Ask for limitations up front.** Make "what we can't match, and why" a deliverable.
- **Make the failure path a feature.** Specify what happens on a syntax error, and test that fixing the file restores everything.
- **Turn "no unbounded growth" into numbers.** Count modules, records, methods and pins before and after repeated reloads. It's the same idea as chapter 13's monotonic leak checks.
- **Centralize the guard.** One entry point for user code (`user_method`) turns "no code runs while suspended" into a guarantee.

## Try It Yourself

1. Run `julia tests/integration/run.jl reload`. Then add a `Mover_v7.jl.txt` that changes `count::Int` to `count::Float64`, and add a check that the value is converted rather than reset. Before you run it, predict the outcome from `migrate_value`.
2. Open the **Ask** agent and ask: *"Why does Godot-julia's hot reload move values directly instead of serializing them through Variants like C#? What would break if it serialized?"* Check the answer against ADR 0011.
3. Ask the **Plan** agent to design a test for the Revise integration that the phase 11 report says is untested. What would the test project need? How would it avoid a network dependency in CI?

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 7.1 | Reload after build | DONE (all reload entry points; dependents reloaded; old generations retired; compiled code not freed, ADR 0011) |
| 7.2 | Serialize/restore instance state | DONE (fields, exports, script enums/structs; removed/retyped fields handled; references and connected closures re-targeted) |
| 7.3 | Tool scripts reload in the editor | DONE (in-editor save path checked in phase 12's headless editor test) |
| 7.4 | `reload_attempts` setting | DONE (`julia/project/reload_attempts`) |
| 7.5 | Graceful failure when the build is broken | DONE (instances suspended with their state; deviation: not engine `PlaceHolderScriptInstance`s, ADR 0011) |

---
[← Previous: Signals and Async](13-signals-async.md) · [Contents](README.md) · [Next: Editor Integration →](15-editor-integration.md)
