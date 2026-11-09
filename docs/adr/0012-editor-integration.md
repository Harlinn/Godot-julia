# ADR 0012: Editor integration

- Status: Accepted
- Date: 2026-11-05

## Context

C#'s editor tooling (GodotTools, loaded by GodotSharpEditor) generates the `.csproj`/`.sln`, adds a Build button and an MSBuild panel with a problems view, launches external IDEs, offers script templates, and registers `dotnet/*` settings. Phase 12 brings the same to Julia under the GDExtension constraints of ADR 0001.

## Decision

- **Native shim, Julia tools.** A native `JuliaEditorPlugin` (`EditorPlugin`) is added with `EditorPlugins::add_by_type` at the editor initialization level, only when `Engine.is_editor_hint()` is true. It forwards `_enter_tree`, `_exit_tree`, `_process` and `_build` over the script bridge. Everything else lives in `GodotEditor.Tools` (`julia/GodotEditor/src/tools/`), which installs its bridge handlers when `GodotEditor` loads (ADR 0004). `JuliaLanguage` forwards `_overrides_external_editor`, `_open_in_external_editor` and `_validate_path`. `Godot.Runtime` defines game-time defaults for these, which the tools replace.
- **Deferred UI.** Extension editor plugins enter the tree while `EditorNode` is still being constructed. The plugin registers its settings and the syntax highlighter immediately, and builds the UI from `_process` once the editor's base control and theme are ready.
- **Project bootstrap.** Creating the first Julia script (`_make_template`) or the menu entry *Project → Tools → Julia → Create Julia Project* writes `Project.toml`:
  - the name comes from `julia/project/package_name`, else the Godot project name, in PascalCase;
  - it gets a random UUID and depends on `Godot`, with `[sources]` pointing at the addon's copy of the package (or the development checkout) and `[compat]` set to its version;
  - the file is activated in the editor process at once.
  The native host already starts Julia with `--project` when `res://Project.toml` exists. *Build* instantiates the environment.
- **Builds in a child process.** *Build* (toolbar button, panel, menu) and the Pkg actions (*Add/Remove/Update Packages*, *Package Status*) run `GodotEditor/src/tools/worker.jl` in a child Julia process with the host's `LOAD_PATH` and depot. The plugin polls its pipes each frame (`OS.execute_with_pipe`, non-blocking), so the editor never freezes, as with C#'s `dotnet build`. A build runs:
  1. `Pkg.instantiate` and `Pkg.precompile`;
  2. validation of every user `.jl` file with the same parse + macro-expanding lowering as `_validate`;
  3. on success, a hot reload of all scripts (ADR 0011).
  The worker reports with a line protocol (`GDJL_STEP`, `GDJL_PROBLEM\tseverity\tfile\tline\tcol\tmessage`).
- **Julia panel.** The "Julia" panel is an `EditorDock` in the bottom slot; the legacy `add_control_to_bottom_panel` is replaced by docks in 4.6+. It holds Build, Clear and Copy Log actions, a status line, a problems view and the streamed log. Activating a problem opens the script at its line through `EditorInterface.edit_script`, which honors the external editor. Like C#'s `BuildProblemsView` (phase 17 audit), the problems view has error/warning toggles with counts, a search box, and a list or grouped-by-file layout (`julia/build/problems_layout`).
- **Translation templates (phase 17 audit).** A native `JuliaTranslationParserPlugin` (analog of C#'s `CsTranslationParserPlugin`) is registered with `add_translation_parser_plugin`. `GodotEditor.Tools` parses the `.jl` file with `Meta.parseall` and returns the string literals passed to `tr`, `atr`, `tr_n`, `atr_n`, `translate` and `translate_plural` (message, context, plural), with `# TRANSLATORS:` comments and `# NO_TRANSLATE` handled like C#. Interpolated strings are skipped.
- **Build before Play.** Optional (`julia/build/build_on_play`, default off). `_build` runs the build and waits for it, cancelling Play on failure. C# always builds; Julia scripts need no compilation to run, so the default favors fast iteration.
- **Settings.**
  - Project settings: `julia/project/package_name` and `julia/project/reload_attempts`, plus the host's `julia/runtime/*` (`path`, `threads`, `optimize`, `sysimage`, `depot_path`, `handle_signals`).
  - Editor settings: `julia/editor/external_editor` (None, VS Code, VSCodium, Emacs, Vim/Neovim, Custom), `julia/editor/custom_exec_path`, `julia/editor/custom_exec_path_args` (`{file}`, `{line}`, `{col}`, `{project}`), `julia/build/verbosity`, `julia/build/build_on_play` and `julia/build/problems_layout`.
- **External editors.** Command construction is a pure function, unit-tested per OS:
  - VS Code/VSCodium: `<project> --goto file:line:col`; on Windows the `bin/code.cmd` shim is replaced by `Code.exe` next to it.
  - Emacs: `emacsclient -n +line:col`.
  - Vim/Neovim: `+call cursor(line, col)`, with `--` for nvim-qt.
  - Custom: the argument template.
  Opening in VS Code writes `.vscode/settings.json` (`julia.environmentPath`) and `extensions.json` (recommends the Julia extension) when missing.
- **Templates.** Built-in templates mirror C#'s: Object (Empty), Node (Default), Resource (Empty), EditorPlugin (Default, Empty) and EditorScript (Default, Empty). Editor base classes are written `Godot.Editor.X`. Project templates in `res://script_templates/<Base>/*.jl` are found by Godot itself and use the same placeholders.
- **Create dialogs.** `@global_class` scripts reach the Create Node/Resource dialogs and typed export pickers through `_get_global_class_name` (phase 08). `_validate_path` rejects file names that are not Julia identifiers, because the class is named after the file.
- **Syntax highlighting.** Extensions cannot use the engine's `EditorStandardSyntaxHighlighter`, and without a language-specific highlighter the script editor falls back to plain text. A native `JuliaSyntaxHighlighter` (an `EditorSyntaxHighlighter` for language "Julia", the analog of `GDScriptSyntaxHighlighter`) is registered with the script editor in the plugin's `_enter_tree`. It colors keywords and control flow (the language's reserved words), macros, strings (including multi-line `"""`), comments (including `#= =#`), numbers, calls, and engine vs. user types, using the editor theme colors. Tabs restored from the previous session were created before plugins load, so a Julia tab gets the highlighter when it becomes current.
- **Reload on save.** Like `ResourceFormatSaverGDScript`, the Julia saver calls `_reload_tool_script` when *Auto Reload and Parse Scripts on Save* is on, so `@tool` instances migrate in place (ADR 0011).
- **Object construction fix.** Controls created from Julia never received `NOTIFICATION_POSTINITIALIZE`, which Godot requires after `classdb_construct_object*` (godot-cpp's `memnew` sends it). They lacked theme setup, and adding them as editor docks crashed. `construct_object` now uses `classdb_construct_object3` and sends the notification for every object (row 4.1).

## Consequences

- A build validates syntax and macro expansion, not types or names, because Julia has no ahead-of-time compile step equivalent to `csc`. Runtime errors still surface at load or call time with `res://` locations.
- Package actions need network access unless the packages are already in the depot. The tests run with `JULIA_PKG_OFFLINE=true`.
- Editor plugins, editor scripts and inspector plugins can be written in Julia (`@tool` classes deriving from `Godot.Editor.*`). The headless editor test is itself such a plugin.
