# Coming from C#

A side-by-side cheat sheet for C# Godot developers. Every Julia line below is checked by the doc tests.

| Task | C# | Julia |
|------|----|-------|
| Script class | `public partial class Player : CharacterBody2D` | `@godot_class mutable struct Player <: CharacterBody2D ... end` |
| Exported property | `[Export] public int Speed { get; set; } = 400;` | `@export speed::Int = 400` |
| Signal | `[Signal] public delegate void HitEventHandler(int damage);` | `@signal hit(damage::Int)` |
| Emit | `EmitSignal(SignalName.Hit, 5);` | `emit_hit(self, 5)` or `emit_signal(self, :hit, 5)` |
| Connect | `button.Pressed += OnPressed;` | `connect_pressed(button, () -> on_pressed(self))` |
| Override callback | `public override void _Ready()` | `Godot._ready(self::Player) = ...` |
| `_Process` | `public override void _Process(double delta)` | `Godot._process(self::Player, delta::Float64)` |
| Get a node | `GetNode<Sprite2D>("Sprite")` | `get_node(Sprite2D, self, "Sprite")` |
| Instantiate | `var n = new Node2D();` | `n = Node2D()` |
| Scene | `GD.Load<PackedScene>("res://x.tscn").Instantiate()` | `instantiate(GD.load(PackedScene, "res://x.tscn"))` |
| Property | `Position = new Vector2(1, 2);` | `self.position = Vector2(1, 2)` |
| Singleton | `Input.IsActionPressed("jump")` | `is_action_pressed(Input, "jump")` |
| Print | `GD.Print("hi");` | `println("hi")` or `GD.print("hi")` |
| Cast | `node as Sprite2D`, `node is Sprite2D` | `as(Sprite2D, node)`, `node isa Sprite2D` |
| Free | `QueueFree();` | `queue_free(self)` |
| Await | `await ToSignal(timer, Timer.SignalName.Timeout);` | `@await to_signal(timer, :timeout)` (in a `godot_task`) |
| async method | `async void Run()` | `run(self) = (godot_task(() -> ...); nothing)` |
| Deferred | `CallDeferred(MethodName.Foo);` | `call_deferred(self, :foo)` |
| Tool | `[Tool]` | `@tool @godot_class ...` |
| Global class | `[GlobalClass]` | `@global_class @godot_class ...` |
| RPC | `[Rpc(MultiplayerApi.RpcMode.AnyPeer)]` | `@rpc :any_peer function f(self::T) ... end` |
| Preprocessor | `#if GODOT_WINDOWS` | `if Godot.@feature(:windows)` |
| Collections | `Godot.Collections.Array<int>` | `GDArray{Int}` |
| Math | `Mathf.Clamp(x, 0, 1)`, `Vector2.Zero` | `clamp(x, 0, 1)`, `Vector2_ZERO` |

## A complete script, both ways

C#:

```csharp
using Godot;

public partial class Coin : Area2D
{
    [Signal] public delegate void CollectedEventHandler(int value);
    [Export] public int Value { get; set; } = 10;

    public override void _Ready() => BodyEntered += OnBodyEntered;

    private void OnBodyEntered(Node2D body)
    {
        EmitSignal(SignalName.Collected, Value);
        QueueFree();
    }
}
```

Julia:

```julia
using Godot

@godot_class mutable struct Coin <: Area2D
    @signal collected(value::Int)
    @export value::Int = 10
end

Godot._ready(self::Coin) = (connect_body_entered(self, body -> on_body_entered(self, body)); nothing)

function on_body_entered(self::Coin, body::Node2D)
    emit_collected(self, self.value)
    queue_free(self)
end
```

```julia
coin = Coin()
got = Int[]
connect_collected(coin, v -> push!(got, v))
add_child(DOC_ROOT, coin)
on_body_entered(coin, Node2D())    # what the physics engine triggers
@test got == [10]
wait(next_frame(DOC_ROOT))
@test !is_instance_valid(coin)     # queue_free'd
```

## Things that work differently

- **Methods are functions.** `node.add_child(x)` is `add_child(node, x)`. Properties still use `obj.property`.
- **Indexing is 1-based** for `GDArray`, packed arrays and Julia vectors. Godot methods that take an index, such as `get_child(node, 0)`, keep Godot's 0-based indices.
- **No `partial`, no `using` directives per class.** One `using Godot` per script. Helper code goes in packages.
- **Builtin structs are immutable values.** Write `self.position = Vector2(x, self.position.y)` instead of setting `Position.X`.
- **Calling another Julia script's methods** from a different script uses the engine, `Godot.call(node, :method, args...)`, or the method itself when the scripts share a package.
