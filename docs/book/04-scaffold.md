# 4. Scaffolding: Decisions Before Code

The first real phase builds almost nothing you would notice.

When it's done, Godot's official editor loads a native library that prints one line. Two Julia packages pass placeholder tests. That's it.

Yet this phase fixes more of the project's future than any other. It settles:

- which Godot version,
- which delivery mechanism,
- which build system,
- where every file goes,
- what "it works" means.

Those decisions are cheap to make on day one. They're expensive to change on day four.

It also has to come first:

- Phase 2 needs a native library to embed Julia into.
- Phase 3 needs the API files this phase fetches.
- Every later phase needs the test-project layout, the addon folder and the version pin.

Run anything earlier, and the agent would have to invent all of this on the fly. Differently each time.

## The Prompt

Here's the full prompt, [`.github/prompts/gdjl-01-scaffold.prompt.md`](../../.github/prompts/gdjl-01-scaffold.prompt.md):

```markdown
---
name: gdjl-01-scaffold
description: "Phase 1: scaffold the Godot+Julia repository (GDExtension host, Julia packages, addon layout, build system)."
argument-hint: "Optional: Godot 4.x tag to pin, e.g. 4.5-stable"
agent: agent
---
Scaffold the Godot-julia repository as described in the [project instructions](../copilot-instructions.md). Godot tag to pin: `${input:godotTag:latest stable 4.x tag}`.

## Tasks

1. **Pin versions**: write `GODOT_VERSION`. Add `godot-cpp` as a git submodule under `native/godot-cpp` on the matching branch/tag.
2. **Native host** (`native/`):
   - Build system (SCons, matching godot-cpp conventions, or CMake — record the choice in `docs/adr/0001-build-system.md`).
   - Build targets: `template_debug`, `template_release`, `editor`; platforms windows/linux/macos; `precision=single|double`.
   - Locate Julia headers/libs via `JULIA_DIR` (fallback: `julia --startup-file=no -e 'print(Sys.BINDIR)'`).
   - Minimal `register_types.cpp` with the GDExtension entry point `godot_julia_library_init` that prints a message at `MODULE_INITIALIZATION_LEVEL_SCENE`.
3. **Addon** (`addons/godot_julia/`): `godot_julia.gdextension` (entry symbol, `compatibility_minimum`, per-platform/per-build library paths), `bin/` (gitignored), `icons/`, `script_templates/`.
4. **Julia packages**: create `julia/Godot` and `julia/GodotBindgen` with `Project.toml`, `src/`, `test/runtests.jl`. `julia/Godot/src/generated/` is gitignored.
5. **Tooling**: `.gitignore`, `.editorconfig`, `scripts/fetch_api.jl` that runs `godot --headless --dump-extension-api-with-docs --dump-gdextension-interface` and stores output in `native/api/` (gitignored, regenerated).
6. **Test project**: `tests/integration/smoke/project.godot` that loads the addon headlessly.
7. **ADRs**: `docs/adr/0000-gdextension-vs-module.md` explaining why GDExtension (official builds, no fork) and listing the known module-only capabilities to watch (compare `modules/mono/register_types.cpp`).
8. `README.md` with prerequisites and build steps.

## Done when

- `scons` (or CMake) builds the library on the current OS.
- `godot --headless --path tests/integration/smoke --quit` prints the init message without errors.
- `julia --project=julia/Godot -e 'using Pkg; Pkg.test()'` passes (placeholder test).
- Parity matrix rows 1.2 and 1.3 updated.
```

## Anatomy of the Prompt

### `${input:godotTag:latest stable 4.x tag}`: a Parameter with a Sensible Default

The frontmatter's `argument-hint` and the `${input:…}` placeholder turn the prompt into a **command with an optional argument**.

- Run `/gdjl-01-scaffold 4.7.2-stable` to pin a specific version.
- Run it bare, and the agent uses the default the placeholder describes: *latest stable 4.x tag*.

We ran it bare. The agent pinned `4.7.2-stable`, then the newest stable release.

The parameter is a hedge against time. A prompt that hard-codes a version goes stale the day the next release ships. A prompt that says "latest stable, unless told otherwise" stays reusable.

The trade-off: the agent must *find out* what the latest stable tag is. That's exactly the kind of fact it should look up rather than remember.

