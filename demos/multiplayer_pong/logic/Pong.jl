# Ported from godot-demo-projects mono/multiplayer_pong/logic/Pong.cs (MIT, Godot contributors).
using Godot

const SCORE_TO_WIN = 3

@godot_class mutable struct Pong <: Node2D
    @signal game_finished(with_error::String)
    score_left::Int = 0
    score_right::Int = 0
end

function Godot._ready(self::Pong)
    multiplayer = get_multiplayer(get_tree(self))
    player_two = get_node(self, "Player2")
    # The server's peer controls player two on the server; each client controls player two locally.
    if is_server(multiplayer)
        set_multiplayer_authority(player_two, get_peers(multiplayer)[1])
    else
        set_multiplayer_authority(player_two, get_unique_id(multiplayer))
    end
    println("Unique id: ", get_unique_id(multiplayer))
end

@rpc :call_local function update_score(self::Pong, add_to_left::Bool)
    if add_to_left
        self.score_left += 1
        get_node(Label, self, "ScoreLeft").text = string(self.score_left)
    else
        self.score_right += 1
        get_node(Label, self, "ScoreRight").text = string(self.score_right)
    end
    game_ended = false
    if self.score_left == SCORE_TO_WIN
        show(get_node(Label, self, "WinnerLeft"))
        game_ended = true
    elseif self.score_right == SCORE_TO_WIN
        show(get_node(Label, self, "WinnerRight"))
        game_ended = true
    end
    if game_ended
        show(get_node(Button, self, "ExitGame"))
        rpc(get_node(self, "Ball"), :stop)
    end
end

on_exit_game_pressed(self::Pong) = emit_game_finished(self, "")
