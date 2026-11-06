using Godot

# A @tool script: real instances run in the editor and hot-reload on save with their state.
@tool @godot_class mutable struct Spinner <: Node
    @export speed::Float64 = 1.0
    turns::Int = 0
end

spin(self::Spinner) = (self.turns += 1; self.turns)
