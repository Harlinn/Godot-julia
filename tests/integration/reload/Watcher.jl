using Godot

# Not reloaded with Mover, but holds references to a Mover instance (a field and a connected closure).
@godot_class mutable struct Watcher <: Node
    target::Node
    seen::Int = 0
end

function watch(self::Watcher, m::Node)
    self.target = m
    connect(m, :moved, n -> (self.seen = n + 100 * getproperty(m, :count); nothing))
    return nothing
end

target_count(self::Watcher) = getproperty(self.target, :count)
