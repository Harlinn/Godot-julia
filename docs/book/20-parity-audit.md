# 20. The Parity Audit: Re-Checking the Spec, and the Claims

Sixteen phases built the project. The seventeenth checks it.

Phase 17 doesn't add a subsystem. It goes back to the reference (Godot's C# support) and asks two questions that every long agent-driven project has to ask eventually:

- *Has the spec moved since we started?*
- *Are our own claims still true?*

The phase sits last for a reason. An audit only means something when there's something complete to audit:

- a full matrix,
- a test suite that can confirm a row ([chapter 18](18-testing-ci.md)),
- documentation and demos that exercise the whole stack ([chapter 19](19-docs-demos.md)).

Run earlier, the audit would have found mostly unbuilt features. Run last, it finds the things that are easy to miss:

- capabilities the original matrix never listed,
- members that fell between naming rules,
- rows marked `DONE` that were narrower than their C# counterpart.

The audit has run. This chapter walks you through what it found, including what the tooling got wrong before it got right. Then it closes the book.

## The Prompt

[`.github/prompts/gdjl-17-parity-audit.prompt.md`](../../.github/prompts/gdjl-17-parity-audit.prompt.md):

```markdown
---
name: gdjl-17-parity-audit
description: "Phase 17: audit Julia support against current Godot C#/.NET capabilities, refresh the parity matrix, and fix or document every gap."
argument-hint: "Optional: Godot tag to audit against (defaults to GODOT_VERSION)"
agent: agent
---
Audit Godot-julia against Godot's current C#/.NET support. Godot tag: `${input:godotTag:value in GODOT_VERSION}`. Follow the [project instructions](../copilot-instructions.md).

## Steps

1. **Refresh the spec**: fetch, at the given tag, `modules/mono/` (C++ and `glue/GodotSharp`, `editor/GodotTools`, `editor/Godot.NET.Sdk`), the godot-docs C# pages, and the Godot release notes / changelog entries tagged C#/.NET since the previously audited version. List every user-visible C# capability (attributes, generator outputs, analyzer diagnostics, project/editor settings, editor UI, export options, supported platforms, builtin type members).
2. **Diff the matrix**: add rows to the [parity matrix](../../docs/csharp-parity-matrix.md) for any capability not yet listed; assign each to the owning phase prompt.
3. **Verify each row** by inspecting code and running the tests that reference it (`scripts/check_parity_tests.jl`). Downgrade statuses that are not backed by passing tests.
4. **API surface diff**: write `scripts/api_diff.jl` that compares GodotSharp's public members (builtin types, `GD`, `Mathf`, `GodotObject` helpers, collections) against the Julia `Godot` package names (accounting for documented naming rules) and outputs missing members. Fix trivial gaps directly; list the rest.
5. **Fix or justify**: for each gap, either implement it (following the owning phase prompt's requirements) or mark `GAP` with an ADR in `docs/adr/` explaining why (e.g. GDExtension limitation, Julia platform support) and the workaround.
6. **Report**: summarize in the chat: counts by status, new rows, fixes made, remaining `GAP`s with ADR links. Update `GODOT_VERSION` if auditing a newer tag and regenerate bindings.

## Done when

No row is `TODO`/`PARTIAL` without an assigned owner and plan, and every `GAP` links an ADR.
```

## Anatomy of the Prompt

### A Spec That Moves

The `${input:godotTag:…}` parameter defaults to the pinned version, but it can name a newer one. That one parameter turns the project from a port of a snapshot into something that can **follow upstream**.

Step 1 lists *where* the spec lives: the C# module, the docs, the changelog. Step 6 says what to do when the tag changes: update `GODOT_VERSION` and regenerate the bindings.

The failure mode it prevents is **quiet drift**. Godot's C# support changes with every minor release. A parity claim made against 4.7 says nothing about 4.8 unless someone re-checks it. A matrix that's never re-checked slowly becomes fiction.

### "List Every User-Visible Capability"

Step 1 doesn't say "check the matrix". It says to enumerate capabilities *from the source*, in eight categories:

