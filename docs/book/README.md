# Building a Language Runtime with an AI Pair Programmer

*Lessons from Godot-julia: agentic software engineering with GitHub Copilot in VS Code*

Espen Harlinn

This book is part of the [Godot-julia](https://github.com/Harlinn/Godot-julia) repository and shares its license: the Apache License 2.0 (see [`LICENSE`](../../LICENSE) and [`NOTICE`](../../NOTICE)). Excerpts of Godot's source code are MIT licensed, © Godot Engine contributors. Each one is quoted with a link to its source file.

## Preface

This book is about working with an **AI coding agent** on a project that's too large to finish in one conversation.

The worked example is this repository. It's a **GDExtension** that makes Julia a scripting language for the Godot game engine. The goal: feature parity with Godot's C# support.

An agent wrote most of the code, phase by phase, driven by the prompt files in [`.github/prompts/`](../../.github/prompts). In the chapters ahead, we'll look at:

- why those prompts are shaped the way they are,
- what the agent built,
- where it went wrong,
- which techniques carry over to your own projects.

**Who it is for.**

- Experienced developers who have used chat-based AI assistants, but not for long-running, agentic, multi-phase work.
- Technical leads deciding how their teams should adopt coding agents.

You don't need to know Godot, Julia or GDExtension. Each chapter explains the domain concepts it needs, and no more.

**What you will learn.**

- How to turn an open-ended goal into a **specification the agent can check**: a parity matrix against a public reference.
- How to write instructions, phase prompts and a **resumable driver prompt** that survive many sessions.
- How to give the agent **executable oracles**: tests, golden values, leak checks, and scripts that enforce conventions.
- How to record decisions in **ADRs** so later sessions don't reopen them.
- How to recognize **what stays human**: choosing the goal, setting the rules, making scope calls, and owning the result.

Chapter 2 also covers why the same agent does much worse on many enterprise codebases, and what you can change about that.

**What it was written against.**

- VS Code 1.145 (November 2026) with GitHub Copilot, using Claude Opus 5.5. The techniques aren't tied to one model; we describe them so they carry over to other frontier models.
- Godot 4.7.2-stable, pinned in [`GODOT_VERSION`](../../GODOT_VERSION).
- Julia 1.12 or later, as the repository requires. The work itself was done with Julia 1.13.3 on Windows.

## Contents

| # | Chapter | Summary |
|---|---------|---------|
| 1 | [Why AI Coding Deserves Your Attention](01-why-ai-coding.md) | What an agent built here, what stayed human, and an honest preview of the problems along the way. |
| 2 | [The Repository and Its Prompt System](02-repository-and-prompt-system.md) | Instructions, parity matrix, phase prompts, ADRs and tests through an agent's eyes, and why Copilot does far better here than on a private enterprise portfolio. |
| 3 | [The Resume Loop: `gdjl-00-next`](03-the-resume-loop.md) | The five-step driver prompt that turns the parity matrix into a resumable work loop, and how it behaved in practice. |
| 4 | [Scaffolding: Decisions Before Code](04-scaffold.md) | Pin versions, choose the delivery model and build system, and record it all in ADRs before writing features. |
| 5 | [Embedding the Runtime: Invariants First](05-embed-runtime.md) | Hosting `libjulia` inside a GDExtension, with exception, GC and threading invariants as deliverables, and a prompt that turned out to be wrong. |
| 6 | [The FFI Layer: Generated, Measured, Owned](06-ffi-layer.md) | A generated binding to Godot's C interface. Allocation-free hot paths are a measured acceptance criterion, and ownership rules live next to the code. |
| 7 | [The Bindings Generator: Scale Through Generation](07-bindings-generator.md) | Why the agent wrote a generator instead of 269,000 lines of bindings, and how delegated design decisions were recorded. |
| 8 | [Builtin Math: The Engine as the Oracle](08-builtin-math.md) | Porting Godot's math types with golden values computed by the engine itself, and following ground truth when the C# port disagreed. |
| 9 | [Variant and Collections: Semantics, Stated Precisely](09-variant-collections.md) | Conversions, typed collections and lifetimes: specified in the prompt, verified by round-trips through the engine. |
| 10 | [The Object Model: Two Garbage Collectors, One Object](10-object-model.md) | Object identity, lifetime and threading across two memory managers, and a bug that waited five phases to surface. |
| 11 | [The Script Language: Exhaustive Checklists and Thin Shims](11-script-language.md) | Implementing Godot's script language interface from an enumerated checklist, with a thin C++ shim over Julia. |
| 12 | [Authoring Macros: Attributes, Generators and Analyzers in Julia](12-authoring-macros.md) | Mapping C# attributes, source generators and analyzers onto Julia macros and diagnostics, and keeping downstream prompts current. |
| 13 | [Signals and Async: Translating a Concurrency Model](13-signals-async.md) | Signals with Julia closures, awaiting signals, and worker threads, all built from Julia's own concurrency machinery. |
| 14 | [Hot Reload: Working With the Language, Not Against It](14-hot-reload.md) | Reloading scripts with their state by porting C#'s reload policy, not its mechanism. |
| 15 | [Editor Integration: UX Parity as a Specification](15-editor-integration.md) | Build panel, project tooling and editor features, specified as a mapping from what C# developers see and tested headlessly. |
| 16 | [Debugging: Parity Where Possible, Honesty Where Not](16-debugging.md) | Script errors, stack frames and a debug REPL, plus manual checks and limits that were written down instead of faked. |
| 17 | [Export: Shipping a Language Runtime](17-export.md) | Packaging Julia and compiled scripts into exported games, and a sanctioned exit for a requirement that proved infeasible. |
| 18 | [Testing and CI: Making Progress Checkable](18-testing-ci.md) | One test entry point for humans, agents and CI, and the convention "no `DONE` without a test" turned into a failing check. |
| 19 | [Documentation and Demos: Docs That Run, Games That Test](19-docs-demos.md) | A user guide where every example is executed, and ports of the official C# demos used as acceptance tests. |
| 20 | [The Parity Audit: Re-Checking the Spec, and the Claims](20-parity-audit.md) | Re-deriving the specification from source, auditing the audit tool, and lessons from the whole project. |

## How This Book Was Written

We generated the book with the same **resumable pattern** as the implementation it describes. The prompts live in [`.github/prompts/book/`](../../.github/prompts/book):

| Prompt | Purpose |
|--------|---------|
| [`book-guide.md`](../../.github/prompts/book/book-guide.md) | Shared rules for every chapter: audience, voice, evidence rules, confidentiality rules, output layout and the phase chapter template. Not a command itself. |
| [`book-next`](../../.github/prompts/book/book-next.prompt.md) | The driver: finds the lowest-numbered missing or incomplete chapter and runs its prompt. |
| `book-ch01-motivation` … `book-ch20-parity-audit` | One prompt per chapter, with leads to verify (not facts to copy) and the chapter's focus. |
| [`book-finalize`](../../.github/prompts/book/book-finalize.prompt.md) | This page, the consistency and link checks, fact spot checks, and the confidentiality scan. |

To regenerate the whole book:

- Open the repository in VS Code in a **Local** harness session. Prompt files run as slash commands there (see chapter 2).
- Run `/book-next` repeatedly until it reports that all chapters exist.
- Run `/book-finalize`.

To rewrite a single chapter, delete its file or run its prompt directly, for example `/book-ch07-bindings-generator`.

Chapter 2 and the finalization step ask for the path of the private comparison repositories. That path is used only for reading and scanning. It's never written to any file.

Every factual statement was checked against the repository at the time of writing: code, ADRs, the parity matrix, tests, scripts and prompts. Where Copilot session history for this repository was available, we used it to reconstruct the order of events. Quoted prompts match the current files in [`.github/prompts/`](../../.github/prompts).

## Prerequisites for the Exercises

Every chapter ends with a *Try it yourself* exercise against this repository.

Many exercises only ask the Ask or Plan agent to explain or plan something. For those, a clone is all you need.

Exercises that build or run code need the tools listed in the repository [README](../../README.md#prerequisites):

- the pinned Godot editor,
- Julia 1.12 or later,
- Python with SCons,
- a C++ toolchain,
- VS Code with GitHub Copilot.

The README also shows you how to build the native host, generate the bindings and run the tests.

---
[Start reading: Why AI Coding Deserves Your Attention →](01-why-ai-coding.md)
