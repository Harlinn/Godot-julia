# 11. The Script Language: Exhaustive Checklists and Thin Shims

Phase 8 is the moment the project becomes visible to a game developer.

Before it, Julia could drive Godot from the outside: construct nodes, call methods, read properties. After it, a `.jl` file *is* a Godot script. You attach it to a node in the editor or in a `.tscn` scene file, just as you would a `.gd` or `.cs` file.

From then on:

- Godot calls its `_ready` and `_process`,
- GDScript can call its methods and connect to its signals,
- the inspector shows its exported fields.

To get there, the extension has to implement Godot's **script-language interface**. That interface has three parts:

- `ScriptLanguageExtension` for the language as a whole,
- `ScriptExtension` for each script file,
- a table of callbacks for each script *instance*.

Together that's more than a hundred virtual methods and callbacks. Each one has a contract, defined by how the engine and editor use it.

This chapter shows you how a prompt makes sure an agent implements *all* of them, and where the logic for each one lives.

The phase builds directly on the object model (chapter 10): a script instance's Julia struct becomes the wrapper of its engine object. Several later phases plug into what this phase creates:

- phase 9's authoring macros,
- phase 11's hot reload,
- phase 12's editor tools,
- phase 13's debugger hooks.

## The Prompt

[`.github/prompts/gdjl-08-script-language.prompt.md`](../../.github/prompts/gdjl-08-script-language.prompt.md):

