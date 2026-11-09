---
name: book-ch15-editor-integration
description: "Book chapter 15: the logic behind gdjl-12-editor-integration — GodotTools parity for Julia: project bootstrap, Build panel, external editors, templates, packages."
agent: agent
---
Write chapter 15 of the book, `docs/book/15-editor-integration.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-12-editor-integration](../gdjl-12-editor-integration.prompt.md).

## Focus

- **UX parity as a specification.** The prompt maps each C# editor feature to a Julia counterpart: `.csproj` → `Project.toml`, MSBuild panel → Julia panel, NuGet → `Pkg`, hammer button → Build. Show how naming the user-facing analog gives an agent a concrete target for UI work, which is otherwise hard to specify.
- **Non-blocking by requirement.** "Run builds without freezing the editor" led to a child process with streamed output. Requirements about responsiveness that are easy to overlook.
- **Settings as a contract.** Explicit setting names (`julia/editor/external_editor`, placeholders `{file}`, `{line}`, …) make behavior testable and documentable.
- **Testing an editor headlessly.** `godot --editor --headless` driven by scripts, plus unit tests for command construction per OS.

## Leads to Verify

- ADR 0012: a native `JuliaEditorPlugin` and `JuliaSyntaxHighlighter` (`julia_editor.cpp`), with Julia tools in `GodotEditor/src/tools` whose bridge handlers merge into `Runtime.BRIDGE` at `GodotEditor.__init__`.
- The UI is built only once the editor is ready (from `_process`), and docks use `EditorDock` (Godot 4.6+). This is version-specific API knowledge the agent had to look up.
- Windows quirk: `OS.execute_with_pipe`/`create_process` drop empty-string arguments, so the worker uses `-`.
- `set_script` on a Julia-held wrapper of a tool script invalidates it; re-fetch via `GD.instance_from_id`.
- `NOTIFICATION_POSTINITIALIZE` was missing from object construction, so Controls created from Julia crashed editor docks. Found and fixed here (cross-reference chapter 10).
- GodotEditor unit tests need `JULIA_LOAD_PATH="<repo>/julia;@stdlib"`.

## Artifacts to Inspect

`native/src/julia_editor.cpp`, `julia/GodotEditor/src/`, `addons/godot_julia/script_templates/`, `addons/godot_julia/tools/`, `docs/adr/0012-editor-integration.md`, `tests/integration/editor/`, `julia/GodotEditor/test/`, `demos/editor_plugin/`.

## Try It Yourself

Ask the agent to add a new built-in script template and a headless editor test proving it validates. Observe how it finds the template placeholders (`_CLASS_`, `_BASE_`, `_TS_`).

Parity rows: 1.4–1.6, 8.1–8.8. Navigation: previous chapter 14, next chapter 16.