- attributes,
- generator outputs,
- analyzer diagnostics,
- settings,
- editor UI,
- export options,
- platforms,
- builtin members.

Why does that matter? The matrix was written at the start of the project from memory and documentation (chapter 2). The audit rebuilds the list from code and compares.

Anything the original matrix missed can only be found this way. A matrix can't list what its authors didn't think of.

### "Downgrade Statuses That Are Not Backed by Passing Tests"

Step 3 tells the agent to **distrust its own earlier work**. Every `DONE` was written by an agent in an earlier session that believed it was done.

Chapter 18 turned "no `DONE` without a test" into a check. This step goes one further: re-run the tests and downgrade anything they don't support.

It's the same principle a code reviewer applies to a colleague's pull request. Here it's applied to the project's own history.

### A Tool, Then Judgment

Step 4 asks for a script, `scripts/api_diff.jl`. It's specific about what the script compares and how: GodotSharp's public members against Julia names, *"accounting for documented naming rules"*. Then: *"Fix trivial gaps directly; list the rest."*

The division of labor is deliberate:

- **Enumerating** 1,000 members across 35 files is mechanical, so a tool does it.
- **Deciding** whether `Color.Color8` is missing or just spelled `from_rgba8` is a judgment, so the agent does it.

The agent then records each judgment in the tool's mapping tables. The next run doesn't need to make it again.

### Fix or Justify, With Exit Criteria

Step 5 allows exactly two outcomes per gap:

- implement it, or
- mark it `GAP` with an ADR that explains why and offers a workaround.

The "Done when" is just as precise: no `TODO` or `PARTIAL` without an owner and a plan, and no `GAP` without an ADR.

Notice what it *doesn't* require: zero `TODO`s. An audit is allowed to **find** work. It isn't allowed to leave work **unowned**.

## What the Agent Built

### Choosing the Phase

The audit ran via the resume loop ([chapter 3](03-the-resume-loop.md)).

By the strict rule ("the lowest-numbered phase that still owns `PARTIAL` rows"), it should have picked phase 1, which shares row 1.3. The agent picked phase 17 instead. The reason was in the matrix: every remaining `PARTIAL` row was blocked on something no local session could do.

- Rows 1.3, 1.7 and 10.2 need the repository published so CI can run.
- Rows 9.1 and 9.3 need a person to run manual checks in VS Code and the editor.

Phase 14 had made the same call when it skipped phase 13's manual-check rows.

Reading the rule for its intent, not its letter, is a judgment. The report states it rather than hiding it.

### Refreshing the Spec

The agent sparse-cloned Godot's `modules/mono` at the pinned tag, 4.7.2-stable, into the gitignored `.tools/` folder. It reused the godot-docs checkout from phase 16. Then it inventoried the categories from step 1:

- **Attributes**: the 14 files in `GodotSharp/Core/Attributes`, all already covered.
- **Source generators and analyzers**: all 22 diagnostic codes (GD0001–GD0402) against `docs/diagnostics.md`, which mapped only 11.
- **Settings**: every `dotnet/*` setting in the C++ and C# sources against the `julia/*` settings the project registers.
- **Editor UI**: menu items, panels and plugins in `GodotTools`. This turned up a translation parser, an inspector warning, a hot-reload watcher and a richer problems view.
- **Export options**: `dotnet/include_debug_symbols` and `dotnet/embed_build_outputs` had no Julia counterpart.
- **Docs**: the section headings of every C# page. This turned up a profiling section and a full list of version defines.

There was no changelog to read. The matrix had been written against 4.7.2 from the start, so there was no "previously audited version" to diff from. The audit stayed on the pinned tag.

### The API Diff

[`scripts/api_diff.jl`](../../scripts/api_diff.jl) parses the public members of 35 C# files. Those cover the builtin types, `GD`, `Mathf`, collections, `StringExtensions`, `Variant`, `Callable`, `Signal`, and the node, scene and resource extension helpers.

It maps each name with the project's rules and looks for a Julia counterpart:

