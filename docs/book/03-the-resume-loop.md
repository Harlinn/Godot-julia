# 3. The Resume Loop: `gdjl-00-next`

Every other phase prompt in this repository describes a piece of software. This one describes a **way of working**.

It's five numbered steps long. We typed it 17 times in the main implementation session, far more than any other prompt.

If you take one idea from this book into your own projects, take this one. A short **driver prompt**, combined with state kept in the repository, turns an agent from a conversation partner into a process. You can stop it, inspect it and resume it at any time.

Why position 00? Because it isn't a phase. It's the loop that runs the phases.

It also couldn't have been run *first*. It needs these to exist:

- the instructions file,
- the parity matrix,
- the phase prompts.

Those came out of the very first turn of the project, from the two-sentence request quoted in chapter 1.

## The Prompt

Here's [`.github/prompts/gdjl-00-next.prompt.md`](../../.github/prompts/gdjl-00-next.prompt.md):

```markdown
---
name: gdjl-00-next
description: "Resume the Godot+Julia implementation: find the next incomplete phase in the C# parity matrix and execute it."
agent: agent
---
Determine where the Godot+Julia (Godot-julia) implementation stands and continue it.

1. Read [project instructions](../copilot-instructions.md) and the [parity matrix](../../docs/csharp-parity-matrix.md).
2. Inspect the repository to verify the matrix is accurate (a row marked `DONE` must have code and a passing test). Correct any stale statuses.
3. Pick the lowest-numbered phase prompt (`gdjl-NN-*.prompt.md` in this folder) that still owns `TODO` or `PARTIAL` rows and whose predecessors are complete.
4. Read that prompt file and carry out its instructions fully.
5. Finish by reporting: phase executed, rows changed, tests run, and remaining blockers.
```

## Anatomy of the Prompt

### Frontmatter: a Command with No Arguments

`name: gdjl-00-next` makes the prompt available as `/gdjl-00-next`.

There's no `argument-hint` and no `${input:…}`. That's by design. The driver needs no parameters, because everything it needs is already in the repository.

`agent: agent` selects the built-in **Agent**, which can edit files and run commands. The description doubles as documentation for you: *find the next incomplete phase … and execute it.*

You can still add free text after the command. We did that exactly once, at a critical moment:

`/gdjl-00-next skip and remove 10.3, 10.4 and 10.5`

So a driver without parameters still accepts steering.

### Step 1: Read State from the Repository, Not from the Chat

> Read [project instructions] and the [parity matrix].

Every new chat starts with an empty context window. Long sessions eventually lose their early turns to summarization.

A process that depends on the agent *remembering* the plan is fragile. A process that re-reads the plan from versioned files at the start of every run is robust. That makes the process:

- **Resumable.** Close VS Code on Monday, run `/gdjl-00-next` on Wednesday, and the agent starts exactly where the files say the project is. The recorded sessions show this happening: nothing on 3 November, then the loop picked up on 4 November without a hand-written recap.
- **Restartable.** If a run goes badly, revert the files and run the driver again.
- **Auditable.** Every state change is a diff to the matrix, an ADR or a test. You review files, not chat transcripts.

The failure mode this prevents is **conversational drift**: the plan slowly changes because it only exists in a long, partially forgotten chat.

### Step 2: Trust, but Verify

> Inspect the repository to verify the matrix is accurate (a row marked `DONE` must have code and a passing test). Correct any stale statuses.

This step treats earlier work as claims to check, not facts. That includes the agent's work and your own edits.

Statuses go stale for ordinary reasons:

- a later phase changes an earlier subsystem,
- a test gets disabled,
- a file moves.

Agents also share a very human weakness: they like to report success.

The definition in parentheses carries the weight. *"`DONE` must have code and a passing test"* turns a judgment call ("is this done?") into something the agent can check.

In the first runs, it was only a rule written in the prompt. In phase 15 (chapter 18), it became mechanical. [`scripts/check_parity_tests.jl`](../../scripts/check_parity_tests.jl):

- parses the matrix,
- collects `# parity: x.y` tags from every test file,
- fails if any `DONE` row has no tagged test, or any tag names a row that doesn't exist.

