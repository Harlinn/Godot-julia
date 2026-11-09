# Book Guide — "Building a Language Runtime with an AI Pair Programmer"

Shared rules for every `book-*.prompt.md` prompt in this folder. Read this file completely before writing or revising any chapter.

## Purpose

Write a book/tutorial about AI-assisted software engineering with GitHub Copilot in VS Code, using Claude Opus 5.5 and other frontier models. It uses this repository, [Godot-julia](https://github.com/Harlinn/Godot-julia), as the worked example. The repository was built phase by phase by an AI agent driven by the prompt files in [`.github/prompts/`](..). The book explains **why those prompts are shaped the way they are**, what the agent produced, where it went wrong, and which techniques readers can reuse in their own projects.

Working title (the finalize prompt may refine it): *Building a Language Runtime with an AI Pair Programmer — Lessons from Godot-julia*.

## Audience

- Experienced developers who have used chat-based AI assistants but not long-running, agentic, multi-phase work.
- Technical leads who decide how teams adopt AI coding agents.
- No prior Godot, Julia or GDExtension knowledge is assumed. Explain domain concepts briefly when they first appear, and only to the depth the AI-coding lesson needs.

## Voice and Style

- Second person ("you") for the reader, first person plural ("we") for the reader and author together or for the people who drove the project. Never use third-person phrasing such as "the author typed", "the user should" or "readers". Refer to the AI explicitly as "the agent" or "Copilot". Do not anthropomorphize beyond that.
- Tone: a friendly senior developer mentoring a junior peer. Action-oriented, encouraging and clear.
- Be honest and concrete. Show failures as clearly as successes, since the failures carry most of the lessons. No hype, no marketing adjectives, no claims of "10x".
- Short sentences and short paragraphs. Bold key terms on first use. Use bullet lists for enumerations. Prefer concrete examples and file links over abstract advice.
- Tutorial steps (especially *Try it yourself*) use imperatives: "Open the Ask agent", "Run the script".
- GitHub-flavored Markdown. Exactly one `#` H1 per file (the chapter title). Use `##`/`###` for sections.
- Mermaid diagrams are welcome where they clarify flow (GitHub renders them). Keep them small.
- Code excerpts: at most ~30 lines each, always preceded by a link to the source file. Use language-tagged fences (`julia`, `cpp`, `gdscript`, `json`, `powershell`, `markdown`). Book code blocks are **not** doc-tested (`scripts/doctest_docs.jl` only covers `docs/user/`), so copy excerpts verbatim from the repository instead of writing new code.
- Quote prompt files verbatim when analyzing them (they are short). Use a fenced `markdown` block.
- Target length: phase chapters 2,500–5,000 words; chapters 1–2 may be longer if the content warrants it.

## Evidence Rules (non-negotiable)

1. Every factual statement about this repository must be checked against the repository: code, ADRs in [`docs/adr/`](../../../docs/adr), the [parity matrix](../../../docs/csharp-parity-matrix.md), [`docs/perf.md`](../../../docs/perf.md), tests, scripts and prompts. Numbers (class counts, timings, sizes) are copied from those sources, not estimated.
2. The "leads" listed in each chapter prompt are **hints to verify, not facts to copy**. Drop any lead you cannot confirm in the repository.
3. Optional richer sources, used only when available in the current environment:
   - Repository memory notes (`/memories/repo/`) maintained by the agent during implementation.
   - Copilot session history (for example the Chronicle session store). Query **only** sessions whose workspace is this repository, and use them to reconstruct what actually happened: the order of events, retries, and user corrections. Never quote anything from sessions belonging to other workspaces.
   If neither source is available, say less rather than inventing it.
4. Never invent sessions, dialogues, timings, costs, token counts, model comparisons or benchmark results. When you describe what a model "tends to do", mark it as the author's observation and keep it general.
5. Mark interpretation as interpretation ("A plausible reason is…").
6. When the book describes VS Code or Copilot features (built-in agents Agent/Ask/Plan, harnesses, prompt files, custom instructions, skills, memory, subagents, MCP), check the current behavior against the official docs at `https://code.visualstudio.com/docs` before writing. Features change between releases. Name the VS Code version you verified against.
7. When the book describes Godot's C# implementation, fetch the referenced file from `godotengine/godot` at the tag in [`GODOT_VERSION`](../../../GODOT_VERSION) instead of relying on memory.

## Confidentiality Rules (non-negotiable)

Chapter 2 compares this repository with a set of **private repositories** supplied at runtime through a prompt input. They are confidential.

- Never write their path, repository names, project, product, system, customer or organization names, people, hostnames, URLs, identifiers, package or class names, file names, code, configuration values, schema names, ticket numbers or domain-specific terminology into **any** file, including the book, notes, todo lists, memory files and commit messages.
- Refer to them only as **"a private enterprise portfolio"** (or "the comparison portfolio").
- Report only aggregated, anonymized, order-of-magnitude observations, for example: "many repositories", "a long-lived enterprise stack", "builds depend on infrastructure not available on a developer machine". Name technology only at a broad category level, never by product or version.
- Read them with read-only tools. Do not run, build, copy or modify anything there, and do not send their content to web tools.
- Before finishing any chapter that touches the comparison, run the confidentiality scan described in [book-finalize](book-finalize.prompt.md#confidentiality-scan).

## Output Layout

All output goes in [`docs/book/`](../../../docs/book). One file per chapter:

| File | Chapter | Produced by |
|------|---------|-------------|
| `README.md` | Title page, preface, table of contents, how to use the prompts | `book-finalize` |
| `01-why-ai-coding.md` | 1. Motivation | `book-ch01-motivation` |
| `02-repository-and-prompt-system.md` | 2. The repository and its prompt system | `book-ch02-overview` |
| `03-the-resume-loop.md` | 3. `gdjl-00-next` | `book-ch03-next` |
| `04-scaffold.md` | 4. `gdjl-01-scaffold` | `book-ch04-scaffold` |
| `05-embed-runtime.md` | 5. `gdjl-02-embed-runtime` | `book-ch05-embed-runtime` |
| `06-ffi-layer.md` | 6. `gdjl-03-ffi-layer` | `book-ch06-ffi-layer` |
| `07-bindings-generator.md` | 7. `gdjl-04-bindings-generator` | `book-ch07-bindings-generator` |
| `08-builtin-math.md` | 8. `gdjl-05-builtin-math` | `book-ch08-builtin-math` |
| `09-variant-collections.md` | 9. `gdjl-06-variant-collections` | `book-ch09-variant-collections` |
| `10-object-model.md` | 10. `gdjl-07-object-model` | `book-ch10-object-model` |
| `11-script-language.md` | 11. `gdjl-08-script-language` | `book-ch11-script-language` |
| `12-authoring-macros.md` | 12. `gdjl-09-authoring-macros` | `book-ch12-authoring-macros` |
| `13-signals-async.md` | 13. `gdjl-10-signals-async` | `book-ch13-signals-async` |
| `14-hot-reload.md` | 14. `gdjl-11-hot-reload` | `book-ch14-hot-reload` |
| `15-editor-integration.md` | 15. `gdjl-12-editor-integration` | `book-ch15-editor-integration` |
| `16-debugging.md` | 16. `gdjl-13-debugging` | `book-ch16-debugging` |
| `17-export.md` | 17. `gdjl-14-export` | `book-ch17-export` |
| `18-testing-ci.md` | 18. `gdjl-15-testing-ci` | `book-ch18-testing-ci` |
| `19-docs-demos.md` | 19. `gdjl-16-docs-demos` | `book-ch19-docs-demos` |
| `20-parity-audit.md` | 20. `gdjl-17-parity-audit` | `book-ch20-parity-audit` |

Links: use paths relative to the chapter file (for example `../../.github/prompts/gdjl-01-scaffold.prompt.md`, `../adr/0002-runtime-loading.md`, `../../native/src/`) so they work both locally and on GitHub. Use absolute `https://github.com/godotengine/godot/blob/<tag>/...` links for upstream Godot files.

Every chapter ends with a navigation line:

```markdown
---
[← Previous: <title>](<file>) · [Contents](README.md) · [Next: <title> →](<file>)
```

## Phase Chapter Template (chapters 4–20)

Use these sections in order. Adapt the headings, but keep the substance.

1. **Opening.** What the phase delivers, in one or two paragraphs, why it sits at this point in the phase order, and what would break if it ran earlier.
2. **The prompt.** The complete prompt file verbatim, with a link to it.
3. **Anatomy of the prompt.** Walk through each element and explain the reasoning behind it: frontmatter (`name`, `description`, `argument-hint`, `agent`, `${input:…}` variables), the link to the project instructions, the behavioral reference into `modules/mono`, numbered requirements, explicit scope fences ("do not add…"), tests, "Done when" criteria, and the parity rows the phase owns. For each element, state the failure mode it prevents.
4. **What the agent built.** A guided tour of the resulting artifacts: directories, key files, the ADR, tests. Use short excerpts and links. Note where the implementation deliberately deviated from the prompt, and why (check the ADR).
5. **Where reality pushed back.** Verified problems found during the phase: engine quirks, platform issues, wrong assumptions in the prompt, bugs discovered later. For each one, cover the symptom, the diagnosis, the fix, and the lesson for prompting.
6. **Closing the loop.** How the phase's tests and tools verify the work (commands, harness, parity tags). Explain why an agent needs an executable oracle.
7. **Techniques to reuse.** A short list of 3–6 named, transferable prompting/engineering techniques shown in this chapter, each with one sentence of guidance.
8. **Try it yourself.** A small, concrete exercise the reader can run with Copilot against this repository (for example "ask the Ask agent to explain X", "use the Plan agent to design Y", "re-run `/gdjl-NN` in a branch and compare"). Use commands that exist in the repository.
9. **Parity rows.** A table of the matrix rows the phase owns, with their current status copied from the matrix.

## Definition of Done for a Chapter

- File written at the path in the table, with the navigation line.
- Every repository link resolves (check with a file search) and every number is traceable.
- Confidentiality scan passed if the chapter mentions the comparison portfolio.
- A one-line entry for the chapter is reported back (title, word count, open questions) so `book-finalize` can build the table of contents.
