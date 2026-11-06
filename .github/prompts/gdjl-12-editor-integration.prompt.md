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
