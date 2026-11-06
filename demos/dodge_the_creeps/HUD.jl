# Ported from godot-demo-projects mono/dodge_the_creeps/HUD.cs (MIT, Godot contributors).
using Godot

@godot_class mutable struct HUD <: CanvasLayer
    @signal start_game()
end

function show_message(self::HUD, text::AbstractString)
    message_label = get_node(Label, self, "MessageLabel")
    message_label.text = text
    show(message_label)
    start(get_node(Godot.Timer, self, "MessageTimer"))
end

# C#'s `async void` method: a Godot task that awaits signals on the main thread; the engine gets `nothing` back.
function show_game_over(self::HUD)
    godot_task() do
        show_message(self, "Game Over")
        @await to_signal(get_node(Godot.Timer, self, "MessageTimer"), :timeout)

        show_message(self, "Dodge the\nCreeps!")
        @await to_signal(create_timer(get_tree(self), 1.0), :timeout)

        show(get_node(Button, self, "StartButton"))
    end
    return nothing
end

update_score(self::HUD, score::Int) = (get_node(Label, self, "ScoreLabel").text = string(score); nothing)

function on_start_button_pressed(self::HUD)
    hide(get_node(Button, self, "StartButton"))
    emit_start_game(self)
end

on_message_timer_timeout(self::HUD) = hide(get_node(Label, self, "MessageLabel"))
