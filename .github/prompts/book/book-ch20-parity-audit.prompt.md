---
name: book-ch20-parity-audit
description: "Book chapter 20: the logic behind gdjl-17-parity-audit — refreshing the spec from upstream, diffing the API surface, and fixing or justifying every gap."
agent: agent
---
Write chapter 20 of the book, `docs/book/20-parity-audit.md`, following the [book guide](book-guide.md) and its phase chapter template. This is the final chapter, so close the book as well as the phase.

Source prompt: [gdjl-17-parity-audit](../gdjl-17-parity-audit.prompt.md).

## First, Establish the Status

Check whether phase 17 has been executed (for example, whether `scripts/api_diff.jl` exists and whether the matrix shows an audit against the current `GODOT_VERSION`). If it has not run yet, write "What the agent built" as "What the audit will produce", describe the expected outputs from the prompt, and say plainly that the audit is pending. Never describe results that do not exist.

## Focus

- **The spec moves.** Upstream Godot keeps changing C#. The audit re-fetches `modules/mono`, the docs and the changelog at a tag, and diffs them against the matrix. This turns a one-off port into a maintainable process.
- **Trust nothing without evidence.** "Downgrade statuses that are not backed by passing tests." The audit re-verifies the agent's earlier claims.
- **Tool-assisted audits.** `scripts/api_diff.jl` compares GodotSharp's public members with the Julia names, using the documented naming rules. Let tools enumerate and let the agent judge.
- **Fix or justify.** Every `GAP` needs an ADR with a workaround. Clear exit criteria: no `TODO`/`PARTIAL` row without an owner and a plan.
- **Re-pinning.** Updating `GODOT_VERSION` and regenerating bindings shows the value of the generator-first design (chapter 7).

## Closing the Book

After the phase template, add a final section, "Lessons Across the Whole Project". Synthesize the techniques from chapters 3–20 into a compact playbook (about 10–15 items, each linked to the chapter that shows it). Then give a short, honest outlook on what still needs a human and what the next generation of models and tools might change. Keep the outlook labeled as opinion.

## Artifacts to Inspect

`docs/csharp-parity-matrix.md` (counts by status, every `GAP`/`PARTIAL` row and its ADR), `docs/adr/`, `GODOT_VERSION`, `scripts/check_parity_tests.jl`, and `scripts/api_diff.jl` if it exists.

## Try It Yourself

Run `/gdjl-17-parity-audit` in Plan mode against the pinned tag, review its proposed matrix changes before allowing any edits, and record how many it found.

Parity rows: summarize the whole matrix by status and list the remaining `PARTIAL`/`GAP` rows. Navigation: previous chapter 19, no next link (link to Contents only).
