using Godot

@godot_class mutable struct Ticker <: Node
    n::Int = 0
end

Godot._process(self::Ticker, delta::Float64) = (self.n += 1; nothing)
