using Godot

# A @tool node: it runs in the editor too, so the spinner turns and redraws while you edit the scene.
@tool @global_class @godot_class mutable struct Spinner <: Node2D
    @export_range (0.0, 10.0; step = 0.1) speed::Float64 = 1.0
    @export color::Color = Color(0.58, 0.35, 0.69)
    @export_range (4, 64) radius::Int = 32
    turns::Float64 = 0.0
end

function Godot._process(self::Spinner, delta::Float64)
    self.rotation += Float32(self.speed * delta)
    self.turns += self.speed * delta / (2π)
    queue_redraw(self)
end

function Godot._draw(self::Spinner)
    r = Float32(self.radius)
    draw_circle(self, Vector2_ZERO, r, self.color)
    draw_line(self, Vector2_ZERO, Vector2(r, 0), Color(1, 1, 1), 3.0)
end
