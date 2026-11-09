# 19. Documentation and Demos: Docs That Run, Games That Test

By the end of phase 15, the project had a language binding that passed hundreds of tests. The parity matrix had almost every row `DONE`.

And yet a Godot developer arriving at the repository would still have had no idea how to use it.

C# has a full section of the Godot manual. The official demo repository has C# versions of the tutorial games. Phase 16 provides the Julia equivalents:

- one documentation page per C# page,
- ports of the C# demos.

Documentation is the kind of work AI is famously good at producing quickly. It's also famously good at getting it subtly wrong. Plausible prose with plausible code that doesn't run is worse than no documentation at all.

This chapter covers the one requirement in the prompt that prevents that. It also shows you how real games became the final test of the whole stack.

## The Prompt

[`.github/prompts/gdjl-16-docs-demos.prompt.md`](../../.github/prompts/gdjl-16-docs-demos.prompt.md):

```markdown
---
name: gdjl-16-docs-demos
description: "Phase 16: user documentation mirroring the Godot C# docs, and Julia ports of the official C# demo projects."
argument-hint: "Optional: specific doc page or demo to produce"
agent: agent
---
Write user documentation and demo ports. Scope: `${input:scope:all docs and demos}`. Follow the [project instructions](../copilot-instructions.md). References: godot-docs `tutorials/scripting/c_sharp/` and the C# projects in `godotengine/godot-demo-projects` (folder `mono/`), plus the "Your first 2D game" tutorial's C# code.

## Documentation (`docs/user/`)

Create one page per C# page, adapted to Julia, with every C# example translated:

| C# page | Julia page |
|---------|------------|
| `c_sharp_basics` | `julia_basics.md` — install, setup, editor config, first script, project structure |
| `c_sharp_features` | `julia_features.md` — type conversion, casting, `get_node(T, …)`, preprocessor/feature-tag equivalents |
| `c_sharp_differences` | `julia_api_differences.md` — naming, renamed types (`GodotObject`, `GDArray`, unexported clashes), `GD` functions, singletons, operators |
| `c_sharp_signals` | `julia_signals.md` |
| `c_sharp_exports` | `julia_exports.md` |
| `c_sharp_global_classes` | `julia_global_classes.md` |
| `c_sharp_variant` | `julia_variant.md` |
| `c_sharp_collections` | `julia_collections.md` |
| `c_sharp_style_guide` | `julia_style_guide.md` |
| (C# async sections) | `julia_async.md` |
| (C# debugging) | `julia_debugging.md` (link phase 13 doc) |
| (C# export notes) | `julia_export.md` |

Also include a "Coming from C#" cheat sheet (side-by-side syntax table) and a "Performance tips" page (type stability, avoiding allocations in `_process`, sysimages).

Every code block must be extracted and executed by a doc test (`scripts/doctest_docs.jl`) inside a headless project.

## Demos (`demos/`)

Port, keeping scene files and assets identical where licensing allows (demos are MIT/CC0 — keep attribution):
1. *Dodge the Creeps* (2D tutorial)
2. 2D platformer or *Pong*
3. A 3D demo (e.g. *Squash the Creeps*)
4. A multiplayer demo using `@rpc`
5. An editor plugin demo using `@tool`

Each demo runs headlessly in CI for a few seconds without errors (integration harness from phase 15).

Update parity rows 11.1–11.2.
```

## Anatomy of the Prompt

### A Mapping Table as the Specification

"Write user documentation" is an open-ended request. The table makes it closed.

It has twelve rows. Each pairs a C# page with a Julia file name, and several add a one-line summary of what the page must cover. Two extra pages (the cheat sheet and performance tips) are named in the next sentence.

That gives you two practical benefits:

- A reviewer can check completeness by listing a folder.
- An agent can tell when it is done.

The table also keeps the documentation **parallel** to Godot's C# manual. If you know where something is in the C# docs, you know where to look in the Julia docs.

This is the same strategy as the parity matrix itself (chapter 2). When an established reference exists, mirror its structure instead of inventing one.

### One Sentence Against Plausible-Looking Docs

> Every code block must be extracted and executed by a doc test (`scripts/doctest_docs.jl`) inside a headless project.

This is the most important sentence in the prompt.

Documentation written by an agent has the same failure mode as documentation written by a hurried person, only faster. The code looks right. It uses names that sound right. And it doesn't run.

Executing every block turns every example into a test. As you'll see, it caught a real bug in the very first page.

Note the phrase *"inside a headless project"*. Running the snippets in a plain Julia session would prove little. Most of them create nodes, connect signals or await frames, so they have to run inside the engine.

