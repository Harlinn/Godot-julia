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
