# 18. Testing and CI: Making Progress Checkable

Every phase so far shipped with tests. The project instructions demand it (*"Each feature ships with tests"*), and every chapter of this book has a "Closing the Loop" section that shows them.

So why does the project need a whole phase about testing, this late?

Because tests written phase by phase answer one question: "does this feature work?" They don't answer the questions a reviewer asks at the end:

- Does *everything* still work?
- Can I run it all with one command?
- Does every claim of `DONE` in the parity matrix actually have a test behind it?

Phase 15 turns a collection of per-phase test suites into **one checkable system**. Along the way, it turns the project's most important convention into a script that fails.

## The Prompt

[`.github/prompts/gdjl-15-testing-ci.prompt.md`](../../.github/prompts/gdjl-15-testing-ci.prompt.md):

```markdown
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
```

## Anatomy of the Prompt

### "Consolidate", Not "Create"

The first word sets the job. Most of the pieces already existed:

- an integration runner since the scaffold (chapter 4),
- golden math fixtures since phase 5 (chapter 8),
- unit test suites in every package.

Requirement 4 even says to reuse the phase 5 script. The phase is about joining these pieces into something uniform.

This is a useful way to scope late phases in any agent-driven project. Early phases each build their own scaffolding. A later phase standardizes it, once you know what the scaffolding needs to do.

### The Convention Becomes a Script

The last line, *"no row may stay `DONE` without a test"*, restates a rule that every phase has followed since chapter 3. Requirement 3 turns it into a tool: `scripts/check_parity_tests.jl`, which *"verifies test files tag the rows they cover (e.g. `# parity: 5.6`)"*.

That difference matters more than anything else in this phase.

- A **convention** is something an agent *should* follow.
- A **check** is something that *fails* when it doesn't.

Chapter 3 described the main risk of a resume loop: an agent that reports more progress than it made. A matrix row marked `DONE` without a test is exactly that kind of over-reporting. Now it fails the build.

### Machine-Readable Output, Specified Exactly

Requirement 1 names the format: one line, `GDJL_TEST_RESULT {json}`. Requirement 2 says where it comes from: a test runner *written in Julia*, running *inside the engine*, using the standard `Test` library.

The harness then has two jobs:

- parse the line,
- fail on *"any Godot `ERROR:` not explicitly expected"*.

Both choices help agents as much as humans. An agent reading a 2,000-line Godot log to decide whether a test passed will sometimes get it wrong. An agent reading `"failed":0` will not.

And "fail on unexpected errors" closes a loophole: a test that reports success while the engine printed errors nobody looked at.

### "When Available" and "If Supported"

Two phrases leave room for things that may not be possible:

- C# benchmark numbers *"when available"*,
- an LTS Julia *"if supported"*.

Both turned out to matter, as you'll see.

### A Done-When the Agent Can't Reach

*"CI is green on all matrix entries."* The repository wasn't published on GitHub during this phase, so no workflow could run. The criterion is unreachable by construction.

What the agent does with an unreachable criterion is the most instructive part of the phase.

## What the Agent Built

### One Command

[`scripts/test_all.jl`](../../scripts/test_all.jl) runs everything CI runs, in order:

```julia
    step("parity-test check", `$JULIA --startup-file=no scripts/check_parity_tests.jl`)
    step("license headers", `$JULIA --startup-file=no scripts/license_headers.jl --check`)
    leaks = flag("--no-leaks") ? String[] : ["--leaks"]
    step("integration tests" * (isempty(leaks) ? "" : " (with leak checks)"), `$JULIA --startup-file=no tests/integration/run.jl $leaks`)
    step("doc tests", `$JULIA --startup-file=no scripts/doctest_docs.jl`)
    step("demos", `$JULIA --startup-file=no demos/run.jl`)
    flag("--exports") && step("export tests", `$JULIA --startup-file=no tests/export/run.jl`)
    flag("--benchmarks") && step("benchmarks", `$JULIA --startup-file=no tests/benchmarks/run.jl`)
```

Before these steps, it builds `native/`, generates the bindings, precompiles `Godot` and runs the unit tests of all four packages. It finishes with a PASS/FAIL summary per step.

The README documents it in four lines:

```sh
julia scripts/test_all.jl                 # build native/, bindings, unit tests, parity check, integration + leak checks, doc tests, demos
julia scripts/test_all.jl --exports       # + template libraries and export tests (slow: system images)
julia scripts/test_all.jl --benchmarks    # + benchmarks against tests/benchmarks/baseline.toml
julia scripts/test_all.jl --no-build --precision=double   # skip the native build; double-precision bindings
```

The same entry point serves three audiences:

- **a contributor** before a pull request,
- **CI**: the workflow's test step simply calls it with `--precision` and, on some entries, `--exports`,
- **the agent itself**.

After this phase, the agent's reports regularly end with some version of *"I rebuilt the native library and ran the full suite afterwards; everything passes."*

The license header, doc test and demo steps in the listing above came later, from phase 16 and from requests after it. Because there is one entry point, every new check has an obvious place to go.

### The In-Engine Test Runner

[`julia/GodotTestRunner`](../../julia/GodotTestRunner/src/GodotTestRunner.jl) is a small package. Its core is a custom `Test` test set that counts results and prints failures as they happen:

```julia
mutable struct EngineTestSet <: Test.AbstractTestSet
    description::String
    passed::Int
    failed::Int
    errored::Int
    broken::Int
    failures::Vector{String}
end
```

An integration project uses it with ordinary `Test` syntax. Here's [`tests/integration/objects/test_objects.jl`](../../tests/integration/objects/test_objects.jl):

```julia
# In-engine tests for object identity, lifetime, casting and dynamic access. parity: 4.1, 4.2, 4.4–4.8
using Test
using GodotTestRunner
using Godot
...
ts = @testset EngineTestSet "objects" begin
    helper = Node()
    set_script(helper, GD.load("res://helper.gd"))

    @testset "identity" begin
```

At the end, `report` prints the one line the harness reads:

```text
GDJL_TEST_RESULT {"name":"objects","passed":…,"failed":0,"errored":0,"broken":0}
```

Some projects run their tests as a script class inside the scene tree, for example the signals and editor tests. They count their checks with simple counters and call `GodotTestRunner.report` directly. Both styles produce the same line.

So did the exported game in chapter 17. It prints the line itself, because the runner package isn't part of the exported image.

One implementation detail came from the Julia version. Julia 1.13's `Test` has no `push_testset` function, which a custom runner might otherwise use to install its test set by hand. The agent's memory note records the replacement: *"Julia 1.13 Test has no push_testset: use `@testset EngineTestSet "name"`."*

Passing the test set type to `@testset` is the supported way, and it's what `run_tests` does.

### The Harness

[`tests/integration/run.jl`](../../tests/integration/run.jl) has existed since the scaffold. Phase 15 gave it the result line and leak checks. Its header comment is a complete specification of when a project passes:

```julia
# A project passes when Godot exits with 0, prints `GDJL_TEST_RESULT {json}` (GodotTestRunner) with no failures,
# prints every line of `expect_output.txt` (substring match), every ERROR:/SCRIPT ERROR:/WARNING: line matches a
# substring in `expect_errors.txt`, and nothing reports leaked objects or resources (`--leaks` adds `--verbose`).
```

Notice how many independent conditions there are:

- the exit code,
- the result line,
- expected output,
- *no unexpected errors or warnings*,
- no leaks.

A project can't pass by accident. A crash, a missing result line, an error the test didn't anticipate or a leaked object each fail it on its own.

Some tests are expected to produce errors. The debugging test of chapter 16, for example, deliberately raises script errors. Those tests list them in `expect_errors.txt`, which documents the expected noise.

### Leak Checks and Expected Noise

With `--leaks`, Godot runs with `--verbose` and reports leaked objects and resources at exit.

The first run found something. The stock Godot editor leaves one orphan `StringName` ("Node") at exit, *even without the addon loaded*. The agent's choice is visible in the code:

```julia
# The stock editor itself leaves an orphan StringName ("Node") at exit, so StringName reports are not checked.
const LEAK_PATTERN = r"leaked at exit|still in use at exit|Leaked instance"
```

Leaked objects and resources still fail. Only the one category of report that the engine produces on its own is excluded, and the reason sits right next to the pattern.

That's the difference between **documenting known noise** and suppressing everything until the output looks clean. The agent checked that the noise came from the engine and not from the addon *before* deciding to ignore it.

