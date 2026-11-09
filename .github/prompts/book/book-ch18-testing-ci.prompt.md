---
name: book-ch18-testing-ci
description: "Book chapter 18: the logic behind gdjl-15-testing-ci — one-command testing, in-engine Julia tests, parity tags, leak checks, benchmarks and CI."
agent: agent
---
Write chapter 18 of the book, `docs/book/18-testing-ci.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-15-testing-ci](../gdjl-15-testing-ci.prompt.md).

## Focus

- **Turning a convention into an enforced check.** "No row may stay `DONE` without a test" became `scripts/check_parity_tests.jl` with `# parity: x.y` tags. This is the strongest guard against an agent over-reporting progress. Link back to chapter 3.
- **Machine-readable results.** `GDJL_TEST_RESULT {json}` emitted by an in-engine runner (`julia/GodotTestRunner`), and failing on any unexpected `ERROR:`. Agents read structured output far more reliably than logs.
- **One command for everything** (`julia scripts/test_all.jl [--exports] [--benchmarks]`). The same entry point serves humans, agents and CI.
- **Honest statuses for what cannot run yet.** CI and release workflows exist, but their rows stay `PARTIAL` until the repository is published (rows 1.3, 1.7, 10.2). The book should show this as a virtue.
- **Consolidation as a phase.** Why testing is consolidated late, even though every phase shipped tests.

## Leads to Verify

- Julia 1.13 `Test` has no `push_testset`, so the runner uses `@testset EngineTestSet "name"`.
- Julia 1.12 lacks `jl_get_libjulia_internal_path` (the host falls back to the standard path). 1.12 checks use `julia +1.12` for the runner and `JULIA_BINDIR` for the host.
- Leak checks via `--leaks`. The stock editor leaves an orphan `StringName` "Node", which is explicitly ignored. Document expected noise rather than suppressing everything.
- License headers: `julia scripts/license_headers.jl --check` runs in `test_all`. Headers shift fixture line numbers (+3) in integration expectations.
- Operational lessons: never start integration tests while a timed-out run is still alive (Godot keeps the addon DLL locked, causing ENOTEMPTY), and a syntax error in an integration main script shows up as a timeout (check `.godot/gdjl_test.log`).

## Artifacts to Inspect

`scripts/test_all.jl`, `scripts/check_parity_tests.jl`, `tests/integration/run.jl`, `julia/GodotTestRunner/`, `tests/benchmarks/`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `scripts/package_addon.jl`, `README.md` (the testing section).

## Try It Yourself

Remove a `# parity:` tag from a test file (in a scratch branch), run `julia scripts/check_parity_tests.jl`, and ask the agent to explain and fix the failure.

Parity rows: list every row whose phase column includes 15, with its current status. Navigation: previous chapter 17, next chapter 19.
