# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot

# Dynamic properties through the engine's script callbacks (C#: _Get, _Set, _GetPropertyList, _ValidateProperty).
@godot_class mutable struct Dyn <: Node
    @export shown::Int = 1
    @export secret::Int = 7
    virtual::Base.RefValue{Int} = Ref(42)
end

Godot._get(self::Dyn, name::Symbol) = name === :virtual_value ? self.virtual[] : nothing

function Godot._set(self::Dyn, name::Symbol, value)
    name === :virtual_value || return false
    self.virtual[] = value
    return true
end

Godot._get_property_list(self::Dyn) =
    [Dict("name" => "virtual_value", "type" => Int(Godot.TYPE_INT), "usage" => Int(Godot.PROPERTY_USAGE_DEFAULT))]

function Godot._validate_property(self::Dyn, prop::Dict)
    prop["name"] == "secret" && (prop["usage"] = prop["usage"] & ~Int(Godot.PROPERTY_USAGE_EDITOR))
    return nothing
end

Godot._property_can_revert(self::Dyn, name::Symbol) = name === :virtual_value
Godot._property_get_revert(self::Dyn, name::Symbol) = name === :virtual_value ? 42 : nothing