### Demos Named by Kind, Not Just by Title

The demo list mixes specific titles (*Dodge the Creeps*) with kinds (*"a multiplayer demo using `@rpc`"*, *"an editor plugin demo using `@tool`"*).

The kinds are there for **coverage**. Together, the five demos touch:

- 2D,
- 3D,
- networking,
- editor tooling.

So every major part of the stack runs in a real game. No C# demo is named for the fifth item, so it calls for a new one.

### Licensing in the Prompt

*"Keeping scene files and assets identical where licensing allows (demos are MIT/CC0 — keep attribution)."*

The demos belong to someone else. Writing the license constraint into the prompt means the agent treats attribution as a requirement, not an afterthought.

### A Scope Parameter for a Big Phase

`${input:scope:all docs and demos}` is the first time a phase prompt explicitly anticipates being split.

Fourteen documentation pages and five demos are a lot for one session. The parameter lets you run *"just julia_signals.md"* or *"just the multiplayer demo"* and resume later.

In the actual session we used the default, and everything was done in one long run.

## What the Agent Built

### Our User Guide

[`docs/user/`](../user/README.md) contains all twelve mapped pages, plus [`coming_from_csharp.md`](../user/coming_from_csharp.md) and [`performance_tips.md`](../user/performance_tips.md). Most pages open by naming the C# page they mirror.

The cheat sheet is a three-column table:

```markdown
| Task | C# | Julia |
|------|----|-------|
| Script class | `public partial class Player : CharacterBody2D` | `@godot_class mutable struct Player <: CharacterBody2D ... end` |
| Exported property | `[Export] public int Speed { get; set; } = 400;` | `@export speed::Int = 400` |
| Signal | `[Signal] public delegate void HitEventHandler(int damage);` | `@signal hit(damage::Int)` |
| Await | `await ToSignal(timer, Timer.SignalName.Timeout);` | `@await to_signal(timer, :timeout)` (in a `godot_task`) |
| Preprocessor | `#if GODOT_WINDOWS` | `if Godot.@feature(:windows)` |
```

Pages also absorbed lessons from earlier phases. For example, [`julia_export.md`](../user/julia_export.md) explains the `invokelatest` requirement for scripts evaluated at runtime. The phase 14 report had flagged that for exactly this phase (chapter 17).

### The Doc Tester

[`scripts/doctest_docs.jl`](../../scripts/doctest_docs.jl) states its rules in its header:

```julia
# Rules, per page (blocks of one page run in order and share one module, so later blocks see earlier names):
# - A block defining a `@godot_class` is a script: written to res://<page>/<Class>.jl and loaded as a script
#   resource (like a file in a project); other code in later blocks can use it via `Godot.script_type`.
# - Other blocks are evaluated in the page module, inside a running engine (a Godot task, so `@await` works).
#   `@test` from Test is available; each block must run without throwing.
# - ```julia {no-run} marks snippets that cannot run on their own (shell, editor-only or fragment); the reason
#   goes on the first line as a comment.
```

Three design choices make documentation pages behave like tutorials:

- **Blocks run in order and share a module.** A page can define a class in one block and use it three paragraphs later, just as you'd read it.
- **Script blocks become real script files.** A block containing `@godot_class` is written to `res://<page>/<Class>.jl` and loaded through Godot's resource loader. It takes the same path as your own scripts, including the script language from chapter 11.
- **Blocks can assert.** `@test` is available, so examples can state their expected results instead of just running.

`julia_basics.md` shows all three. One block defines the class; the next one uses it and checks the result:

```julia
g = Greeter()                     # an engine Node with the script attached (C#: new Greeter())
add_child(DOC_ROOT, g)            # enters the tree: _ready prints "Hello from Julia!"
@test greet(g, "Godot") == "Hello, Godot!"
@test Godot.call(g, :greet, "GDScript") == "Hello, GDScript!"   # how other languages call it
@test g.count == 2
free(g)
```

The `{no-run}` opt-out exists, with a required reason on the first line.

Today our user guide has 61 Julia blocks, and none of them use it. Every Julia example in the guide runs.

### The Demos

[`demos/`](../../demos/README.md) holds four ports from the official `mono/` folder:

- Dodge the Creeps,
- Pong,
- Squash the Creeps,
- Multiplayer Pong.

It also holds one new editor-plugin demo.

Porting starts with [`scripts/port_csharp_demo.jl`](../../scripts/port_csharp_demo.jl). Its header is honest about what it automates and what it doesn't:

```julia
# Copies a C# demo from godot-demo-projects (mono/<name>) into demos/<dest>, converting the project to Julia:
# drops C# project files and .cs scripts, points scene script references at .jl files, renames signal
# connection methods and exported properties to snake_case, removes the [dotnet] section and the "C#" feature.
# The Julia scripts themselves are written by hand next to the copied scenes.
```

That split is a sensible division of labor between a script and an agent:

- The **mechanical** part is rewriting scene files consistently across dozens of connections and properties. It's deterministic, so it belongs in a tool you can rerun.
- The **creative** part is translating C# logic into idiomatic Julia. That's where the agent's judgment adds value.

Scenes and assets stay byte-identical except for the converted names, as the prompt required.

Here's the game-over sequence of Dodge the Creeps. First, the C# from the upstream demo:

```csharp
    public async void ShowGameOver()
    {
        ShowMessage("Game Over");

        var messageTimer = GetNode<Timer>("MessageTimer");
        await ToSignal(messageTimer, Timer.SignalName.Timeout);

        ShowMessage("Dodge the\nCreeps!");
        await ToSignal(GetTree().CreateTimer(1.0), SceneTreeTimer.SignalName.Timeout);

        GetNode<Button>("StartButton").Show();
    }
```

And the Julia port in [`demos/dodge_the_creeps/HUD.jl`](../../demos/dodge_the_creeps/HUD.jl):

```julia
# C#'s `async void` method: a Godot task that awaits signals on the main thread; the engine gets `nothing` back.
function show_game_over(self::HUD)
    godot_task() do
        show_message(self, "Game Over")
        @await to_signal(get_node(Godot.Timer, self, "MessageTimer"), :timeout)

        show_message(self, "Dodge the\nCreeps!")
        @await to_signal(create_timer(get_tree(self), 1.0), :timeout)

        show(get_node(Button, self, "StartButton"))
    end
    return nothing
end
```

The line-for-line correspondence is the point. It shows a C# developer that their mental model carries over.

The `return nothing` at the end has a story. We'll get to it below.

### Demos as Tests

The prompt asked that each demo *"runs headlessly in CI for a few seconds without errors"*. The agent went further.

[`demos/run.jl`](../../demos/run.jl) doesn't just start each game. It **plays** it:

```julia
# Games are played by demos/driver.gd, injected as an autoload through override.cfg (removed afterwards); it must
# print GDJL_DEMO_OK. multiplayer_pong runs a host and a client process that connect over ENet on localhost.
# editor_plugin runs in the headless editor with demos/editor_driver.gd added as a second plugin, which presses the
# Julia dock's button and checks the @tool node.
```

The driver:

- starts a Dodge game and goes through game over,
- lets the Pong ball bounce,
- waits for Squash mobs,
- connects two real processes for multiplayer Pong.

A demo that merely starts proves that scripts load. A demo that is *played* proves much more:

- signals fire,
- timers run,
- physics callbacks reach Julia,
- RPCs cross the network,
- the editor plugin's button changes the edited scene.

The driver is written in GDScript, and that has a side benefit. It exercises the Julia code the way the engine and other languages see it, not from inside Julia.

## Where Reality Pushed Back

### The First Page Had a Bug

The agent wrote the first three pages and ran the doc test on them. The fix that followed was in `julia_basics.md`, in the `Greeter` example.

The original line was:

```julia
    return "$(self.greeting), $name!"
```

In Julia, `!` is a valid character in identifiers (as in `push!`). So `$name!` interpolates a variable called `name!`, which doesn't exist.

The agent's fix, labeled in its edit as *"Fix the interpolation bug"*:

```julia
    return "$(self.greeting), $(name)!"
```

This is the canonical example of what **executable documentation** is for.

The original line looks completely right. It's the kind of thing a reviewer reads past. It would have failed for the first person who copied it. Without the doc test, it would have shipped on the first page of the guide.

### A Missing Feature, Found by Writing Its Documentation

When the agent ran the doc test on all pages, the global classes page failed.

Its example scripts used another script's global class by name. A Julia script couldn't yet do that without an explicit `script_type` call. C# code can name any `[GlobalClass]` directly.

This wasn't a documentation error. It was a **parity gap** that the earlier phases' tests had missed, because no test had tried it.

The agent added `bind_global_classes!` to the script loader ([`runtime/scripts.jl`](../../julia/Godot/src/runtime/scripts.jl)):

```julia
"""
Bind the Julia global classes that `source` mentions in `mod`, so scripts can use them as types anywhere (field
types, method signatures), as C# code can name any [GlobalClass]. Scripts being loaded (cycles) are skipped.
"""
function bind_global_classes!(mod::Module, path::String, source::String)
```