- snake_case functions that take the value first;
- static members that take the type (`from_hsv(Color, …)`);
- constants named `Type_UPPER_SNAKE`;
- Base and LinearAlgebra generics where Julia already has the function (`length`, `push!`, `haskey`, `det`);
- `convert` and constructors for Variant conversions.

Members with no Julia equivalent by design are listed with the reason:

```julia
const EXCLUDED = Dict{String, String}(
    "Equals" => "`==`/`isequal`", "GetHashCode" => "`hash`", "ToString" => "`string`/`show`",
    "Deconstruct" => "destructuring uses fields or `Tuple(v)`", "Dispose" => "lifetime is GC-managed (`finalize`)",
    "GetEnumerator" => "`iterate`", "CopyTo" => "`copyto!`", "NativeInstance" => "internal pointer",
```

The final run printed:

```text
GodotSharp 4.7.2-stable vs Julia Godot: 907 found, 91 excluded by design, 0 missing
```

Getting there took several iterations. You'll see them in the next section, and they matter more than the final number.

### What the Audit Added

The gaps that turned out to be real were small. That's a finding in itself: sixteen phases of C#-referenced work had left little out.

- **Typed helpers.** C#'s `GetChild<T>`, `GetParent<T>`, `GetOwner<T>` and `Instantiate<T>`, plus their `OrNull` variants, had no typed Julia forms, even though `get_node(T, …)` did.
  - The audit added them to [`object/nodes.jl`](../../julia/Godot/src/object/nodes.jl).
  - One design detail: `instantiate(T, scene)` frees the instance before throwing when the scene root has the wrong type.
  - C#'s version doesn't free it in that case. Here, the leak check from chapter 18 would have caught it.
- **`glob_match`.** Godot's wildcard `String.match` had never been bound.
  - The generator's report said *"builtin method not bound (Julia equivalent in Base): String.match"*.
  - But `Base.match` is a regular-expression match, not a glob.
  - One wrong line in a generated report had hidden a missing feature since phase 4.
- **Smaller members**: `recursive_equal` for arrays, `inverse(::Vector2)`, `Plane.x/y/z`.
- **Hot-reload hooks.** C#'s `ISerializationListener` became `Godot._before_reload(self)` and `Godot._after_reload(self)` (new row 7.6, tested in the reload project).
- **Translation templates.** A native `JuliaTranslationParserPlugin` extracts `tr`, `tr_n`, `atr` and `translate` calls from `.jl` files for POT generation. It supports `# TRANSLATORS:` comments and `# NO_TRANSLATE`, as C#'s `CsTranslationParserPlugin` does (row 8.9).
- **Problems view.** The Julia panel gained error/warning toggles with counts, a search box and a grouped-by-file layout (row 8.8).
- **Export option** `julia/export/include_debug_symbols` (row 10.9).
- **Diagnostics.** Two C# rules (GD0109, GD0203) turned out to be raised already as GDJL0006, and nine have no Julia counterpart. [`docs/diagnostics.md`](../diagnostics.md) now lists all 22 codes, and a unit test fails if one goes missing.
- **Docs**: a profiling section in [`performance_tips.md`](../user/performance_tips.md) (row 9.6), and the version and precision equivalents of C#'s preprocessor defines in [`julia_features.md`](../user/julia_features.md).

Four capabilities were too large to finish in the audit. They became `TODO` rows with plans:

- a project environment in a subdirectory (1.9),
- reload after edits in an external editor (7.7),
- an inspector warning for suspended instances (8.10),
- embedding the payload in the PCK (10.10).

## Where Reality Pushed Back

### The Tool Was Wrong Before It Was Right

The first run of `api_diff.jl` reported 55 missing members. Most of them weren't missing. The tool's name mapping was incomplete:

- C# `Intersect3` is Godot's `intersect_3`, not `intersect3`.
- `GetSubName` is `get_subname`, not `get_sub_name`.
- `Color8` is `from_rgba8`, `PrintErr` is `printerr`, `Vector2I.MinValue` is the constant `Vector2i_MIN`.