```julia
function main()
    rows = matrix_rows()
    tags = tagged_rows(test_files())
    done = sort!([id for (id, s) in rows if s == "DONE"]; by = id -> parse.(Int, split(id, '.')))
    missing_ = filter(id -> !haskey(tags, id), done)
    unknown = sort!(filter(id -> !haskey(rows, id), collect(keys(tags))))
    println("$(length(done)) DONE rows, $(length(done) - length(missing_)) tagged by tests")
```

Run it today and it prints:

```text
92 DONE rows, 92 tagged by tests
```

Notice the arc here. A rule written in a prompt is a **request**. The same rule enforced by a script is a **guarantee**, and the agent can run the script itself.

Whenever a prompt contains a sentence like "X must always hold", ask yourself: could a twenty-line script check X?

### Step 3: Deterministic Selection

> Pick the lowest-numbered phase prompt … that still owns `TODO` or `PARTIAL` rows and whose predecessors are complete.

Without this sentence, the agent would choose what to work on. It might choose well. It might also choose whatever looks most interesting or was discussed most recently.

The rule removes that freedom on purpose:

- **"Lowest-numbered"** respects the dependency order baked into the numbering: runtime before FFI, FFI before bindings, and so on.
- **"Still owns `TODO` or `PARTIAL` rows"** makes the matrix's phase column the source of truth for "unfinished".
- **"Whose predecessors are complete"** stops the loop from racing ahead over a broken foundation.

Determinism has a second benefit: you can *predict* the next step. Before typing `/gdjl-00-next`, we could look at the matrix, know which phase would run, and stop the loop if that wasn't what we wanted.

### Step 4: Delegation by Reference

> Read that prompt file and carry out its instructions fully.

The driver contains no knowledge about any phase. It composes with the phase prompts by *reading them*, the way a build system invokes targets.

That keeps each prompt focused. **The driver knows the process; the phase prompts know the product.**

The word "fully" is there for a reason. Without it, agents tend to stop at the first green test. With it, the phase's complete requirement list and "Done when" criteria become the bar.

### Step 5: The Report as a Handoff

> Finish by reporting: phase executed, rows changed, tests run, and remaining blockers.

The report serves two audiences:

- **you**, deciding whether to continue,
- **the next session**, which will start cold.

Its four fields let a reviewer answer the only questions that matter, in a few seconds:

- *What did you do?*
- *What changed in the spec?*
- *How do you know it works?*
- *What is in your way?*

The reports in the session history follow this shape closely. For example, the phase 4 report gives a table of rows with their new statuses and "what's left". The phase 15 report opens with what's still open before it lists what's new.

## What the Loop Produced

The best way to see the loop is through its own reports. These excerpts are verbatim from the recorded session for this repository.

### The First Run Checked State Before Doing Anything

This was on 2 November:

> **Phase:** phase 1 is still the lowest one with unfinished rows (1.2 and 1.3 are `PARTIAL`). No rows are marked `DONE` yet, so there were no stale statuses to correct.

All five steps are visible:

- step 2 ran and found nothing to correct,
- step 3 explains the choice,
- the rest of that report lists what was still building in the background and what would be checked next.

### The Selection Rule Sent the Agent Back Instead of Forward

This was on 4 November. The phase 4 report had admitted that two of its rows were still `PARTIAL`, and that a requested precompile workload was missing. The next run said:

> I finished phase 04 (bindings generator) rather than starting phase 05. Rows 2.9 and 2.12 belong only to phase 04 and were still PARTIAL, and the phase's precompile workload had never been added.

That run produced [ADR 0004](../adr/0004-editor-api-package.md), which moved the editor API into its own package.

Without step 3, the natural move would have been to start phase 5. Two rows would have stayed unfinished indefinitely.

### We Steered Through the Same Command

On 5 November we typed `/gdjl-00-next skip and remove 10.3, 10.4 and 10.5`. The report confirmed:

> **Rows 10.3, 10.4 and 10.5 (Android, iOS, Web) are removed**, as you asked, from the parity matrix and from the phase-14 prompt.

The scope change landed in both places:

- the spec (the matrix),
- the plan (the phase prompt).

So the next cold session wouldn't resurrect it.

### The Agent Used Judgment Where the Rule Ran Out

The same report said:

> I picked phase 14 because phase 13's two remaining PARTIAL rows (9.1 and 9.3) only need manual checks.

Strictly by the letter of step 3, phase 13 still owned `PARTIAL` rows. But those rows can only become `DONE` when someone attaches VS Code's debugger to a running game and walks through the checklist in [`docs/debugging.md`](../debugging.md).

