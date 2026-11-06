# Ported from godot-demo-projects mono/multiplayer_pong/logic/Lobby.cs (MIT, Godot contributors).
using Godot

const DEFAULT_PORT = 8910        # An arbitrary number.
const MAX_NUMBER_OF_PEERS = 1    # How many people we want to have in a game.

@godot_class mutable struct Lobby <: Control
    peer::Union{Nothing, ENetMultiplayerPeer} = nothing
end

multiplayer_api(self::Lobby) = get_multiplayer(get_tree(self))

function Godot._ready(self::Lobby)
    # Connect all callbacks related to networking.
    mp = multiplayer_api(self)
    connect(mp, :peer_connected, id -> player_connected(self, id))
    connect(mp, :peer_disconnected, id -> player_disconnected(self, id))
    connect(mp, :connected_to_server, () -> nothing)   # Not needed for this project.
    connect(mp, :connection_failed, () -> connected_fail(self))
    connect(mp, :server_disconnected, () -> end_game(self, "Server disconnected"))
end

function player_connected(self::Lobby, id)
    # Someone connected, start the game!
    pong = instantiate(GD.load(PackedScene, "res://pong.tscn"))
    # Connect deferred so we can safely erase it from the callback.
    connect(pong, :game_finished, err -> end_game(self, err); flags = GodotObject_CONNECT_DEFERRED)
    add_child(get_root(get_tree(self)), pong)
    hide(self)
end

player_disconnected(self::Lobby, id) =
    end_game(self, is_server(multiplayer_api(self)) ? "Client disconnected" : "Server disconnected")

function connected_fail(self::Lobby)
    set_status(self, "Couldn't connect", false)
    remove_peer!(self)
end

function remove_peer!(self::Lobby)
    multiplayer_api(self).multiplayer_peer = nothing
    get_node(Button, self, "HostButton").disabled = false
    get_node(Button, self, "JoinButton").disabled = false
end

function end_game(self::Lobby, with_error::AbstractString = "")
    if has_node(self, "/root/Pong")
        # Erase immediately, otherwise the network might show errors (why we connected deferred above).
        free(get_node(self, "/root/Pong"))
        show(self)
    end
    remove_peer!(self)
    set_status(self, with_error, false)
end

function set_status(self::Lobby, text::AbstractString, is_ok::Bool)
    get_node(Label, self, "StatusOk").text = is_ok ? text : ""
    get_node(Label, self, "StatusFail").text = is_ok ? "" : text
end

function on_host_pressed(self::Lobby)
    peer = ENetMultiplayerPeer()
    if create_server(peer, DEFAULT_PORT, MAX_NUMBER_OF_PEERS) != OK
        set_status(self, "Can't host, address in use.", false)   # Is another server running?
        return
    end
    compress(peer.host, ENetConnection_COMPRESS_RANGE_CODER)
    self.peer = peer
    multiplayer_api(self).multiplayer_peer = peer
    get_node(Button, self, "HostButton").disabled = true
    get_node(Button, self, "JoinButton").disabled = true
    set_status(self, "Waiting for player...", true)
end

function on_join_pressed(self::Lobby)
    ip = get_node(LineEdit, self, "Address").text
    if !is_valid_ip_address(ip)
        set_status(self, "IP address is invalid", false)
        return
    end
    peer = ENetMultiplayerPeer()
    create_client(peer, ip, DEFAULT_PORT)
    compress(peer.host, ENetConnection_COMPRESS_RANGE_CODER)
    self.peer = peer
    multiplayer_api(self).multiplayer_peer = peer
    set_status(self, "Connecting...", true)
end
