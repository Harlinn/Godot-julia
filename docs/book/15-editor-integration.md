# 15. Editor Integration: UX Parity as a Specification

Until phase 12, Julia worked in Godot. But it didn't feel at home in Godot's editor.

Open a `.jl` file and you saw plain, uncolored text. There was:

- no button to build anything,
- no panel for errors,
- no way to set up a Julia project from the editor,
- no templates in the *Create Script* dialog.

A C# developer gets all of this from Godot's .NET editor tooling (**GodotTools**):

- a generated `.csproj`,
- a hammer-shaped *Build* button,
- an MSBuild panel with clickable problems,
- external IDE support,
- script templates,
- `dotnet/*` settings.

User-interface work is notoriously hard to specify for an agent. "Make a nice build panel" is an invitation to invent.

This phase's prompt avoids that by turning UX into a **mapping**: *for each thing C# developers see, here is its Julia counterpart.*

The result is a small C++ shim and about 1,000 lines of Julia tools. Both grew later:

- phase 14 added export tools,
- the phase 17 audit added a translation parser and a richer problems view.

That brings them to about 500 lines of C++ and 1,350 lines of Julia today. And the editor test is itself written as a Julia editor plugin.

This chapter also tells the story of a bug from chapter 10 that only this phase could find.

## The Prompt

[`.github/prompts/gdjl-12-editor-integration.prompt.md`](../../.github/prompts/gdjl-12-editor-integration.prompt.md):