The snake_case function itself was wrong for names like `ToUtf16Buffer`. Each fix went into the tool's `RENAMED` table, where it documents a naming rule. After that round, 15 remained.

Then came two bugs that went the **opposite** direction: they reported things as present when they weren't.

- **Missing from the output.** Node's extension methods (`GetNode<T>`, `GetChild<T>`, …) didn't appear at all. Their declarations end in `where T : class`, and the parser's check for nested `class` declarations skipped the whole line.
- **A false match.** `PackedScene.Instantiate<T>` was reported as found. The generic `instantiate(::Type{ClassDB}, args...)` dispatch method matched the check `Tuple{Type, PackedScene}`.

The fix uses a concrete type argument in the test:

```julia
        # Generic C# methods (`GetNode<T>`) need the typed Julia form `f(T, x, ...)`; a concrete type argument keeps
        # singleton dispatch such as `instantiate(::Type{ClassDB}, ...)` from matching.
```

The lesson is uncomfortable and important. **An audit tool written by an agent is code written by an agent.** It needs the same scrutiny.

The agent found these bugs by reading the "found" list, not just the "missing" list. It listed every match whose Julia name differed from the plain snake_case of the C# name, and reviewed that list.

A tool that reports zero missing is only useful if you've checked that it *can* report something.

### `DONE` Meant "Tested", Not "Complete"

Step 3's instruction to downgrade unsupported statuses found nothing to downgrade. Every `DONE` row still had passing tests, 87 of 87.

But the inventory found something subtler. Row 8.8, "Build diagnostics panel with clickable file:line", was `DONE` and tested. Yet C#'s panel had filters, search and a tree layout that the Julia panel lacked.

The row was true as written. It was just written more narrowly than C#.

The check from chapter 18 verifies that claims have tests. It can't verify that the claims are as broad as the reference. Only re-reading the reference can.

The audit extended the panel rather than downgrading the row. The row's text now names the features it covers.

### A Doc Example That Measured Nothing

The new profiling example in the docs failed its doc test: the profile report was empty.

The obvious suspect was the embedded runtime. Does the sampling profiler work inside Godot? But the agent first tried the same code in a plain Julia process, and got zero samples there too.

The workload's result was never used, so the compiler had removed the loop entirely:

```julia
total = Ref(0.0)                        # use the results, or the compiler removes the work being profiled
@profile for _ in 1:200
    total[] += busy(100_000)
end
```

Reproducing outside the engine took one command and ruled out a whole class of explanations. It's also another example of chapter 19's point: an example that "looks right" can be wrong in ways only execution reveals.

The same investigation turned up a small usability bug. `scripts/doctest_docs.jl performance_tips.md` failed because the script expected a path, not a page name. So the command quoted in chapter 19 of this book didn't work. The script now accepts both.

### A Default That Needed a Human

C#'s `dotnet/include_debug_symbols` defaults to on. The agent mirrored that, so release system images kept line information.

The release export test then showed what it cost: the payload grew from 723 MiB to 822 MiB.

That's a **product decision** (parity of defaults versus a 100 MiB download), not a technical one. The agent stopped and asked. Our answer was three words: *"off by default"*.

The option stays, so parity of capability is kept. The matrix row records the deviation:

> default off, unlike C#, because it adds ~100 MiB to the payload

### Long Runs and Status Questions

The four export runs took about 20 minutes. During them, we asked three times how things were going:

- *"Are you still waiting?"*
- *"How is it going?"*
- *"when, approximately, will this be finished?"*

The first two times, the agent checked the processes and logs rather than repeating its last statement. It reported which runs had passed, with their numbers, and estimated the rest. By the third, the runs had finished.

Remember chapter 19's episode of an agent waiting on a finished job? This is the behavior you want instead: when asked about a background task, **look before answering**.

## Closing the Loop

The audit leaves behind tools that can run again:

```powershell
julia --project=julia/Godot scripts/api_diff.jl --verbose    # C# API vs Julia, with each match shown
julia scripts/check_parity_tests.jl                          # every DONE row has a tagged test
julia scripts/test_all.jl --exports                          # everything, including export builds
```

The final verification ran:

- the Godot unit tests (542) and GodotEditor unit tests (69),
- all 11 integration projects with leak checks,
- 128 doc test assertions,
- all 5 demos,
- 4 export runs.

The parity check reported 92 of 92 `DONE` rows tagged.

**Re-pinning, not yet exercised.** The audit stayed on 4.7.2, so step 6's "update `GODOT_VERSION` and regenerate bindings" didn't run.

When it does, the generator-first design of [chapter 7](07-bindings-generator.md) is what makes it cheap:

- the 16,800 generated methods come from `extension_api.json`,
- the golden math tests from [chapter 8](08-builtin-math.md) re-check the hand-written types against the new engine,
- `api_diff.jl` re-checks the C# surface at the new tag.

The next audit against a newer Godot will show how well that holds up.

## Techniques to Reuse

- **Re-derive the spec from source.** A matrix written from memory can't list what its authors forgot. Rebuild the capability list from the reference's code.
- **Let tools enumerate, let the agent judge, and record the judgments.** Mapping tables in the tool turn one-time decisions into rules.
- **Audit the auditor.** Check what a tool reports as *found*, not just as missing, and confirm it can fail.
- **Allow the audit to find work, but not to orphan it.** Every new `TODO` gets an owner and a plan. Every `GAP` gets an ADR.
- **Reproduce outside the system first.** One plain-Julia run separated a compiler effect from an engine problem.
- **Escalate product decisions.** When parity and practicality conflict, ask. Then record the answer where the next session will read it.

## Try It Yourself

1. Create a scratch branch. Run `/gdjl-17-parity-audit` with the **Plan** agent against the pinned tag. Review its proposed matrix changes before allowing any edits. Compare its findings with the rows the audit added (1.9, 3.14, 7.6, 7.7, 8.9, 8.10, 9.6, 10.9, 10.10).
2. Run `julia --project=julia/Godot scripts/api_diff.jl --verbose`. Pick five matches whose Julia name isn't the plain snake_case of the C# name. Ask the **Ask** agent to explain the naming rule behind each one. Check its answer against ADR 0003 and ADR 0005.
3. Delete one entry from `RENAMED` in `scripts/api_diff.jl` (for example `"Color8" => [:from_rgba8]`). Rerun the script, and see how a single missing rule shows up.

## Parity Rows

The matrix after the audit: **92 `DONE`, 5 `PARTIAL`, 4 `TODO`, 1 `GAP`.**

The single `GAP`, row 10.6, was `PARTIAL` before the audit ([chapter 17](17-export.md)). No amount of further work makes trimming possible for an eval-based script runtime. So step 5's "mark `GAP` with an ADR" was the honest status.

| Row | Capability | Status |
|-----|------------|--------|
| 1.3 | `Godot` Julia package in a registry, versioned with Godot | PARTIAL (release workflow written, not run; plan: publish the repository, install JuliaRegistrator, push a version tag) |
| 1.7 | Single and double precision (`real_t`) builds | PARTIAL (double-precision library builds locally; plan: DONE once the CI job passes on GitHub) |
| 1.9 | Project environment in a subdirectory | TODO (phase 12; plan in the matrix) |
| 7.7 | Reload of `.jl` files changed by an external editor | TODO (phase 11; plan in the matrix) |
| 8.10 | Inspector warning while an instance is suspended | TODO (phase 12; plan in the matrix) |
| 9.1 | Attach external debugger | PARTIAL (all tested parts done; plan: a person runs the VS Code checklist) |
| 9.3 | Script debugger stack frames in the Debugger panel | PARTIAL (handlers tested; plan: a person runs the editor check) |
| 10.2 | Windows, Linux, macOS desktop exports | PARTIAL (Windows exported and run; plan: DONE once the CI export step passes on Linux and macOS) |
| 10.6 | NativeAOT / trimming | GAP ([ADR 0014](../adr/0014-export.md); workaround: `sysimage` mode) |
| 10.10 | Payload embedded in the PCK | TODO (phase 14; plan in the matrix) |