```markdown
---
name: gdjl-08-script-language
description: "Phase 8: implement JuliaLanguage/JuliaScript/script instances via ScriptLanguageExtension so .jl files attach to nodes like C# scripts."
agent: agent
---
Register Julia as a Godot script language. Follow the [project instructions](../copilot-instructions.md). Behavioral reference: `modules/mono/csharp_script.h/.cpp` (`CSharpLanguage`, `CSharpScript`, `CSharpInstance`, `PlaceHolderScriptInstance` usage) and `Bridge/ScriptManagerBridge.cs`, `Bridge/CSharpInstanceBridge.cs`. C++ classes in `native/` are thin shims that forward to `Godot.Runtime` in Julia.

## Native Shims (`native/src/`)

1. `JuliaLanguage : ScriptLanguageExtension`, registered with `Engine::register_script_language` and unregistered on deinit. Implement every virtual; for each, match `CSharpLanguage` behavior. Notable ones:
   - `_get_name` = "Julia", `_get_type` = "JuliaScript", `_get_extension` = "jl", `_get_recognized_extensions` = `["jl"]`.
   - `_get_reserved_words`, `_is_control_flow_keyword`, `_get_comment_delimiters` (`#`, `#= =#`), `_get_doc_comment_delimiters`, `_get_string_delimiters` (`"`, `"""`, `` ` ``).
   - `_validate` → parse with `JuliaSyntax` and lower; return errors/warnings with line/column.
   - `_has_named_classes`, `_handles_global_class_type`, `_get_global_class_name` (read `@global_class` without executing the file — parse-only).
   - `_make_template`, `_get_built_in_templates`, `_is_using_templates`, `_preferred_file_name_casing` (PascalCase like C#).
   - `_can_make_function`/`_make_function`/`_find_function` (signal connection dialog inserts handler stubs — C# returns false for make; match or exceed).
   - `_open_in_external_editor`/`_overrides_external_editor` (phase 12), `_debug_*` (phase 13), `_reload_*` (phase 11), `_thread_enter/_thread_exit`, `_frame` (pumps the Julia main-thread scheduler; phase 10).
2. `JuliaScript : ScriptExtension`: implement every virtual (`_can_instantiate`, `_get_instance_base_type`, `_instance_create`, `_placeholder_instance_create`, `_is_tool`, `_is_valid`, `_is_abstract`, `_get_global_name`, `_get_base_script`, `_inherits_script`, `_has_method`, `_has_static_method`, `_get_method_info`, `_get_script_method_list`, `_get_script_property_list`, `_get_script_signal_list`, `_has_script_signal`, `_has_property_default_value`, `_get_property_default_value`, `_update_exports`, `_get_constants`, `_get_members`, `_get_member_line`, `_get_rpc_config`, `_get_documentation`, `_get_class_icon_path`, `_reload`, `_get_source_code`/`_set_source_code`).
3. `ResourceFormatLoaderJulia` / `ResourceFormatSaverJulia` for `.jl`.
4. Script instances via `script_instance_create3` with a full `GDExtensionScriptInstanceInfo3` table whose callbacks dispatch into Julia (`set`, `get`, `get_property_list`, `property_can_revert`, `property_get_revert`, `validate_property`, `get_owner`, `get_property_state`, `get_method_list`, `has_method`, `get_method_argument_count`, `call`, `notification`, `to_string`, `refcount_incremented/decremented`, `is_placeholder`, `get_language`, `free`).
   The Julia struct for an instance becomes the object's wrapper via `Godot.bind_wrapper!` (phase 07, ADR 0007), so engine calls that return the object (`get_parent`, `get_node`, signal arguments) yield the user's struct. `refcount_incremented/decremented` follow the same strong/weak rules as the instance binding.

## Julia Side (`Godot.Runtime`)

1. **Script loading**: evaluate a `.jl` file into a fresh module (`Module(:Script_<hash>_<gen>)`) with `using Godot` pre-imported; locate exactly one `@godot_class` whose name equals the file's base name; extract metadata produced by the phase 09 macros. Report violations as script errors with file:line.
2. **Inheritance**: base type is either a Godot class (abstract type) or another Julia script class (`res://` path) — support script-to-script inheritance like C# class inheritance.
3. **Dispatch**: `call` resolves method name → Julia function once per script generation and caches it; virtual engine callbacks (`_ready`, `_process`, `_physics_process`, `_input`, `_unhandled_input`, `_notification`, `_get`, `_set`, `_get_property_list`, `_validate_property`, `_to_string`, ...) are found by `hasmethod(Godot._ready, Tuple{T})`. Unimplemented virtuals must not be reported to the engine (so Godot skips them, as with C#).
4. **Arguments**: converted from `Variant` per declared Julia argument types; arity/type errors produce Godot call errors (`GDEXTENSION_CALL_ERROR_*`), not crashes.
5. **Placeholders**: in the editor, non-`@tool` scripts get placeholder instances exposing exported properties with defaults.

## Tests

- Attach a `.jl` script to a node in a headless scene: `_ready`, `_process`, `_notification` run; exported property set in `.tscn` is applied.
- GDScript calls a Julia method, reads/writes a Julia property, and connects to a Julia-declared signal.
- Julia script inheriting another Julia script.
- Syntax error in a script reports file:line and does not crash.

Update parity rows 2.11, 4.3, 4.9, 5.1–5.4, 5.18, 8.6, 8.7.
```

## Anatomy of the Prompt

### Exhaustive Checklists Beat "Implement the Interface"

This prompt does something unusual: it *enumerates the interface*. It lists:

- every `ScriptExtension` virtual by name,
- every script-instance callback by name,
- the notable `ScriptLanguageExtension` virtuals, with their expected values.

Why not just say "implement `ScriptLanguageExtension`"?

Because an agent working against tests implements what the tests touch. The obvious tests touch maybe a third of the interface.

Attach a script, run `_ready`, call a method: that exercises loading, instance creation and `call`. It never touches `_get_member_line`, `_has_property_default_value`, `_get_rpc_config` or `_get_doc_comment_delimiters`.

Those still matter:

- to the editor (go-to-definition, the inspector's revert arrows),
- to multiplayer,
- to documentation.

A headless test of phase 8 would notice none of them. An **enumerated checklist** turns every omission into a visible gap in the agent's report, instead of an invisible one.

The instruction attached to the list, *"Implement every virtual; for each, match `CSharpLanguage` behavior"*, turns each item into a small porting task with a reference answer.

### Specific Values Where They Matter

Some items carry their expected values inline:

- `_get_name` = `"Julia"`,
- `_get_extension` = `"jl"`,
- comment delimiters `#` and `#= =#`,
- string delimiters `"`, `"""` and `` ` ``,
- file-name casing PascalCase.

An agent *could* derive these facts. It could also get them subtly wrong now and then (Julia's block comment syntax, for instance). Stating each one costs a single line and removes the risk.

### Forward References Keep the Interface Whole

Several virtuals belong to later phases:

- `_open_in_external_editor` (phase 12),
- `_debug_*` (phase 13),
- `_reload_*` (phase 11),
- `_frame` (phase 10).

The prompt lists them anyway, with the owning phase in parentheses.

So the agent implements *every* virtual now, as a stub that forwards to Julia. It also knows exactly who will fill in each stub. Nothing gets silently dropped because "that's for later".

When those phases arrive, they find the hook already wired. They only need to write the Julia handler.

### "Thin Shims That Forward to `Godot.Runtime`"

The opening paragraph applies the architecture rule from the project instructions (*"thin C++ … Everything that can live in Julia lives in Julia"*) to this phase: *"C++ classes in `native/` are thin shims that forward to `Godot.Runtime` in Julia."*

For an agent, this split decides where iteration is cheap:

- Every change to C++ means a native rebuild and a Godot restart.
- Every change to Julia can be tested in a Julia process, and later even hot-reloaded.

By pushing logic into Julia, the prompt keeps most of the hundred-odd behaviors in the **fast loop**.

### The Script Model, Stated Up Front

The Julia-side section fixes the **script model** in a few sentences:

- each file is evaluated into a **fresh module** per generation;
- the file must contain **exactly one** `@godot_class` named after the file;
- violations are reported as **script errors with file:line**.

These rules come straight from the project instructions (*"one `.jl` file = one script = one `@godot_class` whose name matches the file name"*). They were chosen with phase 11 in mind.

Julia can't redefine a struct in place. Reloading a script therefore means evaluating it into a *new* module. If you design loading that way from the start, hot reload swaps generations instead of fighting the language.

### A Parity Detail with a Performance Effect

> Unimplemented virtuals must not be reported to the engine (so Godot skips them, as with C#).

Here's why that sentence matters:

- If a script reports that it has a `_process` method, Godot calls it every frame for every instance.
- If it doesn't, Godot skips the call.

A script language that answered "yes" to every virtual would be correct, and slow: thousands of empty calls per frame across a scene. One sentence in the prompt prevents an expensive default.

### Errors, Not Crashes

Requirement 4 on the Julia side says arity and type mismatches must produce **Godot call errors**.

Say GDScript calls `player.take_damage("oops")`. The caller should see a normal Godot error, the same one it would get from a GDScript or C# method. Not a crash. Not a Julia exception escaping into C++.

The project-wide rule against exceptions crossing C frames already forbids the crash. This sentence tells the agent what to do instead.

### A Sentence Added by an Earlier Phase

The paragraph about `bind_wrapper!` under item 4 wasn't in the original prompt.

Phase 7 added it. It built `bind_wrapper!` but couldn't connect it to script instances yet (chapter 10). When phase 8 ran, the requirement was waiting for it, with a pointer to ADR 0007.

## What the Agent Built

[ADR 0008](../adr/0008-script-language.md) records the design. The pieces are split just as the prompt intended:

- about 500 lines of C++ in [`native/src/julia_script.cpp`](../../native/src/julia_script.cpp),
- about 2,000 lines of Julia in [`runtime/scripts.jl`](../../julia/Godot/src/runtime/scripts.jl), [`runtime/instances.jl`](../../julia/Godot/src/runtime/instances.jl), [`runtime/bridge.jl`](../../julia/Godot/src/runtime/bridge.jl) and [`object/scripting.jl`](../../julia/Godot/src/object/scripting.jl).

### Thin Shims, Literally

[`julia_script.h`](../../native/src/julia_script.h) declares `JuliaLanguage`, `JuliaScript`, `ResourceFormatLoaderJulia` and `ResourceFormatSaverJulia`. Together they override more than a hundred virtual methods.

Static facts (name, extension, reserved words, delimiters) are answered in C++. Almost everything else is one line that forwards to Julia through a small variadic helper:

```cpp
// Calls handler `p_method` of Godot.Runtime's script bridge with `p_self`'s engine object as `self`.
template <typename... Args>
Variant jl(const char *p_method, const Object *p_self, const Args &...p_args) {
	const Variant args[] = { Variant(p_args)..., Variant() };
	const Variant *ptrs[sizeof...(Args) + 1] = {};
	for (size_t i = 0; i < sizeof...(Args); i++) {
		ptrs[i] = &args[i];
	}
	Variant ret;
	JuliaHost::get_singleton().script_call(p_method, p_self ? p_self->_owner : nullptr, ptrs, int64_t(sizeof...(Args)), ret);
	return ret;
}
```

With that helper, a virtual such as instance creation reads:

```cpp
void *JuliaScript::_instance_create(Object *p_for_object) const {
	return reinterpret_cast<void *>(uintptr_t(as_int(jl("script_instance_create", this, object_handle(p_for_object)), 0)));
}
```

The `as_int`/`as_bool`/`as_string` helpers tolerate a `nil` result. That's what comes back when Julia isn't running, or when a handler failed and reported its error.

So the shims degrade gracefully instead of crashing the editor. That honors phase 2's "editor still usable" rule.

### One Entry Point: the Script Bridge

All of those calls go through a single new entry in the C++/Julia function table. Adding it bumped the native ABI to v3:

```c
void (*script_call)(const char *method, void *self, const void *const *args, int64_t argc, void *r_ret);
```

On the Julia side, `method` names a handler in a dictionary, [`Godot.Runtime.BRIDGE`](../../julia/Godot/src/runtime/bridge.jl):

```julia
const BRIDGE = Dict{Symbol, Function}(
    :language_init => language_init,
    :language_finish => language_finish,
    :language_frame => language_frame,
    ...
    :script_instance_create => script_instance_create,
    ...
)
```

Today it has about 55 handlers, including the reload, editor and debugger hooks that later phases filled in. This mirrors C#'s `ScriptManagerBridge`.

ADR 0008 explains why one generic entry point beats a function pointer per virtual: *"One generic entry point keeps the C ABI stable while handlers evolve."*

In practice, adding a handler in phases 11–13 meant adding a dictionary entry in Julia. No ABI bump. No C++ rebuild for the dispatch itself.

A small optimization shows attention to the **hot path**. The C++ side always passes string *literals*, so their addresses are stable. Julia caches the address-to-symbol conversion:

```julia
# The native side passes string literals, so their addresses identify the handler.
const BRIDGE_NAMES = Dict{Ptr{UInt8}, Symbol}()
```

### The Class Model

Take this script from the integration tests ([`tests/integration/scripts/Player.jl`](../../tests/integration/scripts/Player.jl)):

```julia
@godot_class mutable struct Player <: Node2D
    @export speed::Float64 = 300.0
    @export label::String = "player"
    health::Int = 100
    ready_called::Bool = false
    process_frames::Int = 0
    notifications::Vector{Int} = Int[]
    @signal hit(damage::Int)
end

function Godot._ready(self::Player)
    self.ready_called = true
    nothing
end
```

According to ADR 0008, it defines two Julia types:

- An **abstract** `Player <: Node2D`. You dispatch on it, and other scripts can extend it.
- A **concrete** `mutable struct var"Player#Instance" <: Player`. It holds the native pointer and every field, inherited ones first.

A few more rules apply:

- Fields with defaults get per-instance initializers.
- Fields declared as an engine type without a default become `Union{Nothing, T}`, because C# reference fields start out null.
- `Player()` creates the engine object with the script attached, like C#'s `new Player()`.

**Script-to-script inheritance** falls out of the abstract types ([`Boss.jl`](../../tests/integration/scripts/Boss.jl)):

```julia
# Script-to-script inheritance (C#: `partial class Boss : Player`).
@godot_class mutable struct Boss <: script_type("res://Player.jl")
    @export armor::Float64 = 5.0
end
```

### Dispatch: Only What the Script Declares

A method name from the engine resolves once per script generation, and the result is cached. It resolves to either an engine callback (`Godot._ready`) or a function in the script's module.

ADR 0008 adds a rule the prompt didn't spell out:

> In both cases only methods whose first argument is declared as a supertype of the instance type (not `Any`) count. So helpers and Godot's own functions are not exposed, and unimplemented callbacks are not reported to the engine, which then skips them.

Why is that needed? A script's module sees all of `Godot` through `using Godot`. Without the rule, `has_method(player, :add_child)` would find Godot's generic `add_child` and report it as a script method.

Requiring a first argument typed to the script exposes exactly what you wrote for this class. The integration test checks both sides:

```gdscript
	check(player.has_method("take_damage") and player.has_method("_ready"), "has_method")
	check(not player.has_method("_physics_process"), "unimplemented callbacks are not methods")
```

### Validation Without Execution

The editor calls `_validate` as you type. It parses with `Base.JuliaSyntax` and lowers each top-level expression with macros expanded, *without running anything*.

`_get_global_class_name` is parse-only for the same reason. Godot calls it during its file-system scan to discover global classes. Executing user code during an editor scan would be slow at best and dangerous at worst.

Errors come back as `res://File.jl:<line>: <message>`. An invalid script is left non-instantiable rather than half-loaded.

### Placeholders in the Editor

In the editor, a non-`@tool` script must not run. Yet the inspector still has to show its exported fields with their defaults.

The agent used Godot's **placeholder instances** (`placeholder_script_instance_create`) for this. They hold property values without a Julia instance behind them.

Row 5.4 stayed `PARTIAL` until phase 12's headless editor test could check them.

## Where Reality Pushed Back

### Scripts Freed Under Live Nodes

Here's the headline bug from the phase 8 report:

> **Bug found and fixed:** in Godot 4.7 an object reaches its script only through the script instance, so the instance must hold a reference to the script. Without that, scripts were freed while nodes still used them. The instance now takes the reference on creation and releases it when freed.

In Godot 4.7, `Object::get_script()` returns `script_instance->get_script()`. The object doesn't keep its own reference to the script resource.

So a script instance that doesn't hold a reference lets the script be freed while instances still use it. That ends badly the next time anything asks the object for its script.

GDScript's instances take the reference. Now Julia's do too: [`instances.jl`](../../julia/Godot/src/runtime/instances.jl) calls `Internals.reference_object(self)` in `script_instance_create` and releases it in `free`.

This is **version-specific engine behavior**, and it's easy to get wrong from memory. The agent:

- found it during the integration tests,
- checked it against the engine's behavior at the pinned version,
- wrote the rule into ADR 0008 and its memory notes.

### Small FFI Details

Two smaller lessons from the agent's notes:

- The bridge's `method` argument had to be declared as `Ptr{UInt8}`, not `Cstring`. Julia's `Cstring` has no conversion to a plain pointer, and the address-keyed cache above needs one.
- `Script.is_valid` and `inherits_script` aren't exposed to GDScript. Godot also doesn't attach invalid scripts to scene nodes at all (`get_script()` returns `null`). So the tests check script validity through what *is* exposed. The syntax-error test, for example, looks for the reported error.

### A Limitation Stated, Not Hidden

ADR 0008's consequences include one you will run into:

> `_init` runs inside `instance_create`, before Godot attaches the instance to the object. Engine calls that need the script instance (script signals, script properties through `Object.get`) are not available in `_init`. This is the same constraint as C# constructors. Use `_ready` or `_enter_tree` for such work.

The agent didn't invent an elaborate workaround. It recognized that C# has the same constraint, documented it with the same advice, and moved on.

### The Cost of Dynamic Dispatch

Every engine call into a script costs:

- a name lookup,
- a method-cache lookup,
- Variant conversion,
- a dynamic call through `invokelatest`.

That last one is needed because scripts are evaluated at runtime, after the calling code was compiled. So Julia's **world age** rules apply.

The phase 8 report measured about 1.2 µs for a GDScript-to-Julia method call. Phase 15's benchmarks put it in context ([`docs/perf.md`](../perf.md)):

| Benchmark | Julia script | GDScript (reference) |
|-----------|-------------:|---------------------:|
| engine → script method call | 1101 ns | 551 ns |
| one `_process` dispatch | 660 ns | 280 ns |

That's about 2.3× GDScript. The ADR says honestly that faster paths (typed thunks per method) can come later without changing the ABI. That's the payoff of the single-entry-point design.

### The Driver Fixed a Stale Row

The same report opens with: *"**Verification step:** row 2.2 is now marked DONE; phase 07's identity code and its `objects` test cover it."*

That's step 2 of `gdjl-00-next` (chapter 3) at work. Before starting phase 8, the agent noticed that a row from phase 4 was still `PARTIAL`, even though phase 7 had finished its remaining work. It corrected the row.

### A Note for the Next Phase

The report also lists *"a note in the phase 09 prompt on what already exists"*.

Phase 8 had built more of the authoring syntax than planned: `@godot_class`, `@export`, `@signal`, `@tool`, `@global_class` and `@icon`. So the agent edited the phase 9 prompt to say so. Chapter 12 shows that paragraph and what it changed.

## Closing the Loop

The [`tests/integration/scripts/`](../../tests/integration/scripts) project is driven from the *GDScript* side.

Its [`main.gd`](../../tests/integration/scripts/main.gd) is tagged `# parity: 4.3, 4.9, 5.1–5.3, 5.5–5.18`. It plays the role of the engine and of a GDScript caller:

```gdscript
	check(script != null and script.get_class() == "JuliaScript", "Julia script attached from .tscn")
	check(player.ready_called, "_ready ran")
	check(is_equal_approx(player.speed, 123.5), "exported property set in .tscn")
	...
	player.connect("hit", _on_hit)
	check(player.take_damage(10) == 90, "GDScript calls a Julia method")
	check(hits == [10], "Julia emits a signal connected in GDScript")
	...
	check(boss.get_script().get_base_script() == script, "Boss.jl inherits Player.jl")
```

The Julia side checks itself too. `Player.julia_checks` verifies two things:

- `get_node` returns your struct,
- a bad argument comes back as a `GodotCallError` with `GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT`.

[`Broken.jl`](../../tests/integration/scripts/Broken.jl) contains a deliberate syntax error. [`expect_errors.txt`](../../tests/integration/scripts/expect_errors.txt) requires exactly the reported location:

```text
res://Broken.jl:8: syntax error
```

There's a small history in that line number.

The phase 8 report quotes the error as `res://Broken.jl:5`. Later, the Apache license header added three comment lines to every source file, test scripts included. The expected line moved to 8.

The agent's memory notes record the rule: *"Headers shift fixture line numbers (+3) in integration expectations."*

Phase 9 extended the same project with the authoring checks. That's why `main.gd` now also has a `check_authoring` function.

```powershell
julia tests/integration/run.jl scripts
```

## Techniques to Reuse

- **Enumerate the interface.** List every virtual and callback by name, so the agent's report shows omissions instead of hiding them.
- **Inline the facts that are cheap to state.** Names, extensions and delimiters in the prompt remove a class of small, silly errors.
- **Stub now, fill later, name the owner.** Forward references to later phases keep an interface whole while work is staged.
- **One generic entry point across a slow boundary.** A dispatch dictionary on the fast side lets handlers evolve without touching the native ABI.
- **Expose only what was declared.** Dispatch rules that require an explicit receiver type keep library functions from leaking into the script's API.
- **State limitations with their reference equivalent.** "Same constraint as C# constructors; use `_ready`" is clearer than a clever workaround.

## Try It Yourself

1. Pick one virtual from the prompt's list, for example `_get_member_line` or `_has_property_default_value`. Ask the **Ask** agent to show the C++ shim, the Julia bridge handler, and the C# equivalent in `csharp_script.cpp` side by side.
2. Write a small script in `tests/integration/scripts/` that defines `_physics_process`. Attach it to a node in `main.tscn`, and add a check to `main.gd` that `has_method("_physics_process")` is now true. Run `julia tests/integration/run.jl scripts`.
3. Ask the agent: *"What would it take to replace `invokelatest` in script dispatch with typed thunks per method, without changing the native ABI?"* Compare its plan with ADR 0008's consequences.

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 2.11 | Overridable virtual methods | DONE (`Godot._ready(self::T)` etc.; unimplemented callbacks not reported; ADR 0008) |
| 4.3 | Script instance returned by engine calls | DONE (the script struct is the object's wrapper) |
| 4.9 | GDScript → Julia methods, properties, signals | DONE (arity/type errors are Godot call errors) |
| 5.1 | `JuliaLanguage` (`ScriptLanguageExtension`) | DONE (all virtuals, forwarding over the bridge; hooks filled in by phases 11–13) |
| 5.2 | `JuliaScript` resources, `.jl` loader/saver | DONE (one generation module per load; script-to-script inheritance) |
| 5.3 | Script instance with reflection | DONE (full `GDExtensionScriptInstanceInfo3` table) |
| 5.4 | Placeholder instances in the editor | DONE (checked in phase 12's headless editor test) |
| 5.18 | `_get`, `_set`, `_get_property_list`, `_validate_property` | DONE (dispatch here; tests added in phase 09) |
| 8.6 | Script editor highlighting | DONE (native `JuliaSyntaxHighlighter`, phase 12) |
| 8.7 | Validation errors in the editor | DONE (`_validate` errors mark the line; checked in phase 12) |

At the end of phase 8, rows 5.4, 5.18, 8.6 and 8.7 were `PARTIAL`: implemented here, verified by later phases.

---
[← Previous: The Object Model](10-object-model.md) · [Contents](README.md) · [Next: Authoring Macros →](12-authoring-macros.md)