### "Pin Versions" Comes First

Task 1 is to write [`GODOT_VERSION`](../../GODOT_VERSION) and pin `godot-cpp`. Everything later depends on it:

- which API files to fetch,
- which tag of `modules/mono` to read,
- which editor binary to download.

The project instructions repeat the rule ("Godot: the tag in `GODOT_VERSION`"). Every phase prompt that fetches a reference file says *at the pinned tag*.

For an agent, the pin does two jobs:

- **It makes the work reproducible.** The same prompt on another machine gets the same API.
- **It gives the agent permission to distrust its own memory.** The ground truth is a specific tag that can be fetched, not whatever version the model remembers best.

### Two Decisions Recorded Before Any Real Code

Tasks 2 and 7 require two **architecture decision records** (ADRs):

- **[ADR 0001](../adr/0001-build-system.md): build system.** The prompt offers "SCons, matching godot-cpp conventions, or CMake" and requires the choice to be written down. The agent chose SCons. The engine, the official `godot-cpp-template` and godot-cpp's own tests all use it. They also share option names (`target`, `platform`, `arch`, `precision`) and the library suffix convention.
- **[ADR 0000](../adr/0000-gdextension-vs-module.md): GDExtension, not an engine module.** This is the decision the whole project rests on. Godot's C# support is an engine module, which is why it needs a separate ".NET" editor build. A GDExtension runs on the official, unmodified editor.

Why make the agent write these down on day one?

Because the next session won't remember the reasoning. A reasonable agent facing a hard problem in phase 8 might well conclude, again, that "this would be easier as an engine module."

The project instructions close that door explicitly: *"Architecture (decided — change only via an ADR in `docs/adr/`)"*. The ADR is what makes "decided" mean something.

### "List the Known Module-Only Capabilities to Watch"

The most forward-looking sentence in the prompt sits in task 7: *listing the known module-only capabilities to watch (compare `modules/mono/register_types.cpp`)*.

It asks the agent to look for risk *before* committing to the architecture. Where might the GDExtension route fall short?

The agent read the C# module's entry point at the pinned tag. It found that the module does only four things at the `SCENE` initialization level:

- registers the `CSharpScript` class,
- creates a binding singleton,
- registers `CSharpLanguage`,
- adds `.cs` resource loaders and savers.

GDExtension has equivalents for all four.

The ADR then lists eight capabilities that use engine internals in `modules/mono`. Each comes with the GDExtension route that should replace it and the phase responsible:

| Capability in `modules/mono` | Internal mechanism | GDExtension route | Phase |
|---|---|---|---|
| Interop function table (`glue/runtime_interop.cpp`) | Direct calls into engine C++ | `gdextension_interface` functions via `get_proc_address` | 03 |
| Script instances (`CSharpInstance`) and refcount hooks | `ScriptInstance` subclass | `GDExtensionScriptInstanceInfo3` (`refcount_incremented/decremented`) | 07, 08 |
| Assembly reload with state backup | Iterates every script instance in the engine | Track instances on our side; `_reload_scripts` / `_reload_tool_script` | 11 |

*(Three of the eight rows from [ADR 0000](../adr/0000-gdextension-vs-module.md).)*

This table is a **risk register with owners**. If any of these turned out impossible, the owning phase would have to record a `GAP` with an ADR.

As of today, none has.

Visible compromises are rare, and they're recorded where they belong. For example:

- Engine code can only call script static methods through `script.call_static(...)`, because GDExtension scripts can't intercept `Script.f()` (row 5.16, [ADR 0009](../adr/0009-script-authoring.md)).
- Ahead-of-time trimming turned out not to be feasible either. But the reasons have nothing to do with GDExtension ([ADR 0014](../adr/0014-export.md)).

### Precise Names, Paths and Symbols

Look at how specific the tasks are:

- the entry symbol `godot_julia_library_init`,
- the initialization level `MODULE_INITIALIZATION_LEVEL_SCENE`,
- the paths `addons/godot_julia/`, `native/api/`, `julia/Godot/src/generated/`.

None of these is interesting in itself. But naming them precisely means every later prompt can refer to them without ambiguity. Every later session will put files in the same places.

Precision in the scaffold prompt buys **cheap consistency** for the whole project.

