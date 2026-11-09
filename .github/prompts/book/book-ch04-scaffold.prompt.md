---
name: book-ch04-scaffold
description: "Book chapter 4: the logic behind gdjl-01-scaffold — pinning versions, choosing GDExtension over a module, and executable done-when criteria."
agent: agent
---
Write chapter 4 of the book, `docs/book/04-scaffold.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-01-scaffold](../gdjl-01-scaffold.prompt.md).

## Focus

- **Decisions before code.** Pinning `GODOT_VERSION` and the godot-cpp submodule, and writing ADR 0000 (GDExtension vs engine module) and ADR 0001 (build system) first. Explain why early ADRs keep later sessions from re-opening the architecture.
- **`${input:godotTag:…}`.** A prompt parameter with a default turns the prompt into a reusable command.
- **Listing module-only capabilities to watch** (from `modules/mono/register_types.cpp`): asking the agent to find risks up front.
- **"Done when" as executable checks**: a build succeeds, `godot --headless … --quit` prints the init message, `Pkg.test()` passes. Contrast this with vague acceptance criteria.
- **A walking skeleton.** The smallest end-to-end path (editor loads the extension, prints a line) comes before any feature.

## Leads to Verify (Drop Any You Cannot Confirm)

- Pinned Godot 4.7.2-stable. godot-cpp is versioned independently (10.0.0-stable), and `api_version` is passed from `native/SConstruct`.
- The prompt's dump flags became `--dump-extension-api-with-docs --dump-gdextension-interface-json` in Godot 4.6+, and `scripts/fetch_api.jl` falls back to the JSON bundled with godot-cpp. This is an example of the prompt being outdated and the agent adapting.
- A headless smoke run needs `--import` once before `--quit` so `.godot/extension_list.cfg` registers the extension.
- Godot issues #111048/#123511: the headless editor crashes at exit on the first scan that discovers a `.gdextension`. The workaround pre-writes `.godot/extension_list.cfg` in `scripts/prepare_test_projects.jl`.
- Windows tooling lessons: SCons finds MSVC by itself, piping scons into `Select-Object -First N` kills the build, `native/SConstruct` must `env.Clone()` before appending flags or godot-cpp rebuilds fully, and `curl.exe` with a SHA-512 check is used instead of the slow `Invoke-WebRequest`.

## Artifacts to Inspect

`GODOT_VERSION`, `native/SConstruct`, `native/src/register_types.cpp`, `addons/godot_julia/godot_julia.gdextension`, `scripts/fetch_api.jl`, `scripts/fetch_godot.jl`, `scripts/prepare_test_projects.jl`, `tests/integration/smoke/`, `docs/adr/0000-gdextension-vs-module.md`, `docs/adr/0001-build-system.md`, `README.md`.

## Try It Yourself

Ask the Plan agent to scaffold a minimal GDExtension in another language (for example Rust or Zig) using this prompt as a template, and compare its done-when checks with the original's.

Parity rows: 1.2, 1.3. Navigation: previous chapter 3, next chapter 5.
