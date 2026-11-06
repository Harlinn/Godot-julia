# Exporting

Games with Julia scripts are exported like any Godot game (*Project → Export*). The export plugin compiles the scripts and ships the Julia runtime in a `data_<Package>_<platform>_<arch>/` folder next to the executable, as C# ships `data_*` with its assemblies. Keep that folder with the game.

The complete guide is [docs/export.md](../export.md). In brief:

- **Modes** (`julia/export/mode` in the preset):
  - `sysimage` (default) compiles Godot, your packages and your scripts into a system image (ReadyToRun-like); scripts load without their sources.
  - `jit` ships package sources and compiled caches. It is for debug exports only and exports faster.
- **Sources**: `.jl` files are replaced by empty files in the PCK unless `julia/export/include_sources` is set.
- **Platforms**: Windows, Linux and macOS desktop. Export on the platform you target, because the payload comes from the editor's Julia installation.
- **Engine calls at load time**: a script whose top-level code calls the engine (for example `const SCENE = Godot.load(...)`) is shipped as source and evaluated at startup. Load resources in `_ready` instead to keep the script compiled.

## Platform-specific code

`Godot.@feature(:tag)` is a compile-time constant in system-image exports (C#: `#if GODOT_WINDOWS`):

```julia
save_dir = Godot.@feature(:windows) ? "AppData" : Godot.@feature(:macos) ? "Library" : ".local/share"
@test save_dir in ("AppData", "Library", ".local/share")
@test Godot.@feature(:editor) == Godot.has_feature(:editor)   # true in the editor, false in exported games
```

Scripts evaluated at runtime, which happens in `jit` exports or for scripts shipped as source, define their methods after the code that loaded them was compiled. Call their constructors and functions through `Base.invokelatest` when the calling code was compiled earlier. For example, with this script:

```julia
using Godot

@godot_class mutable struct Saver <: Node
    index::Int = 1
end

slot(self::Saver) = "slot-$(self.index)"
```

```julia
T = Godot.script_type("res://julia_export/Saver.jl")
s = Base.invokelatest(T)
@test Base.invokelatest(getglobal(parentmodule(T), :slot), s) == "slot-1"
free(s)
```