The agent recognized it couldn't make progress there. It said so explicitly and moved on.

That's the right behavior. And the report put the deviation exactly where we would see it.

### An Honest Report on a Phase That Couldn't Fully Finish

From phase 15:

> I've built phase 15 (`gdjl-15-testing-ci`) and everything passes locally, but the CI and release workflows have never run on GitHub. The phase's "CI green on every matrix entry" criterion is therefore still open. The parity-test check passes: all 85 DONE rows have a tagged test.

At that point, 85 rows were `DONE`. Phase 16 brought it to 87 with the documentation and demo rows. The phase 17 audit brought it to 92 (chapter 20).

### By the Numbers

In the main session, the 51 turns break down like this:

| Kind of turn | Count | What it means |
|--------------|-------|---------------|
| `/gdjl-00-next` | 17 | The driver, including the one with an extra instruction. |
| `/gdjl-01-scaffold` | 1 | The first phase, invoked directly in the turn after the prompts were written. |
| *Continue to iterate?* | 10 | VS Code's confirmation after the agent has worked autonomously for a long stretch in one turn. |
| Terminal notifications | 16 | Long builds, test runs and exports that the agent started in the background. VS Code reported back when each finished. |
| Other | 7 | The initial request, a retry, one status question, and housekeeping (packaging, licensing, naming). |

Some driver turns produced only a one-line answer, because the agent had started a long build in the background. For example:

*"While it builds, I'll write the integration test project and a minimal harness (phase 15 will extend it)."*

The real work of such a turn continued through the terminal notifications that followed. So a phase usually spans several turns:

- one driver invocation,
- some background-command completions,
- a *Continue* or two.

## Where Reality Pushed Back

### Phases Bigger Than One Turn

Several phases needed more than one driver run. The agent stopped:

- after building the infrastructure,
- after a long build,
- when the autonomous request budget ran out.

That turned out to be harmless, *because state lived in files*. The next `/gdjl-00-next` re-read the matrix, saw the same phase still unfinished, and continued.

**The lesson:** don't try to make one invocation finish one phase. Make every invocation leave the repository in a state the next one can pick up.

### Rows That Can't Become `DONE` Locally

Some `PARTIAL` rows can never be finished from a laptop:

- Rows 1.3 and 1.7 need CI runs on GitHub, and the repository isn't published yet.
- Row 10.2 needs Linux and macOS runners.
- Rows 9.1 and 9.3 need a human at the keyboard.

A literal reading of step 3 would leave the loop stuck on phase 1 forever, because row 1.3 is co-owned by phases 01, 14 and 15.

In practice, the agent handled this with explicit reasoning. For example: "Row 1.3 stays `PARTIAL` because publishing the package to a registry belongs to phase 14."

If you write your own driver, make this explicit. Mark rows that need external evidence (for example "PARTIAL — needs CI"), and tell the selection step to skip them.

### Multi-Owner Rows

Some rows are owned by several phases:

- 1.7 (precision: phases 03, 05 and 15),
- 4.10 (threads: 02, 07 and 10).

Each phase completes its share and leaves a note. That works, but only because the notes in the status column are detailed. For example: *"bindings + math verified … CI job … has not run yet."*

A bare `PARTIAL` would force every session to rediscover what's missing.

### Not Seeing Progress

Long phases run builds and test suites for many minutes. Late in phase 16, we asked: *"Task manager says that not much is going on"*.

The answer: the integration tests had already finished (11 of 11 passed with leak checks). The slower demo and doc-test runs were still going in the background.

Visibility is part of the loop's design. So:

- prefer commands that log to files,
- run long jobs asynchronously,
- have the agent say what's still running when it ends a turn.

## Closing the Loop

`gdjl-00-next` contains no tests of its own. Instead, it makes every other test in the repository part of its decision-making:

- **Step 2** runs, or at least inspects, the tests that back each `DONE` row. Since phase 15, `julia scripts/check_parity_tests.jl` does the structural part in a second.
- **Step 4** inherits each phase's tests and "Done when" criteria.
- **Step 5** requires the agent to report *which* tests it ran, so you can check that the oracle was actually consulted.

The full local **oracle** is one command: `julia scripts/test_all.jl`. It:

- builds the native host,
- generates bindings,
- runs unit tests, the parity check, integration tests with leak checks, doc tests and demos.

