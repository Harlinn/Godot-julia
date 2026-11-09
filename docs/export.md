# Exporting games with Julia scripts

Export Julia games the usual way (*Project → Export*): the Julia export plugin compiles the scripts and ships the Julia runtime in a `data_<Package>_<platform>_<arch>/` folder next to the executable, like C# ships `data_*` with its assemblies. Keep that folder with the game. Design: [ADR 0014](adr/0014-export.md).

## Requirements

- Export templates for the editor's Godot version.
- The Godot-julia template libraries in `addons/godot_julia/bin/` (`template_debug` and `template_release`, built with `scons target=template_debug|template_release`).
- Export **on the target platform**. The Julia payload (runtime and system image) comes from the editor's Julia installation, so Windows games are exported on Windows, Linux games on Linux and macOS games on macOS, each for the host architecture. Android, iOS and Web exports are not supported.

## Preset options

| Option | Values | Meaning |
|---|---|---|
| `julia/export/mode` | `sysimage` (default), `jit` | `sysimage`: Godot, the project's packages and the scripts are compiled into a system image (ReadyToRun-like); scripts load without their sources. `jit`: package sources and compiled caches are shipped and scripts run from source (debug exports only; faster to export). |
| `julia/export/include_sources` | `false` (default) | Keep the `.jl` sources in the PCK. By default they are replaced by empty files, like C# scripts. |
| `julia/export/include_debug_symbols` | `false` (default) | Keep line information in release system images, so backtraces show file:line in release exports too (C#: `dotnet/include_debug_symbols`, which C# turns on by default). Costs about 100 MiB of payload. Debug exports always keep line information. |

Exporting in `sysimage` mode compiles a system image in a child process (several minutes; progress in the Julia panel or the console). Debug exports are compiled with `-O2` and keep the Julia debug server and the remote debugger. Release exports use `-O3`.

## Scripts that need the engine at load time

In `sysimage` mode scripts are evaluated while the image is built, without a running engine. A script whose top-level code calls the engine, for example `const SCENE = Godot.load(Godot.ResourceLoader, "res://x.tscn")`, cannot be compiled in. The export prints a warning naming the script, ships its source in `data_*/scripts/`, and evaluates it at runtime as in the editor. To keep it compiled, load resources in `_ready` or lazily instead of at top level.

## Platform-specific code

```julia
if Godot.@feature(:windows)      # compile-time constant in sysimage exports (C#: #if GODOT_WINDOWS)
    use_windows_paths()
end
Godot.has_feature(:mobile)       # runtime check (OS.has_feature)
```

`@feature` accepts any feature tag: platform (`windows`, `linux`, `macos`, `pc`), `debug`, `release`, `template`, `editor`, the architecture, and custom tags of the preset. Outside exports it is a runtime check.

## What ships

| Path | Content |
|---|---|
| `julia/` | Julia runtime libraries (JIT included), Base and stdlib sources |
| `sys.dll` / `sys.so` / `sys.dylib` | system image (`sysimage` mode) |
| `env/Project.toml` | the game's package environment |
| `scripts/` | sources of scripts not compiled into the image |
| `depot/` | package sources and compiled caches (`jit` mode) |
| `godot_julia_export.cfg` | mode and runtime options read by the native host |

Sizes and startup times are recorded in [perf.md](perf.md).

## macOS signing

Sign `data_*/julia/lib/*.dylib`, the system image and the Godot-julia framework along with the app (`codesign --deep` does not descend into the data folder). Notarization requires the hardened runtime with the `com.apple.security.cs.allow-jit` and `com.apple.security.cs.allow-unsigned-executable-memory` entitlements, because Julia's JIT generates code at runtime. This has not been verified yet.

## Testing exports

`julia tests/export/run.jl [sysimage-debug] [sysimage-release] [jit-debug]` exports `tests/export/game` and the smoke project for the host platform, runs the exported games headlessly and prints export time, size and startup time. It uses the templates archive in `.tools/godot/` or installed templates.
