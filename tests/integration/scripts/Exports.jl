using Godot

# `Item` is a Julia @global_class: usable by name as a field type without importing it (parity: 5.13).

@enum Mode Walk Run Fly

@tool @godot_class mutable struct Exports <: Node2D
    @export_category("Movement")
    @export speed::Float64 = 300.0
    @export_range (0, 100, 1; or_greater = true) health::Int = 100
    @export_group("Visuals"; prefix = "visual_")
    @export visual_tint::Color = Color(1, 1, 1)
    @export_color_no_alpha visual_bg::Color = Color(0, 0, 0)
    @export_subgroup("Text")
    @export_multiline notes::String = ""
    @export_placeholder "Name..." title::String = ""
    @export_group("")
    @export_enum ("Small", "Large:5") size::Int = 0
    @export mode::Mode = Walk
    @export_flags ("Fire", "Water", "Earth") elements::Int = 0
    @export_flags_2d_physics layers::Int = 1
    @export_file ("*.png", "*.jpg") image::String = ""
    @export_dir folder::String = ""
    @export_exp_easing ("attenuation",) easing::Float64 = 1.0
    @export_node_path (Sprite2D,) sprite_path::NodePath = NodePath("")
    @export target::Node2D
    @export item::Item
    @export items::GDArray{Int}
    @export lookup::GDDictionary{String, Int}
    @export_storage hidden_state::Int = 3
    @export_custom (Godot.PROPERTY_HINT_PASSWORD, "", Godot.PROPERTY_USAGE_DEFAULT) password::String = ""
    @export_tool_button ("Reset", "Reload") reset_button = reset!
    last_shot::Int = 0
    @signal changed(old::Int, new::Int)
end

reset!(self::Exports) = (self.speed = 300.0; nothing)

@rpc :any_peer :call_local :unreliable_ordered channel = 1 function shoot(self::Exports, power::Int)
    self.last_shot = power
    return power
end

@rpc ping(self::Exports) = nothing

double_it(::Type{Exports}, x::Int) = 2x

# Checks run from Julia; returns the names of failed checks.
function julia_checks(self::Exports)
    failed = String[]
    check(ok, what) = ok || push!(failed, what)
    got = Tuple{Int, Int}[]
    connect_changed(self, (a, b) -> push!(got, (a, b)))
    emit_changed(self, 1, 2)
    check(got == [(1, 2)], "typed signal helpers")
    check(SignalName(Exports).changed === :changed && PropertyName(Exports).item === :item, "name tables")
    check(:shoot in keys(MethodName(Exports)), "MethodName")
    check(self.item isa Item && self.item.power == 7, "exported script resource from .tres")
    check(self.target isa Node2D, "exported node resolved from NodePath")
    check(self.mode === Fly, "enum set from GDScript as an int")
    # call_local RPCs run locally (the default OfflineMultiplayerPeer is the authority).
    rpc(self, :shoot, 9)
    check(self.last_shot == 9, "rpc() of a Julia @rpc function")
    return failed
end