It then added an integration test for it, tagged with the matrix row for global classes, and extended the documentation page to say so.

Here's the takeaway: writing documentation is a form of testing. It forces you to use the API the way a newcomer would. Every awkward example is a design signal.

### A Script Method Must Not Return a Task

The first version of `show_game_over` was a one-liner:

```julia
show_game_over(self::HUD) = godot_task() do
    ...
end
```

In Julia, a function returns the value of its last expression. So this version returned the `Task` object.

`Main.jl` calls the method through the engine (`Godot.call(get_node(self, "HUD"), :show_game_over)`). That means the return value has to be converted to a Variant, and a `Task` can't be.

C#'s `async void` returns nothing. The Julia equivalent has to do the same, explicitly.

The agent:

- rewrote the method with `return nothing`,
- put the reason in a comment,
- carried the lesson into our user guide.

[`julia_async.md`](../user/julia_async.md) now says: *"The engine expects a Variant-compatible result, so return `nothing` rather than the task (C#: an `async void` method)."* The cheat sheet has a row for it, and the rule went into the agent's memory notes.

A unit test that calls the method from Julia would never have found this. It took a real game calling the method through the engine.

### Converter Heuristics Meet Real Scenes

The scene converter renames C#-style property names in `.tscn` files to snake_case.

The first version treated any name starting with `_` as a C# field. That would also rename engine-internal properties, such as a `Curve3D`'s `_data`. The fix narrowed the rule to underscored names *that contain an uppercase letter*:

```julia
        csharp = isuppercase(name[1]) || (startswith(name, "_") && any(isuppercase, name))
```

That rule, in turn, missed one case. Multiplayer Pong's paddle has a C# field `_left`, which is all lowercase.

The agent fixed that single line in the scene by hand instead of making the converter more complex.

Heuristics over real data always have edge cases. The real question is whether an edge case is common enough to deserve code. One property in four demos isn't.

The agent also re-ported the scenes after improving the converter, *without overwriting its hand-written Julia scripts*. It copied them aside, regenerated the demo folders, and copied them back.

The project's rule for generated bindings is to keep generated files separate from hand-written ones. That rule applies to ports too.

### Flaky Is Not the Same as Broken

The multiplayer demo failed intermittently. The causes were in the *test*, not the product:

- **Slow client boot.** The client process starts after the host and needs time to boot Julia, so the driver's connection wait was tripled.
- **Bad sampling time.** The driver checked that the ball had moved after four seconds. By then the ball sometimes reached a side and was reset to the center, near where it started. Sampling after one second fixed it.
- **Early exit.** The client quit before the host had finished its checks, so the client now stays connected longer.

Each fix carries a comment explaining the timing, for example *"Sampled before the ball can reach a side and be reset to the center."* After each change, the agent ran the full demo suite twice in a row to check stability.

Treating every intermittent failure as a product bug wastes time. So does retrying until a test happens to pass.

The agent did neither. It added diagnostics to the failing check (ball position, speed and processing state) and fixed the cause it found.

### The Editor Ignores `override.cfg`

The game demos inject the driver through `override.cfg`, which Godot reads at startup.

The editor-plugin demo needed a second plugin enabled, though. The headless editor reads enabled plugins only from `project.godot`.

The runner now patches `project.godot` temporarily and restores it in a `finally` block. After the run, the agent checked with `git status` that the file was back to its original state.

### Two Process Lessons

The last stretch of the phase produced two lessons that have nothing to do with Julia or Godot.

**Editing files through the shell can corrupt them.**

At one point the agent rewrote `julia_basics.md` with a PowerShell one-liner to fix a code fence. Windows PowerShell 5.1 reads UTF-8 files without a byte-order mark as the system code page. Every `→` arrow in the page turned into mojibake (`â†’`).

The agent later found and fixed it, and named the cause: *"left by my earlier PowerShell rewrite of the file."* This is why agent instructions often say to use the editor's file tools instead of terminal commands for edits.

**Waiting needs checking.**

Near the end, the agent delegated the integration tests to a background run and reported: *"The integration run is still going; I'll wait for it to finish."* We looked at the machine and wrote back:

> Task manager says that not much is going on

The agent checked and replied: *"The integration tests had already finished when you checked: 11/11 projects passed with leak checks, which is why the machine looked idle."*

What happened? The background run's summary had said that results were unavailable. The agent had concluded from that that the run was still going. Our glance at Task Manager unblocked it.

Agents can wait on things that have already finished. When an agent says it's waiting, a quick independent check is cheap.

### No Formal Report

Phase 16 is also the only phase without a clean final report.

