using Godot

# Inherits from the global class Enemy by name; resolved when the system image is built.
@godot_class mutable struct Boss <: Enemy
    armor::Int = 3
end

hit!(self::Boss, n::Int) = (self.hp -= max(n - self.armor, 0); self.hp)