### "Done When": Four Checks You Can Run

The done-when list isn't "the repository is set up". It's four checks:

1. the build succeeds;
2. a headless Godot run prints the init message without errors;
3. `Pkg.test()` passes;
4. the matrix rows are updated.

Each of the first three is a command with an **observable result**. As you'll see in the next section, that mattered immediately.

### Owned Rows: 1.2 and 1.3

The phase owns two rows:

- *works with the standard Godot editor* (1.2),
- *a versioned Julia package* (1.3).

Row 1.3 is co-owned with phases 14 and 15. "Versioned with Godot and registered" needs release machinery that doesn't exist yet.

So the prompt only asks for the rows to be *updated*, not finished. That leaves the agent free to report `PARTIAL` honestly.

## What the Agent Built

The artifacts are small and deliberately boring.

### The entry point

[`native/src/register_types.cpp`](../../native/src/register_types.cpp) has grown since phase 1. It now starts the Julia host, registers the script language and loads the editor API.

The shape the scaffold gave it hasn't changed:

- an exported `godot_julia_library_init`,
- an initializer and terminator,
- work done at the `SCENE` level.

```cpp
extern "C" {
GDExtensionBool GDE_EXPORT godot_julia_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_godot_julia_module);
	init_obj.register_terminator(uninitialize_godot_julia_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
```

### The addon descriptor

[`addons/godot_julia/godot_julia.gdextension`](../../addons/godot_julia/godot_julia.gdextension) lists:

- the entry symbol,
- `compatibility_minimum = "4.7"`,
- a library path for every platform, target and precision combination.

It also contains a line the prompt didn't ask for:

```ini
; The embedded Julia runtime cannot be unloaded, so the library must not be hot-reloaded.
reloadable = false
```

The agent saw ahead to a constraint from phase 2: a Julia runtime can't be unloaded from a process. It recorded the consequence in ADR 0000. Script hot reload in phase 11 must work *inside* the runtime, not by reloading the library.

### The build script

[`native/SConstruct`](../../native/SConstruct) is about sixty lines.

- It delegates to godot-cpp's SConstruct with `api_version = "4.7"`.
- It writes outputs straight into `addons/godot_julia/bin/` using godot-cpp's suffix convention.
- So the `.gdextension` file can list them without a copy step.

One line carries a hard-won lesson:

```python
env = SConscript("godot-cpp/SConstruct", {"api_version": GODOT_API_VERSION})
# Our flags must not leak into godot-cpp's environment, or the whole library rebuilds.
env = env.Clone()
```

### The tooling scripts

- **[`scripts/fetch_api.jl`](../../scripts/fetch_api.jl)** dumps the API from the pinned Godot binary. It warns when `godot --version` doesn't match `GODOT_VERSION`. When no Godot binary is available, it falls back to the copies bundled with godot-cpp.
- **[`scripts/prepare_test_projects.jl`](../../scripts/prepare_test_projects.jl)** copies the built addon into each test project.
- **[`scripts/fetch_godot.jl`](../../scripts/fetch_godot.jl)**, added later, downloads the pinned editor and verifies it against the release's SHA-512 sums.

### The smoke project

[`tests/integration/smoke/`](../../tests/integration/smoke) is the smallest possible Godot project that loads the addon. Today its script prints the machine-readable result line that phase 15 standardized:

```gdscript
extends Node
# parity: 1.2


func _ready() -> void:
	print('GDJL_TEST_RESULT {"name":"smoke","passed":1,"failed":0,"errored":0,"broken":0}')
	get_tree().quit()
```

Its `expect_output.txt` contains a single line, `Godot-julia: Julia 1.`. That checks that the host started a Julia 1.x runtime.

Note the `# parity: 1.2` tag. This file is the **evidence** behind row 1.2.

### The rest

The Julia packages and the ADRs, described above, complete the picture.

## Where Reality Pushed Back

### The First Run Could Not Finish, and Said So

The very first run of this prompt happened on a machine with Julia 1.13.3 and git. Nothing else:

- no Godot,
- no Python or SCons,
- no C++ compiler.

The agent did what it could. Its report opened with what it could *not* do:

> The phase 1 files are in place and the Julia tests pass. However, the C++ library was never built and the smoke test never ran: this machine has no Godot, Python/SCons or C++ compiler (only Julia 1.13.3 and git). So two of the four "done when" checks are still open.

It followed with a done-when table:

- native build: "Not run (no build tools)",
- smoke test: "Not run (no Godot)",
- `Pkg.test()`: "Passes",
- rows 1.2 and 1.3: "Both marked `PARTIAL`".

This is why **executable done-when criteria** matter.

With a vague criterion such as "scaffold the repository", the first run would have looked complete. With four concrete checks, the missing evidence was impossible to overlook. The matrix correctly said `PARTIAL`.

Then we installed the tools.

The session history shows a short side conversation in **Ask** mode, asking for a script to install Python and SCons. Ask can't create files, so it answered with the script for us to save. We installed Visual Studio as well.

The next `/gdjl-00-next`:

- downloaded the official 4.7.2 editor,
- verified its SHA-512 checksum,
- built the library,
- ran the smoke test.

The report:

> Phase 1 is now complete: the native library builds, and the official Godot 4.7.2 editor loads it in the headless smoke test.

Row 1.2 moved to `DONE`, backed by the smoke test. Row 1.3 stayed `PARTIAL`, *"because publishing to a registry belongs to phase 14."*

### Godot Refused to Run a Project Without a Main Scene

The prompt asked for a `project.godot` that loads the addon. That isn't enough. `godot --headless --path … --quit` refused to run the project without a main scene.

The agent added `main.tscn` and `main.gd` and reported the change.

Small, but typical. **Reference behavior beats the prompt's assumptions** every time. The agent has to notice the difference and adapt.

### The Prompt Was Already Out of Date

We wrote the prompt from the model's knowledge of Godot. Two details were stale for Godot 4.7:

- **godot-cpp versioning.** Task 1 says to add godot-cpp *"on the matching branch/tag"*. But godot-cpp is now versioned independently of Godot. The agent pinned `10.0.0-stable` and selected the API with `api_version = "4.7"`, recorded in [ADR 0001](../adr/0001-build-system.md).
- **The dump flag.** Task 5 says `--dump-gdextension-interface`. Godot 4.6 and later use `--dump-gdextension-interface-json`, which [`scripts/fetch_api.jl`](../../scripts/fetch_api.jl) now uses. The script also documents a 4.7 quirk found later: `--dump-extension-api-with-docs` exits with an error once extensions are loaded. So project-specific dumps (for classes from other GDExtensions) are made without docs.

A prompt is a **hypothesis about the world**. When it disagrees with the pinned reference, the reference wins.

The deviation should then be reported. Here, it was, under the heading *"Changes from the prompt worth reviewing"*.

### A Decision That Belonged to Phase 2

That same section of the first report held a bigger deviation: *"Julia isn't linked at build time."*

The prompt said to locate Julia headers and libraries via `JULIA_DIR`. While scaffolding, the agent concluded that the extension should load libjulia when it starts instead. That way it can:

- find whichever Julia is installed,
- keep the editor usable when Julia is missing (as the C# editor stays usable without .NET),
- avoid a MinGW/MSVC mismatch on Windows.

It wrote [ADR 0002](../adr/0002-runtime-loading.md) on the same day. Chapter 5 covers it in detail.

There's a small lesson in what happened next. The three sources now disagree slightly:

- [ADR 0001](../adr/0001-build-system.md) still says the Julia installation is used *"only for headers (see ADR 0002)"*.
- ADR 0002 says *"Julia headers are not used,"*.
- Today's `SConstruct` uses the Julia directory only to bake in a development fallback path.

ADRs record decisions at a point in time. A later decision can quietly make an earlier sentence stale.

In your own projects, have the agent update the earlier ADR's *Consequences*, or add a "superseded in part by" note, when a new ADR changes it. A periodic audit (chapter 20) is a good place to catch the rest.

### Headless Godot Has Its Own Rules

Two Godot behaviors shaped the test infrastructure early on:

- **A headless run needs an `--import` pass** once before `--quit`, so that `.godot/extension_list.cfg` registers the extension.
- **A headless editor crashes at exit** on the first scan that discovers a `.gdextension` file (Godot issues [#111048](https://github.com/godotengine/godot/issues/111048) and [#123511](https://github.com/godotengine/godot/issues/123511)). The agent ran into it in phase 3 and confirmed that it happens even with Julia disabled. It added the workaround to [`scripts/prepare_test_projects.jl`](../../scripts/prepare_test_projects.jl), with a comment that names the issues:

```julia
    # Pre-register the extension: a headless editor that discovers a .gdextension during its first scan
    # crashes at exit (godotengine/godot#111048, #123511).
    mkpath(joinpath(project, ".godot"))
    write(joinpath(project, ".godot", "extension_list.cfg"), "res://addons/godot_julia/godot_julia.gdextension\n")
```

The comment matters as much as the code. It tells the next session, and the next person reading it, why a line that looks redundant must not be removed.

### Windows Tooling Lessons

Several lessons from the first day are about tools rather than the product. The agent recorded them in its memory notes and in code comments:

- **SCons finds MSVC by itself.** `cl` doesn't need to be on `PATH`.
- **Don't truncate a live build.** Piping a running `scons` into PowerShell's `Select-Object -First N` kills the build once N lines have been read. Long builds now log to a file and run in the background.
- **Clone before appending flags.** `native/SConstruct` must `env.Clone()` first, or godot-cpp rebuilds from scratch (the comment shown above).
- **Download with the right tool.** PowerShell's `Invoke-WebRequest` was too slow for the editor, so the first download used `curl.exe` with a SHA-512 check. The logic later moved into `scripts/fetch_godot.jl`, written in Julia so it runs the same way on every OS.

None of these are interesting engineering problems. Each one cost time once. With a note in the right place, it costs nothing the next time.

## Closing the Loop

At the end of phase 1, the **oracle** was the four done-when checks, run by hand from the agent's terminal.

Today the same checks are part of the one-command suite:

```powershell
julia scripts/test_all.jl              # builds native/, generates bindings, runs every test, including smoke
julia tests/integration/run.jl smoke   # just the smoke project
```

The smoke project still guards row 1.2 through its `# parity: 1.2` tag. `scripts/check_parity_tests.jl` would fail if that tag disappeared.

The scaffold's checks didn't go away when later phases added features. They became the foundation of the **regression suite**.

## Techniques to Reuse

- **Pin first, distrust memory.** Write the version pin before any code. Tell every prompt to fetch references at that pin.
- **Decide, then write it down.** Have the agent record foundational choices as ADRs in the first phase, so later sessions treat them as settled.
- **Ask for a risk register.** Before building on the chosen architecture, have the agent list what might not work, with an owner for each risk.
- **Name everything precisely.** Entry symbols, paths and folder names in the scaffold prompt become shared vocabulary for every later prompt.
- **Use executable done-when criteria.** Commands with observable results expose missing evidence. Vague criteria hide it.
- **Report deviations explicitly.** Ask for, and reward, a "changes from the prompt" section in every report.

## Try It Yourself

1. Open the **Ask** agent and give it this request: *"Compare `.github/prompts/gdjl-01-scaffold.prompt.md` with ADR 0000, ADR 0001 and `native/SConstruct`. List every place where the implementation deviates from the prompt and say which ADR explains it."* Check whether it finds the godot-cpp versioning, the dump flag, `reloadable = false`, and the ADR 0001/0002 wording conflict.
2. Open the **Plan** agent and have it design a scaffold prompt for a different binding, for example a Rust or Zig GDExtension. Compare its done-when list with the four checks above. Are all of them executable?
3. Run `julia scripts/prepare_test_projects.jl` and `julia tests/integration/run.jl smoke`. Then delete `.godot/extension_list.cfg` from the smoke project and run Godot headless yourself. Watch what happens, and you'll see why that line exists.

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 1.2 | Works with the standard Godot editor via GDExtension (C# needs a separate .NET editor build) | DONE (official 4.7.2 editor loads the extension; `tests/integration/smoke`) |
| 1.3 | `Godot` Julia package in a registry, versioned with Godot | PARTIAL (versioned with the pinned Godot 4.7.2 and shipped in the addon zip; the release workflow that registers the package has not run yet, because the repository is not published) |

---
[← Previous: The Resume Loop](03-the-resume-loop.md) · [Contents](README.md) · [Next: Embedding the Runtime →](05-embed-runtime.md)
