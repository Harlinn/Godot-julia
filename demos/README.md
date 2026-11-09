# Demos

Julia ports of the official C# demos from [godot-demo-projects](https://github.com/godotengine/godot-demo-projects) (`mono/`), plus an editor-plugin demo written for Godot-julia.

| Demo | Source | Shows |
|------|--------|-------|
| [dodge_the_creeps](dodge_the_creeps) | `mono/dodge_the_creeps` ("Your first 2D game") | `@export` of a `PackedScene`, `@signal`, signals connected in scenes, async game-over with `godot_task` + `@await to_signal`, calling other scripts |
| [pong](pong) | `mono/pong` | 2D areas, `script_type` to test for another script's class, exported properties set in the scene |
| [squash_the_creeps](squash_the_creeps) | `mono/squash_the_creeps` ("Your first 3D game") | `CharacterBody3D`, slide collisions, connecting a script signal to a closure |
| [multiplayer_pong](multiplayer_pong) | `mono/multiplayer_pong` | ENet multiplayer with `@rpc` (`:any_peer`, `:call_local`, `:unreliable`) and `rpc(node, :method, ...)` |
| [editor_plugin](editor_plugin) | new | A `@tool` `EditorPlugin` in Julia (dock + button that edits the scene) and a `@tool` `@global_class` node that runs in the editor |

Scenes and assets of the ports are copied unchanged from upstream (`scripts/port_csharp_demo.jl`); only script paths, signal connection methods and exported member names are converted to the Julia scripts' snake_case names. Each port's README keeps the upstream asset credits.

## Running

Open a demo folder in the Godot editor after copying `addons/godot_julia` into it (or run `julia demos/run.jl <demo>` once, which does that).

`julia demos/run.jl [demo...]` runs every demo headlessly and fails on errors, script errors or leaks. The games are played by `driver.gd`, which is injected as an autoload for the run: it starts a Dodge game and goes through game over, lets the Pong ball bounce, waits for Squash mobs, and connects a host and a client process for multiplayer Pong. The editor-plugin demo runs in the headless editor, where `editor_driver.gd` presses the Julia dock's button.

## License

The four ported demos (code and scenes) are MIT licensed by the Godot Engine contributors ([LICENSE.md](LICENSE.md)); the assets' own licenses are listed in each demo's README. The editor-plugin demo and the demo runner (`run.jl`, `driver.gd`, `editor_driver.gd`) are part of Godot-julia and licensed under the Apache License 2.0 ([LICENSE](../LICENSE)).
