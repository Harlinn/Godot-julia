---
name: gdjl-15-testing-ci
description: "Phase 15: consolidate the test suite and CI matrix for Godot+Julia (unit, headless integration, golden math tests, leak checks, exports)."
agent: agent
---
Consolidate testing and CI. Follow the [project instructions](../copilot-instructions.md). Reference for structure: Godot's own CI for the .NET build (`.github/workflows/` in godotengine/godot, especially the mono/glue generation and `build_assemblies.py` steps).

## Requirements

1. **Test harness**: `tests/integration/run.jl` that discovers each project under `tests/integration/`, runs `godot --headless --path <proj>` with a timeout, parses a machine-readable result line (`GDJL_TEST_RESULT {json}`) emitted by a test-runner autoload written in Julia, and fails on any Godot `ERROR:` not explicitly expected.
2. **In-engine Julia test runner**: lets integration projects use `Test` (`@testset`, `@test`) inside the running engine and reports through the result line.
3. **Coverage of phases**: ensure every `DONE` row in the [parity matrix](../../docs/csharp-parity-matrix.md) is referenced by at least one test; add a script `scripts/check_parity_tests.jl` that verifies test files tag the rows they cover (e.g. `# parity: 5.6`).
4. **Golden fixtures**: regeneration script for builtin-math fixtures from Godot (phase 05).
5. **Leak & sanitizer jobs**: run integration tests with `--verbose` and fail on "ObjectDB instances leaked" / "resources still in use"; optional ASAN build of `native/`.
6. **Performance regression**: benchmarks for method call overhead, property access, signal emit, Variant conversion, and script `_process` dispatch; compare against stored baselines and against equivalent C# numbers when available (document how they were measured).
7. **CI workflow** (`.github/workflows/ci.yml`): matrix over OS (windows, ubuntu, macos), precision (single, double), Julia (current stable, plus LTS if supported); steps: fetch pinned Godot, build `native/`, generate bindings, Julia unit tests, integration tests, export tests (phase 14). Cache Julia depot and SCons cache.
8. **Release workflow**: build the addon zip for all platforms and attach to a GitHub release; publish `Godot` Julia package version.

## Done when

- CI is green on all matrix entries, and the parity-test check passes.
- Contributors can run everything locally with one command documented in `README.md`.

Update the matrix: no row may stay `DONE` without a test.
