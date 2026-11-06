using Godot

# A global class other scripts inherit from by name.
@global_class @godot_class mutable struct Enemy <: Node
    hp::Int = 10
    readied::Bool = false
end

Godot._ready(self::Enemy) = (self.readied = true; nothing)
damage!(self::Enemy, n::Int) = (self.hp -= n; self.hp)
