# Signals

Counterpart of Godot's [C# signals](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_signals.html).

## Declaring signals

Declare a script's signals inside `@godot_class` with `@signal` (C#: a `[Signal]` delegate). Typed parameters are checked when the signal is emitted from Julia, and appear in the editor's signal list.

```julia
using Godot

@godot_class mutable struct Hero <: Node
    @signal health_changed(old::Int, new::Int)
    @signal died()
    health::Int = 100
end

function take_damage(self::Hero, amount::Int)
    old = self.health
    self.health = max(old - amount, 0)
    emit_health_changed(self, old, self.health)   # C#: EmitSignal(SignalName.HealthChanged, old, Health)
    self.health == 0 && emit_died(self)
end
```

For each signal, `@godot_class` generates `emit_<name>` and `connect_<name>` helpers, plus the name table `SignalName(Hero)` (C#: `SignalName.HealthChanged`).

## Connecting

`connect(obj, :signal, f)` connects any Julia function or closure (C#: `+=` on the event, or `Connect(..., Callable.From(...))`). It returns the `Callable`, which `disconnect` accepts.

```julia
hero = Hero()
log = Tuple{Int, Int}[]
connect_health_changed(hero, (old, new) -> push!(log, (old, new)))    # typed helper
c = connect(hero, :died, () -> push!(log, (0, 0)))                    # by name
take_damage(hero, 30)
take_damage(hero, 100)
@test log == [(100, 70), (70, 0), (0, 0)]
@test SignalName(Hero).died === :died
disconnect(hero, :died, c)
@test !is_connected(hero, :died, c)
free(hero)
```

Engine signals have generated helpers too: `connect_timeout(timer, f)`, `connect_pressed(button, f)`, and so on.

```julia
button = Button()
clicks = Ref(0)
connect_pressed(button, () -> (clicks[] += 1; nothing))
emit_signal(button, :pressed)
@test clicks[] == 1
free(button)
```

## Connection flags

Pass Godot's connect flags with `flags`, for example a one-shot or deferred connection:

```julia
node = Node()
add_user_signal(node, "ping")
hits = Ref(0)
connect(node, :ping, () -> (hits[] += 1; nothing); flags = GodotObject_CONNECT_ONE_SHOT)
emit_signal(node, :ping)
emit_signal(node, :ping)
@test hits[] == 1
free(node)
```

## Automatic disconnection

A connection made with a closure is tied to the engine object the closure captures (C#: the delegate's `Target`). When that object is freed, Godot drops the connection. A closure that captures no engine object stays connected until the signal's owner is freed or you disconnect it.

## Signals connected in the editor

Connections made in the editor's *Node → Signals* dock call a script method by name. Use the method's Julia name, for example `on_button_pressed`:

```julia
@godot_class mutable struct Menu <: Control
    presses::Int = 0
end

on_start_pressed(self::Menu) = (self.presses += 1; nothing)
```

```julia
menu = Menu()
b = Button()
add_child(menu, b)
connect(b, :pressed, Callable(menu, :on_start_pressed))   # what a scene connection does
emit_signal(b, :pressed)
@test menu.presses == 1
free(menu)
```

## Awaiting a signal

`wait(to_signal(obj, :signal))`, or `@await to_signal(...)`, returns the signal's arguments as a tuple. It must run in a Godot task: see [async](julia_async.md).

```julia
t = godot_task() do
    timer = Godot.Timer()
    add_child(DOC_ROOT, timer)
    start(timer, 0.05)
    args = @await to_signal(timer, :timeout)    # C#: await ToSignal(timer, Timer.SignalName.Timeout)
    free(timer)
    args
end
@test fetch(t) == ()
```

## The Signal type

`Signal(obj, :name)` is Godot's first-class signal value, as in C#:

```julia
node = Node()
add_user_signal(node, "changed")
s = Signal(node, :changed)
seen = Ref(false)
f = () -> (seen[] = true; nothing)
connect(s, f)
emit(s)
@test seen[] && is_connected(s, f)
disconnect(s, f)
free(node)
```