## The Same Pattern, One Level Up

This book was produced with the same pattern. [`book-next`](../../.github/prompts/book/book-next.prompt.md) maps onto the driver step by step:

- it reads a shared [book guide](../../.github/prompts/book/book-guide.md) (the instructions),
- compares `docs/book/` against the guide's output table (the matrix),
- picks the lowest missing chapter (deterministic selection),
- runs that chapter's prompt (delegation by reference),
- reports word count, sources and dropped claims (the handoff).

The domain is completely different. The loop is identical. It's a general technique, not a trick for one project.

## How This Relates to VS Code's Built-in Agents and Autonomy Settings

As of VS Code 1.145, the editor itself offers some of these ideas:

- The **Plan** agent researches a task and produces an implementation plan for you to review. That's useful *inside* a phase, but it doesn't persist state between sessions. The parity matrix does.
- **Autopilot** lets the agent work until it decides the task is complete. It auto-approves tools, retries on errors and answers its own blocking questions. In the Copilot harness it's an agent mode. In the Local harness, which runs the prompt files in this repository, it's a permission level. An *Allow all* permission level skips approval prompts without the other behaviors.
- In this project, we stayed in the loop *between* phases: we read each report before the next `/gdjl-00-next`. Within a phase, the agent ran long stretches on its own, interrupted only by *Continue to iterate?*

Here's a reasonable rule of thumb:

- give the agent autonomy *within* a well-specified phase with executable "Done when" criteria,
- review *between* phases, where scope decisions get made.

Autopilot is attractive for long runs, but it auto-approves potentially destructive actions. Use it in workspaces you trust, preferably with sandboxing enabled, and read the report afterwards.

## Techniques to Reuse

- **State in files, not in chat.** Re-read the plan and status from versioned files at the start of every run, so any session can resume.
- **Verify before you build.** Make the first step of every run a check of previously claimed results against code and tests.
- **Turn rules into scripts.** When a prompt says "X must always hold", write the checker and let the agent run it (`check_parity_tests.jl`).
- **Deterministic next step.** Define "what to do next" so precisely that you can predict it, and make exceptions visible in the report.
- **Delegate by reference.** Keep the driver ignorant of the domain. Let it compose specialized prompts by reading them.
- **Structured handoff.** End every run with the same few fields (what was done, what changed in the spec, which tests ran, what's blocking), for the reviewer and the next cold session.

## Try It Yourself

1. Select the **Ask** agent (it can't edit files) and type `/gdjl-00-next`. Note which phase it would pick and whether it would correct any statuses. Then check its reasoning against the matrix. Rows 9.1, 9.3 and 10.2 are good tests of whether it understands "needs a human" and "needs CI".
2. Run `julia scripts/check_parity_tests.jl`. Then, in a scratch copy of the repository, delete one `# parity:` tag from a test file and run it again. Watch the rule get enforced.
3. Write a three-row parity matrix for a small task of your own, with a reference to match, an owner, and a strict definition of `DONE`. Add a five-line driver prompt modeled on the one above. Let the agent take the first step.

## Parity Rows

The driver owns no rows. Here's the matrix it drove, as of this writing:

| Section | Rows | DONE | PARTIAL |
|---------|------|------|---------|
| 1. Runtime, Packaging, Build | 8 | 6 | 2 (1.3, 1.7) |
| 2. Generated Engine API | 12 | 12 | 0 |
| 3. Builtin Types | 13 | 13 | 0 |
| 4. Object Model & Lifetime | 10 | 10 | 0 |
| 5. Scripting | 19 | 19 | 0 |
| 6. Signals & Async | 6 | 6 | 0 |
| 7. Hot Reload | 5 | 5 | 0 |
| 8. Editor Integration | 8 | 8 | 0 |
| 9. Debugging & Diagnostics | 5 | 3 | 2 (9.1, 9.3) |
| 10. Export & Deployment | 5 | 3 | 2 (10.2, 10.6) |
| 11. Documentation & Samples | 2 | 2 | 0 |
| **Total** | **93** | **87** | **6** |

No rows are `TODO` or `GAP`. Rows 10.3–10.5 (Android, iOS, Web) were removed by the scope decision described above.

---
[← Previous: The Repository and Its Prompt System](02-repository-and-prompt-system.md) · [Contents](README.md) · [Next: Scaffolding →](04-scaffold.md)
