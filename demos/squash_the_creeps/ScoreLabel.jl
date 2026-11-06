# Ported from godot-demo-projects mono/squash_the_creeps/ScoreLabel.cs (MIT, Godot contributors).
using Godot

@godot_class mutable struct ScoreLabel <: Label
    score::Int = 0
end

function on_mob_squashed(self::ScoreLabel)
    self.score += 1
    self.text = "Score: $(self.score)"
end
