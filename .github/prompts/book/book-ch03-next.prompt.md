---
name: book-ch03-next
description: "Book chapter 3: the logic behind gdjl-00-next, the resumable driver prompt that turns a parity matrix into an autonomous work loop."
agent: agent
---
Write chapter 3 of the book, `docs/book/03-the-resume-loop.md`, following the [book guide](book-guide.md). Use the phase chapter template. The "What the agent built" section becomes "What the loop produced".

Source prompt: [gdjl-00-next](../gdjl-00-next.prompt.md).

## Focus

This five-step prompt is the engine of the whole project. Explain why such a short prompt works, and which surrounding artifacts make it work:

1. **State lives in the repository, not the chat.** Each run starts with a fresh context. The matrix, ADRs and tests carry state between sessions, which makes the loop resumable, restartable and auditable.
2. **"Verify the matrix is accurate" (trust, but verify).** A row marked `DONE` must have code and a passing test. This guards against stale statuses and optimistic self-reports. Later this became mechanical: `scripts/check_parity_tests.jl` with `# parity: x.y` tags (phase 15). Show the evolution from a written rule to an enforced rule.
3. **Deterministic selection.** "Lowest-numbered phase that still owns `TODO` or `PARTIAL` rows and whose predecessors are complete" removes ambiguity about what to do next and respects dependencies.
4. **Delegation by reference.** "Read that prompt file and carry out its instructions fully": composition of prompts, and one driver for all phases.
5. **The report as a handoff.** "Phase executed, rows changed, tests run, remaining blockers" is a structured summary for the human reviewer and the next session.

## Discuss Also

- How the loop relates to VS Code's built-in Plan and Agent agents and to autonomous permission modes (verify the current names in the docs). When should a human review between iterations?
- Failure modes: a phase too large for one context window, `PARTIAL` rows that can never become `DONE` locally (for example CI rows that need a published repository; see matrix rows 1.3, 1.7), and the agent picking the wrong phase when the matrix drifts.
- How the same pattern drives this book: compare with [book-next](book-next.prompt.md).
- If session history for this workspace is available, show how often `gdjl-00-next` was invoked versus a specific phase prompt directly, and what the reports looked like. Otherwise skip this.

## Try It Yourself

Run `/gdjl-00-next` in Ask or Plan mode (no edits) and compare its chosen phase and matrix corrections with the actual matrix. Then design a three-row parity matrix for a small project of the reader's own.

Parity rows: none owned. Instead, show the current status counts of the matrix. Navigation: previous chapter 2, next chapter 4.