The optional AddressSanitizer job takes a similar line in CI. It reports memory errors but not leaks, because *"Julia's own allocations are not tracked by LSan"*, as the workflow comment explains.

### The Parity Check

[`scripts/check_parity_tests.jl`](../../scripts/check_parity_tests.jl) does the following:

- reads the matrix,
- collects every `parity:` tag from test files (unit tests, integration and export projects, the demo runner and the doc tester),
- expands ranges such as `6.1–6.6`,
- fails in two ways.

```julia
    println("$(length(done)) DONE rows, $(length(done) - length(missing_)) tagged by tests")
    isempty(missing_) || println("DONE rows without a tagged test: ", join(missing_, ", "))
    isempty(unknown) || println("tags naming no matrix row: ", join(("$id ($(join(unique(tags[id]), ", ")))" for id in unknown), "; "))
    return isempty(missing_) && isempty(unknown)
```

The second check is easy to miss, and it's important: a tag naming a row that doesn't exist also fails. Without it, tags would drift silently as rows were renumbered or removed.

That happened in this very project. Chapter 17's scope cut removed rows 10.3–10.5.

When the agent first ran the check, it failed. In the agent's words: *"29 rows lacked tags; I confirmed each one has a covering test before tagging it."*

That sentence describes the right behavior. It also shows the check's limit.

- Making the script pass was trivial: add 29 comments.
- The value lay in confirming, for each row, that a real test covered it.

The script verifies that a tag exists, not that the tagged test is meaningful. That part still relies on the agent's honesty and a reviewer's spot checks.

Today the check prints:

```text
92 DONE rows, 92 tagged by tests
```

It runs first in CI, as its own job that every other job depends on. A pull request that marks a row `DONE` without a test fails before any expensive build starts.

### Benchmarks

[`tests/benchmarks/`](../../tests/benchmarks) measures the hot paths the prompt listed, with GDScript as an in-process reference. It compares each against [`baseline.toml`](../../tests/benchmarks/baseline.toml):

```toml
engine_call = 37.3
engine_to_gdscript_call = 551.3
engine_to_julia_script_call = 1101.0
gdscript_process_dispatch = 280.0
julia_process_dispatch = 659.8
property_get = 36.4
signal_emit_to_julia = 733.6
variant_round_trip = 38.2
```

(Nanoseconds per operation.)

A benchmark fails when it is more than three times slower than its baseline. The report says repeated runs were stable within ±4%.