We moved on to other requests (packaging the repository for transfer) while the last test runs were still going. The results came in the next turn's reply:

> **Phase 16 tests:** everything finished has passed:
> - Integration: 11/11 projects, with leak checks
> - Demos: 5/5
> - Doc tests: 125 passed, 0 failed
> - Unit tests for the Godot and GodotBindgen packages
> - Parity check: 87/87
>
> GodotEditor's unit tests exited cleanly, but I didn't see their counts, and GodotTestRunner's tests had not finished when I last checked.

Even in a hurried, interrupted ending, the report separates what passed from what it didn't see.

### Licensing Hygiene

The ported demos stay under their original MIT license. Here's how the agent handled it:

- It copied the upstream `LICENSE.md` into [`demos/LICENSE.md`](../../demos/LICENSE.md).
- Each Julia port starts with an attribution line, for example `# Ported from godot-demo-projects mono/dodge_the_creeps/HUD.cs (MIT, Godot contributors).`
- Each demo README keeps the upstream asset credits.

When the project later adopted Apache-2.0 (chapter 18), the agent added headers to 167 source files. It deliberately skipped the four ported demos: *"they stay MIT under demos/LICENSE.md. The editor-plugin demo and the demo runner did get the Apache header."* [`demos/README.md`](../../demos/README.md) spells out the split.

An agent handling licensing correctly isn't a given. Here it worked because the prompt stated the constraint. The agent then applied it consistently, even when a later request could easily have overridden it.

## Closing the Loop

```powershell
julia scripts/doctest_docs.jl                     # every ```julia block of docs/user, in a headless project
julia scripts/doctest_docs.jl julia_signals.md    # one page
julia demos/run.jl                                # play all five demos headlessly
julia demos/run.jl multiplayer_pong               # host + client over ENet on localhost
```

Both runners are part of `scripts/test_all.jl` (chapter 18). They carry `# parity: 11.1` and `# parity: 11.2` tags, so the parity check counts them as the tests behind those two rows.

At the end of the phase:

- 125 doc test assertions passed,
- all 5 demos passed,
- the parity check reported 87 of 87 `DONE` rows tagged.

## Techniques to Reuse

- **Use a mapping table as the scope.** "One page per reference page" makes documentation complete and checkable.
- **Execute every example.** The first page had a bug that looked right. Doc tests found it.
- **Treat writing docs as API testing.** Writing the global classes page found a real feature gap.
- **Use real programs as acceptance tests, and drive them from outside.** A GDScript driver playing the demos found the `Task` return bug that no unit test could.
- **Script the mechanical part, hand-write the creative part.** The scene converter is rerunnable; the Julia translations are where judgment goes.
- **Diagnose flakiness before fixing it.** Add diagnostics, fix the cause, run twice.
- **Edit files with file tools, not shell one-liners.** Encodings bite.
- **Check on waiting agents.** "I'll wait" can mean "I'm waiting for something that already finished."
- **Put license constraints in the prompt.** The agent then applies them even in later, unrelated requests.

## Try It Yourself

1. Break a doc example on purpose. In a scratch branch, change `$(name)!` in `julia_basics.md` back to `$name!` (or break any code block in a `docs/user` page). Run `julia scripts/doctest_docs.jl julia_basics.md` and read the failure. Then ask the **Agent** to fix it. Does it fix the docs, or does it try to change the code under test?
2. Open `demos/squash_the_creeps/Player.jl` next to the upstream `mono/squash_the_creeps/Player.cs` from [godot-demo-projects](https://github.com/godotengine/godot-demo-projects). Find the places where the Julia version differs structurally from a line-by-line translation. Ask the **Ask** agent why.
3. Ask the **Plan** agent: *"Port one more C# demo from godot-demo-projects using scripts/port_csharp_demo.jl. What will the converter handle, and what will need hand work?"* Compare its plan with this chapter.

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 11.1 | Docs: basics, features, API differences, signals, exports, global classes, variant, collections, style guide | DONE (`docs/user/`: one page per C# page plus async, debugging, export, a C# cheat sheet and performance tips; every Julia block runs headlessly via `scripts/doctest_docs.jl`) |
| 11.2 | Official C# demo projects | DONE (`demos/`: Dodge the Creeps, Pong, Squash the Creeps, Multiplayer Pong ported from `godot-demo-projects/mono` via `scripts/port_csharp_demo.jl`, plus a Julia editor-plugin demo; each driven headlessly by `demos/run.jl`) |

---
[← Previous: Testing and CI](18-testing-ci.md) · [Contents](README.md) · [Next: The Parity Audit →](20-parity-audit.md)
