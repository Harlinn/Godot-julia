---
name: book-ch01-motivation
description: "Book chapter 1: a motivational opening on agentic AI coding, grounded in what was built in Godot-julia."
agent: agent
---
Write chapter 1 of the book, `docs/book/01-why-ai-coding.md`, following the [book guide](book-guide.md). This chapter does **not** use the phase template.

## Goal

Make an experienced, possibly skeptical developer want to read on. Then give them a realistic mental model of what agentic AI coding with GitHub Copilot and frontier models (Claude Opus 5.5 and others) can and cannot do today. Motivate with evidence from this repository, not with hype.

## Gather Evidence First

- Read the [README](../../../README.md), the [project instructions](../../copilot-instructions.md), and the [parity matrix](../../../docs/csharp-parity-matrix.md). Count rows by status.
- Collect scale indicators from the repository: generated API size (matrix row 2.1), number of integration test projects under `tests/integration/`, ported demos under `demos/`, user doc pages under `docs/user/`, ADR count, and supported workflows (editor, hot reload, debugging, export). Copy numbers; don't estimate them.
- If session history for this workspace is available, establish the real timeline and how much human steering was needed. Otherwise leave dates and durations out.

## Suggested Structure

1. **A hook.** The ambition stated plainly. Making a new language a first-class Godot scripting language, at feature parity with C#, used to be a multi-person, multi-year effort. Here it was driven by one developer and a sequence of 18 prompt files. Show the final result concretely: a short `@godot_class` script from a demo (for example under `demos/dodge_the_creeps/`), with a link.
2. **What changed.** The move from autocomplete, to chat, to agents that read code, run builds and tests, fetch reference sources, and iterate. Explain why a feedback loop (compile, run, test) matters more than raw model intelligence.
3. **What did not change.** Architecture, scope, taste, verification and accountability remain human responsibilities. Frame the human as the specifier, reviewer and owner of decisions (ADRs).
4. **The honest ledger.** What went smoothly and what needed repeated correction, at a high level, pointing forward to the chapters that tell those stories. Mention that the parity matrix still records `PARTIAL` and `GAP` items, and why that honesty is a feature.
5. **Why this project is a good teacher.** It is a demanding, low-level problem: FFI, garbage collection across two runtimes, threads, an editor, exports. Its success criteria are objective (parity with an existing, public reference implementation). Keep the comparison with private codebases for chapter 2; just foreshadow it here.
6. **How to read this book.** Chapter 2 explains the repository and the prompt system. Chapters 3–20 each dissect one prompt. Every chapter ends with reusable techniques and a hands-on exercise. Say what readers need installed to follow along (from the README).
7. **A call to action.** Encourage readers to apply one technique to their own project by the end of chapter 3.

## Constraints

- No unverifiable productivity multipliers. No disparaging other tools or models.
- Keep any "AI will replace developers" debate to at most one balanced paragraph.
- Navigation line: no previous link; next is chapter 2.
