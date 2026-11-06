using Godot

# A non-tool script: the editor gives its objects placeholder instances holding exported values.
@godot_class mutable struct Plain <: Node
    @export size::Int = 3
    hidden::Int = 0
end