## Lessons Across the Whole Project

Twenty chapters condense into a short playbook. Each item links to the chapter that shows it best.

1. **Pin a reference and make it a table.** A parity matrix against a real implementation gives every session the same definition of done ([chapter 2](02-repository-and-prompt-system.md)).
2. **One prompt resumes the work.** A driver that reads the state, verifies it and picks the next step makes many short sessions behave like one long one ([chapter 3](03-the-resume-loop.md)).
3. **Decide architecture before code, and write it down.** ADRs keep agents from reopening settled questions ([chapter 4](04-scaffold.md)).
4. **State invariants as rules, not hopes.** "No exception may unwind through C frames" shaped every entry point ([chapter 5](05-embed-runtime.md)).
5. **Measure early, and keep the numbers.** Performance claims need a log ([chapter 6](06-ffi-layer.md)).
6. **Generate what is large and regular.** A generator scales to 16,800 methods; hand-writing doesn't ([chapter 7](07-bindings-generator.md)).
7. **Use the reference as an oracle.** Golden values computed by Godot settle every numeric argument ([chapter 8](08-builtin-math.md)).
8. **Specify semantics precisely where languages differ.** Ownership, identity and conversion rules are where bugs hide ([chapters 9](09-variant-collections.md) and [10](10-object-model.md)).
9. **Give the agent exhaustive checklists.** "Implement every virtual" beats "implement the important ones" ([chapter 11](11-script-language.md)).
10. **Translate models, not syntax.** Signals, async and hot reload work when designed with Julia's semantics, not against them ([chapters 13](13-signals-async.md) and [14](14-hot-reload.md)).
11. **Be honest where parity is impossible.** A justified `PARTIAL` or `GAP` is worth more than a faked `DONE` ([chapters 16](16-debugging.md) and [17](17-export.md)).
12. **Turn conventions into failing checks.** "No `DONE` without a test" became a script ([chapter 18](18-testing-ci.md)).
13. **Execute every example and play every demo.** Docs and games caught bugs that unit tests missed ([chapter 19](19-docs-demos.md)).
14. **Re-audit with tools, and audit the tools.** The spec moves, and auditors have bugs too ([this chapter](#the-tool-was-wrong-before-it-was-right)).
15. **Keep humans on the decisions that are theirs.** Scope, licenses, defaults with real costs, and a glance at a machine that has gone quiet ([chapters 17](17-export.md), [18](18-testing-ci.md), [19](19-docs-demos.md) and this one).

### Outlook (Opinion)

*What follows is our opinion, not a finding of the project.*

Several things in this project still need a person, and will for a while:

- **Choosing what to build and what to leave out.** The scope cut of mobile and web exports, the license, the debug-symbols default: all human calls.
- **Checks that need eyes and hands**, such as attaching a debugger in VS Code or watching the editor's Debugger panel.
- **Publishing.** It unlocks three of the five remaining `PARTIAL` rows, and it needs accounts and permissions that an agent shouldn't hold.
- **Noticing** that an agent is waiting on a finished job. That took a glance at Task Manager.

What might change with the next generation of models and tools?

Long-running work is the clearest candidate. Much of the friction in chapters 17–20 came from builds that take ten minutes, and agents that have to wait for them, poll them, or misread their state. Better background-task handling in agent harnesses would remove a lot of it.

Agents that can drive a real editor UI would turn rows like 9.1 and 9.3 into automated tests. And a model that audits its own tools as routinely as this chapter's agent eventually did would make the "found" list as trustworthy as the "missing" list.

What probably won't change is the **shape of the method**:

- a pinned reference,
- a matrix that every session reads,
- decisions written down,
- checks that fail.

That's what let a series of separate sessions build one coherent system. Better models will make each step faster. They don't remove the need for the steps.

---
[← Previous: Documentation and Demos](19-docs-demos.md) · [Contents](README.md)