The threshold is generous on purpose. Its job is to catch an accidental return to allocating or dynamically dispatching code (the project instructions' hot-path rule), not small fluctuations. CI raises it to ten and runs the job as informational, since shared runners are slower and noisier than the machine the baselines came from.

The numbers are honest about a weakness. Calls from the engine into a Julia script, and `_process` dispatch, cost roughly twice what the same calls cost in GDScript. [`docs/perf.md`](../perf.md) attributes this to *"the bridge round trip and `invokelatest`"*.

For C#, the *"when available"* clause applied. No .NET build of Godot was installed, so the agent didn't invent numbers. Instead, `docs/perf.md` describes how to measure them: *"Measure them with the mono editor of the same Godot version: a C# `[GlobalClass]` node with `int Noop(int x)` and `_Process`, timed with the same loops … Then add a column to this table."*

### Workflows

[`ci.yml`](../../.github/workflows/ci.yml) has four jobs:

- the parity check,
- the main test matrix,
- informational benchmarks,
- the optional ASan job.

The matrix:

```yaml
      matrix:
        os: [windows-latest, ubuntu-latest, macos-latest]
        precision: [single]
        julia: ["1", "1.12"]
        include:
          # Official Godot binaries are single precision; the double job builds the editor from source.
          - os: ubuntu-latest
            precision: double
            julia: "1"
```

Two decisions here weren't in the prompt:

- **Double precision builds Godot from source.** Official Godot binaries are single precision, so a double-precision addon has nothing to load into. The double job clones the pinned Godot tag, builds a minimal headless editor, and caches it. Running double precision on every OS would multiply the slowest step, so there is one double job.
- **Julia 1.12 instead of an LTS.** The project instructions set Julia 1.12 as the floor (`juliac --trim` needs it). Testing the oldest supported version is what the prompt's *"if supported"* clause allowed for.

[`release.yml`](../../.github/workflows/release.yml) builds the native libraries for seven platform, architecture and precision combinations. Then it:

- packages the addon with [`scripts/package_addon.jl`](../../scripts/package_addon.jl) once per precision (generated bindings are precision specific, so double-precision libraries ship in their own `-double` zip),
- checks that the tag matches the package version,
- attaches the zips to a GitHub release,
- asks JuliaRegistrator to register the `Godot` package.

Linux libraries are built on Ubuntu 22.04 so they load on older glibc versions. macOS libraries target macOS 11.

## Where Reality Pushed Back

### The 1.12 Matrix Entry Found a Real Bug

Adding Julia 1.12 to the matrix wasn't just configuration. When the agent ran the suite on 1.12 locally, the extension failed to start: *"Julia 1.12 failed to start because the host required a symbol only 1.13 exports."*

The fix in [`julia_host.cpp`](../../native/src/julia_host.cpp):

```cpp
	// Julia 1.13+ reports where libjulia-internal is; 1.12 keeps it at its standard place in the install.
	api.jl_get_libjulia_internal_path = reinterpret_cast<const char *(*)()>(dynlib_symbol(libjulia, "jl_get_libjulia_internal_path"));
	std::string internal_path = api.jl_get_libjulia_internal_path ? std::string(api.jl_get_libjulia_internal_path())
																  : std::string(p_home.path_join(LIBJULIA_INTERNAL_REL).utf8().get_data());
```

The project instructions had claimed support for Julia 1.12 and later from the start. But nothing had run on 1.12. The claim was false, and only an actual run found it.

Running on 1.12 had its own pitfall, also recorded in memory: the test runner and the native host find Julia separately. To test 1.12 you need both:

- `julia +1.12` for the runner,
- `JULIA_BINDIR` pointing at 1.12 for the host.

Otherwise the runner is 1.12 while the engine quietly loads 1.13, and the test proves nothing. With both set, the report says, the 515 Godot unit tests and all 11 integration projects passed on 1.12.

### Holding Statuses That Can't Be Earned Yet

The workflows exist, but they had never run. The agent's report opens with that fact, not with the list of what was built:

> I've built phase 15 (`gdjl-15-testing-ci`) and everything passes locally, but the CI and release workflows have never run on GitHub. The phase's "CI green on every matrix entry" criterion is therefore still open.

And on the matrix:

> **Parity rows**: no status changed. I updated the notes on 1.3 (registry publishing), 1.7 (double precision) and 10.2 (desktop exports); all three stay PARTIAL until the workflows run on GitHub.

It would have been easy to promote these rows. The workflows are written, they parse as valid YAML, and the double-precision library builds locally.

But **"written" isn't "verified"**. The matrix notes say exactly what remains: *"defined in `ci.yml` but has not run yet."*

A matrix where `DONE` means "verified" stays trustworthy only if rows that are merely written stay `PARTIAL`.

- The parity check enforces one half of that rule: no `DONE` without a test.
- The other half, no `DONE` without a *run*, relies on the agent's judgment. Here it held.

The report is just as careful about its own coverage: *"The `sysimage` exports were not re-run after this phase's changes; they passed in phase 14."*

A ten-minute build is a reasonable thing to skip. Not mentioning that you skipped it is not.

### A Blocker That Needed a Human

The report's list of remaining blockers included:

> **No `LICENSE` file**: the README still says "to be decided", and the addon zip ships without a license.

The agent couldn't choose a license for someone else's project, so it named the gap and stopped there.

Our next request outside the phase loop answered it: *"This project will be published code under apache 2.0 license, copyright 2026 Espen Harlinn."* That request produced:

- `LICENSE`,
- `NOTICE`,
- SPDX headers in 167 source files,
- a new tool, [`scripts/license_headers.jl`](../../scripts/license_headers.jl).

Its `--check` mode joined `test_all`. A new file without a header now fails the suite, just like a missing parity tag does.

The headers had a side effect worth knowing about. Three new lines at the top of every source file moved every test fixture's line numbers.

The agent updated the integration expectations that check `res://Bad.jl:N`-style locations and the editor test's syntax-highlighting lines. Then it recorded the lesson in memory: *"Headers shift fixture line numbers (+3) in integration expectations."*

Tests that assert exact line numbers are precise, and fragile in exactly this way.

### Operational Lessons

Two lessons from earlier phases became part of how the suite is run. Both are in the agent's memory notes:

- *"Kill stray Godot processes before rerun (DLL locked -> ENOTEMPTY in prepare)."* A timed-out Godot process keeps the addon DLL open on Windows, and the next run fails while copying the addon (chapter 15).
- *"A syntax error in an integration main script = timeout (never quits); check .godot/gdjl_test.log."* If the test script doesn't parse, it never calls `quit`. The symptom is a five-minute timeout instead of an error. The log file names the real cause.

Neither of these is a bug in the code. They are facts about how the tests behave. Without the notes, every new session would have to rediscover them.

## Closing the Loop

The phase 15 report's test inventory:

- Unit tests: Godot 515 (on Julia 1.13 and 1.12), GodotBindgen 128, GodotEditor 60, GodotTestRunner 8.
- Integration: 11 of 11 with leak checks on Julia 1.13, and 11 of 11 on Julia 1.12.
- Exports: `jit-debug` 2 of 2 after the final changes.
- Also: the double-precision library builds, the benchmarks pass, and a full `scripts/test_all.jl` run passes.

You can reproduce the core of it yourself:

```powershell
julia scripts/check_parity_tests.jl       # seconds
julia scripts/test_all.jl                 # the full local suite
julia tests/integration/run.jl --leaks    # just the integration projects, with leak checks
```

## Techniques to Reuse

- **Turn your most important convention into a failing check.** "No `DONE` without a test" became a script that runs first in CI. Conventions drift; checks don't. Chapter 3 introduced the idea as "turn rules into scripts"; this is where it was carried out.
- **Make results machine-readable.** One structured line per test project beats an agent's reading of a log.
- **Fail on the unexpected, and list the expected.** Unexpected `ERROR:` lines fail. Expected ones are listed per project, and known engine noise is excluded with a comment saying why.
- **Use one entry point for humans, agents and CI.** Every new check gets an obvious place to go.
- **Test the versions you claim to support.** The 1.12 claim was false until something actually ran on 1.12.
- **Keep "written" and "verified" apart.** Workflows that have never run leave their rows `PARTIAL`, and the report leads with that.
- **Name the blockers only a human can resolve.** The license gap was reported, not guessed at.

## Try It Yourself

1. In a scratch branch, remove a `# parity:` tag from a test file, for example the one in `tests/integration/objects/test_objects.jl`. Run `julia scripts/check_parity_tests.jl` and see which rows it reports. Then ask the **Agent**: *"The parity-test check fails. Explain why and fix it."* Does it restore the tag, or does it first confirm that the test actually covers those rows?
2. Run `julia tests/integration/run.jl --leaks editor`. Find the `Orphan StringName: Node` line in `tests/integration/editor/.godot/gdjl_test.log`. Then ask the **Ask** agent: *"Could excluding StringName reports from the leak check hide a real leak in the addon? How would you check?"*
3. Ask the **Plan** agent: *"What would it take to move parity rows 1.3, 1.7 and 10.2 from PARTIAL to DONE?"* Compare its plan with the notes in the matrix.

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 1.3 | `Godot` Julia package in a registry, versioned with Godot | PARTIAL (versioned with the pinned Godot 4.7.2 and shipped in the addon zip, tested locally; `release.yml` publishes the zip and asks JuliaRegistrator to register `julia/Godot` on a version tag; not yet run: the repository is not published and the registrator app not installed) |
| 1.7 | Single and double precision (`real_t`) builds | PARTIAL (math verified with `real_t = Float64` bindings; native `precision=double` library builds on Windows, tested locally; the CI job building a double-precision Godot editor and running the suite is defined in `ci.yml` but has not run yet) |
| 10.2 | Windows, Linux, macOS desktop exports | PARTIAL (Windows x86_64 exported and run in sysimage debug/release and jit; Linux/macOS run by the `ci.yml` export step, which has not run yet) |

The phase's other deliverable, "no row may stay `DONE` without a test", is not a row. It's the check that keeps every other row honest.

---
[← Previous: Export](17-export.md) · [Contents](README.md) · [Next: Documentation and Demos →](19-docs-demos.md)
