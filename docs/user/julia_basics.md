# Julia basics

GodotJL makes Julia a scripting language for Godot 4, alongside GDScript and C#. This page is the Julia counterpart of Godot's [C# basics](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_basics.html).

## Why Julia?

Julia is a dynamic language that compiles to fast native code, with multiple dispatch, a large scientific package ecosystem and a REPL. In Godot, Julia scripts:

- use the standard Godot editor and export templates (GodotJL is a GDExtension, not a custom engine build);
- can call, and be called from, GDScript and C# scripts;
- can use any Julia package from the project environment.

## Prerequisites

- Godot 4.7 (the standard editor, not the .NET one).
- Julia 1.12 or newer, on `PATH` (or set the project setting `julia/runtime/path`).
- The GodotJL addon: unzip the release into your project so that `addons/godot_julia/` exists, then restart the editor.

When the editor starts you will see a line such as `GodotJL: Julia 1.13.3 from ... startup 900 ms` in the Output panel.

## Configuring an external editor

Godot's script editor highlights and validates `.jl` files. For a full IDE, use VS Code with the Julia extension. In *Editor Settings → Julia → Editor → External Editor* choose *VS Code* (or Emacs, Vim/Neovim, or a custom command with `{file}`, `{line}`, `{col}` and `{project}` placeholders). Opening a script then opens it in that editor at the right line, and GodotJL writes `.vscode/settings.json` so that the Julia extension uses the project environment.

## Creating a script

Attach a script to a node and choose the *Julia* language in the *Attach Node Script* dialog. Like C#, a script file contains one class named after the file: `Greeter.jl` defines `Greeter`.

```julia
using Godot

@godot_class mutable struct Greeter <: Node
    @export greeting::String = "Hello"
    count::Int = 0
end

function Godot._ready(self::Greeter)
    println(self.greeting, " from Julia!")
end

function greet(self::Greeter, name::AbstractString)
    self.count += 1
    return "$(self.greeting), $(name)!"
end
```

- `@godot_class mutable struct Greeter <: Node` declares the script class. Its parent is the Godot class the script extends (C#: `public partial class Greeter : Node`).
- Fields are the script's members. `@export` makes a field appear in the inspector (C#: `[Export]`).
- Engine callbacks are methods of Godot's functions, written `Godot._ready(self::Greeter)` (C#: `public override void _Ready()`).
- Other functions whose first argument is the script type are the script's methods. GDScript, C# and the editor can call them by name.

Using the class from Julia code:

```julia
g = Greeter()                     # an engine Node with the script attached (C#: new Greeter())
add_child(DOC_ROOT, g)            # enters the tree: _ready prints "Hello from Julia!"
@test greet(g, "Godot") == "Hello, Godot!"
@test Godot.call(g, :greet, "GDScript") == "Hello, GDScript!"   # how other languages call it
@test g.count == 2
free(g)
```

## Project setup

GodotJL keeps a Julia project environment in the Godot project:

- `Project.toml` is created with the first Julia script. It depends on the `Godot` package that ships with the addon.
- *Project → Tools → Julia → Add Packages...* adds packages (C#: NuGet). The **Build** button in the toolbar instantiates and precompiles the environment, then validates every script. Problems appear in the *Julia* bottom panel, where you can click them to open the script at the line.
- Shared, non-script code belongs in a regular Julia package (for example `src/` with its own `Project.toml`, added to the environment) and is loaded with `using`, as you would put shared C# code in a class library.

A typical layout:

```text
my_game/
  project.godot
  Project.toml        # Julia environment (created automatically)
  Manifest.toml
  addons/godot_julia/ # the GodotJL addon
  player/Player.jl    # script: one @godot_class named Player
  main.tscn
```

## Hot reload

Saving a script in the editor reloads it, including instances in the running game (when started from the editor) and `@tool` scripts in the editor. Field values are kept, as with C#'s assembly reload. If the new code has an error, instances keep their state and wait for a successful reload.

## Next steps

- [Features](julia_features.md): conversions, casting and feature tags.
- [API differences](julia_api_differences.md): how Godot's API looks in Julia.
- [Coming from C#](coming_from_csharp.md): a side-by-side cheat sheet.