```markdown
---
name: gdjl-12-editor-integration
description: "Phase 12: Godot editor integration for Julia — project generation, Build button/panel, external editors, templates, settings, global classes (GodotTools parity)."
agent: agent
---
Implement editor tooling in `Godot.Editor` (Julia) plus minimal C++ `EditorPlugin` shims. Follow the [project instructions](../copilot-instructions.md). Behavioral reference: `modules/mono/editor/GodotTools/` (`GodotSharpEditor.cs`, `Build/BuildManager.cs`, `Build/MSBuildPanel.cs`, `Build/BuildProblemsView.cs`, `Ides/`, `ProjectEditor`, `Utils/`), C# script templates under `modules/mono/editor/script_templates/`, and docs `c_sharp_basics.rst` (editor setup sections).

## Requirements

1. **Project bootstrap**: when the first `.jl` script is created (or via menu *Project → Tools → Julia → Create Julia Project*), generate `Project.toml` (name from `julia/project/package_name`, defaulting to the Godot project name), add the `Godot` package at the version matching the editor, and instantiate. Equivalent of auto-generated `.csproj`/`.sln`.
2. **Build button + panel**: toolbar "Build" action (C# hammer icon parity) that runs `Pkg.instantiate`, precompiles user packages and all scripts, validates every `.jl` script, then triggers hot reload (phase 11). Run builds without freezing the editor (background process or worker task), streaming output to a bottom panel "Julia" with a problems list (severity, file, line, clickable → opens script at line), copy log, and clear actions. Optionally auto-build before running the project (C# parity setting).
3. **Settings**:
   - Project: `julia/project/package_name`, `julia/project/reload_attempts`, `julia/runtime/threads`, `julia/runtime/path`, `julia/runtime/optimize`.
   - Editor: `julia/editor/external_editor` (enum: None, VS Code, VSCodium, Emacs, Vim/Neovim, Custom), `julia/editor/custom_exec_path`, `julia/editor/custom_exec_path_args` (with `{file}`, `{line}`, `{col}`, `{project}` placeholders), `julia/build/verbosity`.
4. **External editor**: `_overrides_external_editor` / `_open_in_external_editor` launch the chosen editor at file:line:col; for VS Code also open the project folder and recommend the Julia extension (generate `.vscode/settings.json` with `julia.environmentPath`). Double-clicking a script, errors, and signal-handler navigation all route here.
5. **Templates**: built-in templates for `Node`, `Object`, `Resource`, `EditorPlugin`, `EditorScript` ("Empty" and "Default") mirroring C#'s; support project `script_templates/<BaseClass>/*.jl` with the same placeholders (`_CLASS_`, `_BASE_`, `_TS_`).
6. **Create dialogs**: `@global_class` scripts appear in Create Node / Create Resource dialogs with icons and in typed export pickers; class name validation in the Create Script dialog (PascalCase = file name).
7. **Editor scripts**: `@tool` + `EditorPlugin` / `EditorScript` / `EditorInspectorPlugin` written in Julia work (uses `Godot.Editor` bindings).
8. **Package management UX**: menu entries to add/remove/update packages (`Pkg.add` etc.), output in the Julia panel — NuGet parity.

## Tests

- Headless editor test (`godot --editor --headless --quit-after N`) with a scripted `EditorScript` asserting: project bootstrap creates `Project.toml`; build reports a deliberate error with correct file:line; templates produce scripts that validate.
- Unit tests for external-editor command construction per OS.

Update parity rows 1.4–1.6, 8.1–8.8.
```

## Anatomy of the Prompt

### UX Parity as a Specification

Almost every requirement names the C# counterpart of the Julia feature:

| C# (GodotTools) | Julia (this phase) |
|-----------------|-------------------|
| auto-generated `.csproj`/`.sln` | `Project.toml` on the first script |
| hammer-icon *Build* button | toolbar *Build* button |
| MSBuild panel + problems view | "Julia" bottom panel + problems list |
| NuGet | `Pkg` menu entries |
| `dotnet/*` settings | `julia/*` settings |
| C# script templates | Julia templates with the same placeholders |

Why does this matter? UI work is hard to specify because so much of it is **implicit**:

- where the button goes,
- what a problem row contains,
- what clicking it does.

Naming the C# feature turns all that implicit design into a reference the agent can study.

- `MSBuildPanel.cs` shows the layout and actions.
- `BuildProblemsView.cs` shows what a problem row holds and what activating it does.

The prompt's own descriptions also spell out the essentials (*"severity, file, line, clickable → opens script at line"*, *"copy log, and clear actions"*). So nothing important rests on the agent reading C# code correctly.

### "Without Freezing the Editor"

Requirement 2 contains a sentence that's easy to skim past: *"Run builds without freezing the editor (background process or worker task)."*

A build that runs `Pkg.instantiate` and precompiles packages can take minutes. Run that on the editor's main thread, and the whole editor freezes for that long. So would every package action.

**Responsiveness requirements** are classic omissions in specifications. Whoever writes them imagines the feature working, not waiting.

Stating the requirement, and offering two acceptable implementations, makes it part of the design.

### Settings as a Contract

Requirement 3 spells out:

- every setting name,
- its enumeration values,
- the placeholders in the custom command line (`{file}`, `{line}`, `{col}`, `{project}`).

Exact names make behavior **testable**: the editor test can check that each setting exists. They make it **documentable**: the README can list them.

They also mean later phases and user documentation refer to the same names, without guessing.

### A Pure Function That Can Be Tested Per OS

Look at the second test bullet: *"Unit tests for external-editor command construction per OS"*.

It implies a design. The code that *builds* the command line must be separate from the code that *launches* it. Otherwise you can't test it on one machine for three operating systems.

A test requirement that shapes the architecture is a cheap way to get testable code.

### Testing an Editor Without a Screen

The first test bullet describes how to test an editor in CI: run `godot --editor --headless`, with a scripted plugin making assertions.

Without that bullet, an agent would reasonably conclude that editor UI can only be checked by hand. With it, bootstrap, build errors and template validation become automated checks.

## What the Agent Built

[ADR 0012](../adr/0012-editor-integration.md) records the design. It follows the project's usual split:

- a small native shim, [`native/src/julia_editor.cpp`](../../native/src/julia_editor.cpp). It's about 400 lines today, including the translation parser the phase 17 audit added.
- Julia tools in [`julia/GodotEditor/src/tools/`](../../julia/GodotEditor/src/tools).

### Native Shim, Julia Tools

A native `JuliaEditorPlugin` is added automatically in the editor.

It's only created when `Engine.is_editor_hint()` is true. That's the same rule that loads the editor API (ADR 0004).

It forwards `_enter_tree`, `_exit_tree`, `_process` and `_build` over the script bridge to `GodotEditor.Tools`. The bridge handlers are registered when `GodotEditor` loads.

This is the payoff of chapter 11's single entry point. New editor features meant new Julia handlers, not new C++ ABI.

The native side also carries a `JuliaSyntaxHighlighter`. The ADR explains why it must be native:

- extensions can't use the engine's built-in highlighter,
- without a language-specific one, Godot shows `.jl` files as plain text.

### A Build That Runs Elsewhere

*Build* (toolbar, panel or menu) and the package actions run [`worker.jl`](../../julia/GodotEditor/src/tools/worker.jl) in a **child Julia process**.

The plugin reads the child's output pipes once per frame, without blocking. So the editor stays responsive. That's exactly what requirement 2 asked for, and also what C# does with `dotnet build`.

The worker reports through a simple **line protocol**, documented at the top of the file:

```julia
# Output protocol (one record per line): `GDJL_STEP\t<text>`, `GDJL_PROBLEM\t<severity>\t<file>\t<line>\t<col>\t<message>`;
```

A build has three steps:

- `Pkg.instantiate` and `Pkg.precompile`;
- validation of every user `.jl` file, with the same parse-and-lower check as the editor's `_validate`;
- on success, a hot reload of all scripts (chapter 14).

Problems appear in the panel. Activate one, and it opens the script at its line through `EditorInterface.edit_script`, which honors the external-editor setting.

The ADR is honest about what a build can't do:

> A build validates syntax and macro expansion, not types or names, because Julia has no ahead-of-time compile step equivalent to `csc`. Runtime errors still surface at load or call time with `res://` locations.

### External Editors as a Pure Function

[`external.jl`](../../julia/GodotEditor/src/tools/external.jl) builds the command line from the settings, the file, line, column and project.

Every OS-dependent input is passed in as a parameter (`windows`, `which`, `exists`):

```julia
function external_editor_command(kind::ExternalEditor, file::AbstractString, line::Integer, col::Integer,
                                 project::AbstractString; exec_path::AbstractString = "", args_template::AbstractString = "{file}",
                                 windows::Bool = Sys.iswindows(), which = Sys.which, exists = isfile)
    kind == EDITOR_NONE && return nothing
    if kind == EDITOR_VSCODE || kind == EDITOR_VSCODIUM
        p = find_program(exec_path, kind == EDITOR_VSCODE ? ("code",) : ("codium",); which)
        p === nothing && return nothing
        return EditorCommand(vscode_executable(p, windows; exists), [String(project), "--goto", "$file:$line:$col"])
```

So unit tests can ask "what would we launch on Windows when VS Code is installed at this path?" on any machine.

The ADR records the editor-specific details the tests pin down:

- Emacs uses `emacsclient -n +line:col`.
- Vim uses `+call cursor(line, col)`, with `--` for nvim-qt.
- On Windows, VS Code's `bin/code.cmd` shim is replaced by `Code.exe` next to it.

Opening a project in VS Code also writes these files, but only if they're missing:

- `.vscode/settings.json`, pointing the Julia extension at the project environment,
- `extensions.json`, recommending the Julia extension.

### Bootstrap, Templates and Dialogs

- **Project bootstrap.** Creating the first Julia script, or using *Project → Tools → Julia → Create Julia Project*, writes `Project.toml`.
  - It uses a PascalCase name from the settings or the Godot project name.
  - It depends on `Godot` through `[sources]`, pointing at the addon's copy of the package.
  - The native host already starts Julia with `--project` when that file exists.
- **Templates** mirror C#'s: Object, Node, Resource, EditorPlugin and EditorScript, each "Default" and/or "Empty".
  - Editor base classes are written `Godot.Editor.EditorPlugin` and so on.
  - Project templates in `res://script_templates/` use C#'s placeholders.
- **Create dialogs.** `@global_class` scripts already reached Godot's dialogs through phase 8's `_get_global_class_name`.
  - This phase added `_validate_path`.
  - It rejects file names that aren't Julia identifiers, because the class is named after the file.

### Build Before Play: A Different Default from C#

Requirement 2 asked for optional auto-build before running.

The agent implemented it (`julia/build/build_on_play`). But it chose a default different from C#'s, and explained why in the ADR:

> C# always builds; Julia scripts need no compilation to run, so the default favors fast iteration.

Parity is about **capability**. Defaults should fit the language.

## Where Reality Pushed Back

### The Editor Crashed While Loading the Plugin

The session history records the first crash of this phase in a single line from the agent: *"The import step crashed inside `add_control_to_bottom_panel` from `plugin_enter_tree`."*

Here's what was going on. Extension editor plugins enter the tree while Godot's `EditorNode` is still being constructed. At that moment there's no editor theme yet, and adding docks crashes.

The fix defers building the UI ([`plugin.jl`](../../julia/GodotEditor/src/tools/plugin.jl)):

```julia
function plugin_enter_tree(self::Ptr{Cvoid})
    plugin = Godot.wrap_object(self, false)
    define_settings!()
    Godot.Runtime.SCRIPT_CREATED_HOOK[] = ensure_project!
    # Extension editor plugins enter the tree while EditorNode is still being built (no editor theme yet; docks
    # added then crash), so the UI is built from `_process` once the editor is ready.
    UI_PENDING[] = true
    Godot.set_process(plugin, true)
    return nothing
end
```

The readiness check is explicit about what "ready" means:

- the base control exists and is ready,
- the editor theme exists,
- at least two frames have run.

Two related version facts went into the ADR:

- The legacy `add_control_to_bottom_panel` is replaced by `EditorDock` in Godot 4.6+. So the Julia panel is a dock in the bottom slot.
- Tabs restored from the previous session were created *before* plugins load. So a Julia tab gets the syntax highlighter when it becomes current.

### A Bug from Phase 7

Adding Julia-created `Control`s to the editor exposed a second crash, with a different cause. The phase 12 report:

> **Bug found on the way:** objects created from Julia (`Node()`, `Button()`, …) never received the post-initialize notification Godot requires after construction. That bug has been there since phase 07. Controls built from Julia had no theme setup, and adding them to the editor crashed it. `construct_object` now sends the notification for every object. All integration projects still pass, and row 4.1 records the fix.

Chapter 10 showed the fix from the object model's side. From this phase's side, the lesson is about **coverage**.

- Phase 7's tests created `Node`s and `Resource`s. Those don't care about `NOTIFICATION_POSTINITIALIZE`.
- Phase 12 was the first phase to build real editor UI from Julia. So it was the first to exercise the missing notification.

Notice what the agent did next:

- it fixed the root cause in `construct_object`, not a workaround in the editor plugin,
- it re-ran every integration project,
- it updated row 4.1's note so the history stays visible.

### Windows Drops Empty Arguments

Launching the build worker means passing a depot path, which is often empty.

On Windows, Godot's `OS.execute_with_pipe` and `create_process` silently drop empty-string arguments. Every later argument shifts by one.

The fix is a **sentinel value**, and the comment explains it ([`jobs.jl`](../../julia/GodotEditor/src/tools/jobs.jl)):

```julia
# Godot drops empty arguments when building a command line, so "no depot" is passed as "-".
depot_setting() = (d = string(something(Godot.get_setting(Godot.ProjectSettings, "julia/runtime/depot_path"), "")); isempty(d) ? "-" : d)
```

The worker side reads it back: `DEPOT == "-" || pushfirst!(DEPOT_PATH, DEPOT)`.

The rule is also in the agent's memory notes: *"never pass "" (worker uses "-")"*.

### `set_script` Replaces the Wrapper

Testing `@tool` scripts in the editor surfaced a subtlety:

> Like C#, attaching a script with `set_script` gives the object a new Julia wrapper, and a reload replaces it again. Code holding the old wrapper must re-fetch the object (the test uses `GD.instance_from_id`).

That follows from the design of chapters 10 and 14. The script struct *is* the object's wrapper, and a reload builds a new one.

So a plain local variable holding the old wrapper sees a freed object. The test shows the idiom:

```julia
            Godot.set_script(sp, scr)
            sp = Godot.GD.instance_from_id(id)   # like C#, the object gets a new wrapper: the script instance
```

### A Locked DLL

One more turn in the session history deserves a mention.

An integration run failed with `rm(...): directory not empty (ENOTEMPTY)` while syncing the addon into a test project.

The cause? A previous, timed-out Godot process was still running. On Windows, it held the addon's DLL open. Nothing was wrong with the code.

The lesson went into the agent's memory notes: *"Never run integration tests while a previous (timed-out) run is alive."*

Agents running long processes need **operational hygiene** as much as humans do.

## Closing the Loop

### A Headless Editor Test Written as a Julia Editor Plugin

The [`tests/integration/editor/`](../../tests/integration/editor) project runs with `--editor` (from its `run_args.txt`).

Its test is a Julia `@tool` class deriving from `Godot.Editor.EditorPlugin`, enabled in `project.godot` ([`addons/editor_test/EditorTest.jl`](../../tests/integration/editor/addons/editor_test/EditorTest.jl)):

```julia
# Headless editor checks for the Julia editor tools (parity: 1.4-1.6, 5.4, 7.3, 8.1-8.8). Being a Julia @tool EditorPlugin
# enabled in project.godot, it also checks that editor plugins can be written in Julia.
@tool @godot_class mutable struct EditorTest <: Godot.Editor.EditorPlugin
end

Godot._enter_tree(self::EditorTest) = (godot_task(() -> run_tests(self)); nothing)
```

The test covers requirement 7 (*"editor scripts written in Julia work"*) simply by existing.

Its checks walk through the prompt:

- the panel and toolbar button exist;
- every setting is registered;
- templates for all five base classes validate;
- editor base classes are qualified;
- `_validate_path` rejects `My Thing.jl`;
- creating a script bootstraps `Project.toml` with the right name and dependency;
- global classes appear with base type and icon;
- non-tool scripts get placeholder instances (closing row 5.4);
- saving a tool script reloads it in place with its state (closing row 7.3).

Finally, it runs a real build. The deliberate error in `Bad.jl` must be reported at the right line:

```julia
        Tools.build!()
        t0 = time()
        while Tools.busy() && time() - t0 < 240
            wait(next_frame(self))
        end
        check(!Tools.busy(), "build finished")
        probs = Tools.problems()
        check(any(q -> q.file == "res://Bad.jl" && q.line == 10, probs), "build reports res://Bad.jl:10 ($probs)")
```

The phase 12 report counted 40 checks in this project, passing on two additional runs.

On top of that came 46 new `GodotEditor` unit tests. They cover:

- external-editor commands per OS,
- bootstrap,
- the build-output protocol,
- VS Code settings,
- package add/status/remove.

They run offline with `JULIA_PKG_OFFLINE=true`.

```powershell
julia tests/integration/run.jl editor
$env:JULIA_LOAD_PATH = "$PWD\julia;@stdlib"; julia --project=julia/GodotEditor -e "using Pkg; Pkg.test()"
```

The second command reflects one more note from the agent's memory. `GodotEditor`'s unit tests need the repository's `julia/` folder on the load path, so they find the `Godot` package next to them.

## Techniques to Reuse

- **Specify UX by mapping to a known product.** For each feature, name its counterpart in an existing tool. Then add the essential details (columns, actions, click behavior) explicitly.
- **State responsiveness requirements.** "Without freezing the editor" is the requirement people forget. Offer acceptable implementations.
- **Let test requirements shape the design.** "Unit-test command construction per OS" forces a pure function with injected OS dependencies.
- **Test UI headlessly.** A scripted plugin in a headless editor can check panels, settings, dialogs, builds and reloads in CI.
- **Fix the root cause in the layer that owns it.** A missing notification in object construction gets fixed there, not patched in the editor plugin.
- **Choose defaults for the language, not the reference.** Parity is about capability. C#'s "always build" default doesn't fit Julia.

## Try It Yourself

1. Ask the agent to add a built-in template (for example `Node2D` with a `_process` stub) and a check in `EditorTest.jl` that it validates. Watch how it finds the template code in `GodotEditor` and the placeholders `_CLASS_`, `_BASE_`, `_TS_`.
2. Ask the **Ask** agent: *"What command would Godot-julia launch on Windows to open `res://Player.jl` at line 12, column 4 in VSCodium installed at `C:\Tools\VSCodium\bin\codium.cmd`?"* Then check the answer against `external_editor_command` and the unit tests.
3. Open `demos/editor_plugin/` in the Godot editor and read its Julia plugin. Ask the agent to add a menu item to it. Test the result in the editor yourself. This is one of the few checks in this book that needs a screen.

## Parity Rows

| Row | Capability | Status |
|-----|------------|--------|
| 1.4 | Third-party libraries (NuGet → Pkg) | DONE (Add/Remove/Update Packages, Package Status in a child process; tested offline) |
| 1.5 | Auto-generated project file | DONE (`Project.toml` on the first script; tested in `tests/integration/editor`) |
| 1.6 | Build button + output panel | DONE (non-blocking child-process build, then hot reload; optional build before Play) |
| 8.1 | External editors | DONE (VS Code, VSCodium, Emacs, Vim/Neovim, custom; command construction unit-tested per OS) |
| 8.2 | Open script at line/column | DONE |
| 8.3 | Create Script dialog + templates | DONE (every template validates) |
| 8.4 | Global classes in Create dialogs with icons | DONE |
| 8.5 | Project and editor settings | DONE (`julia/project/*`, `julia/runtime/*`, `julia/editor/*`, `julia/build/*`) |
| 8.6 | Script editor highlighting | DONE (native `JuliaSyntaxHighlighter`) |
| 8.7 | Validation errors in the editor | DONE |
| 8.8 | Build problems panel with clickable file:line | DONE |

The phase also closed rows 5.4 (placeholders) and 7.3 (tool-script reload in the editor), which phases 8 and 11 had left `PARTIAL`. It also corrected row 4.1's history.

---
[← Previous: Hot Reload](14-hot-reload.md) · [Contents](README.md) · [Next: Debugging →](16-debugging.md)
