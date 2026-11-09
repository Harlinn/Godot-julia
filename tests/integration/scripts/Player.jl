# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot

@godot_class mutable struct Player <: Node2D
    @export speed::Float64 = 300.0
    @export label::String = "player"
    health::Int = 100
    ready_called::Bool = false
    process_frames::Int = 0
    notifications::Vector{Int} = Int[]
    @signal hit(damage::Int)
end

function Godot._ready(self::Player)
    self.ready_called = true
    nothing
end

function Godot._process(self::Player, delta::Float64)
    self.process_frames += 1
    nothing
end

function Godot._notification(self::Player, what::Int)
    push!(self.notifications, what)
    nothing
end

function take_damage(self::Player, amount::Int)
    self.health -= amount
    emit_signal(self, :hit, amount)
    return self.health
end

describe(self::Player) = "$(self.label):$(self.health)"
noop(self::Player, x::Int) = x

# Checks run from Julia; returns the names of failed checks (empty when all pass).
function julia_checks(self::Player)
    failed = String[]
    check(ok, what) = ok || push!(failed, what)
    parent = get_parent(self)
    # Engine calls that return the object yield the user's struct (instance binding = script struct).
    check(get_node(parent, "Player") === self, "get_node returns the script struct")
    check(Godot.get(self, :speed) == self.speed, "Object.get reads a Julia field")
    Godot.set(self, :health, 55)
    check(self.health == 55, "Object.set writes a Julia field")
    # A bad argument is a Godot call error (GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT), surfaced in Julia as GodotCallError.
    bad_call = try
        Godot.call(self, :take_damage, "oops")
        nothing
    catch e
        e
    end
    check(bad_call isa Godot.FFI.GodotCallError && bad_call.error == Godot.FFI.GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT &&
          self.health == 55, "bad argument is a call error")
    too_many = try
        Godot.call(self, :take_damage, 1, 2)
        nothing
    catch e
        e
    end
    check(too_many isa Godot.FFI.GodotCallError && too_many.error == Godot.FFI.GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS,
          "arity is checked")
    # Creating a script object from Julia (C#: new Player()).
    p = Player()
    check(p isa Player && p.speed == 300.0 && is_instance_valid(p), "Player() creates a scripted Node2D")
    check(Godot.get_script(p) == Godot.get_script(self), "Player() attaches the script")
    free(p)
    check(!is_instance_valid(p), "freed")
    self.health = 90
    return failed
end
