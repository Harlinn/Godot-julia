# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# @godot_class metadata, exports and diagnostics. parity: 5.5, 5.6, 5.19
using Godot.Runtime: Runtime

module ScriptTestA
using Godot
@godot_class mutable struct Mover <: Node2D
    "Movement speed."
    @export speed::Float64 = 300.0
    health::Int = 100
    target::Node
    scratch::Base.RefValue{Int} = Ref(0)
    @signal hit(damage::Int, source)
end
take_damage(self::Mover, n::Int) = (self.health -= n; self.health)
Godot._ready(self::Mover) = nothing
helper(x) = x

@tool @global_class @icon "res://icon.svg" @godot_class mutable struct ToolThing <: Resource
end
end

module ScriptTestB
using Godot
using ..ScriptTestA: Mover
@godot_class abstract mutable struct Boss <: Mover
    armor::Float32 = 2
end
end

module ScriptTestC
using Godot
@enum Mode Walk Run Fly
@tool @godot_class mutable struct Exports <: Node2D
    @export_category("Movement")
    @export speed::Float64 = 300.0
    @export_range (0, 100, 1; or_greater = true) health::Int = 100
    @export_range (0.0, 1.0; step = 0.05, suffix = "m") ratio::Float64 = 0.5
    @export_group("Visuals"; prefix = "visual_")
    @export_color_no_alpha visual_bg::Color = Color(0, 0, 0)
    @export_subgroup("Text")
    @export_multiline notes::String = ""
    @export_placeholder "Name..." title::String = ""
    @export_group("")
    @export_enum ("Small", "Large:5") size::Int = 0
    @export mode::Mode = Walk
    @export_flags ("Fire", "Water") elements::Int = 0
    @export_flags_2d_physics layers::Int = 1
    @export_file ("*.png", "*.jpg") image::String = ""
    @export_node_path (Sprite2D,) sprite_path::NodePath = NodePath("")
    @export target::Node2D
    @export items::GDArray{Int}
    @export lookup::GDDictionary{String, Int}
    @export_storage hidden::Int = 3
    @export_custom (Godot.PROPERTY_HINT_PASSWORD, "", Godot.PROPERTY_USAGE_DEFAULT) password::String = ""
    @export_tool_button ("Reset", "Reload") reset_button = reset!
    @export pm::Godot.Node_ProcessMode = Godot.Node_PROCESS_MODE_INHERIT
    @export msgs::Godot.Node_ProcessThreadMessages = Godot.Node_ProcessThreadMessages(0)
    scratch::Base.RefValue{Int} = Ref(0)
    @signal changed(old::Int, new::Int)
end
reset!(self::Exports) = nothing
@rpc :any_peer :call_local :unreliable_ordered channel = 1 function shoot(self::Exports, x::Int)
    return x
end
@rpc ping(self::Exports) = nothing
double_it(::Type{Exports}, x::Int) = 2x
end

@testset "Scripts" begin
    @testset "@godot_class metadata" begin
        Mover = ScriptTestA.Mover
        info = Runtime.script_info(Mover)
        C = info.instance_type
        @test isabstracttype(Mover) && Mover <: Godot.Node2D && C <: Mover && ismutabletype(C)
        @test info.native_base === :Node2D
        @test Godot.godot_class_name(Mover) === :Node2D && Godot.godot_class_name(C) === :Node2D
        @test fieldnames(C) == (:__ptr, :speed, :health, :target, :scratch)
        @test fieldtype(C, :target) == Union{Nothing, Godot.Node}
        @test !info.tool && !info.global_class && !info.is_abstract
        d = Runtime.all_defaults(info)
        @test d[1:3] == (300.0, 100, nothing) && d[4] isa Base.RefValue{Int}
        @test Runtime.all_defaults(info)[4] !== d[4]           # initializers run per instance
        obj = Runtime.construct_instance(info, Ptr{Cvoid}(1))
        @test obj.speed == 300.0 && obj.health == 100 && obj.target === nothing
        obj.health = 7
        @test obj.health == 7
        @test info.signals[1].name === :hit && info.signals[1].args == [:damage => Int, :source => Any]

        props = Runtime.script_props(info)
        @test [p.name for p in props] == [:speed, :health, :target]    # Julia-only types stay private
        @test props[1].usage == Runtime.USAGE_DEFAULT | Runtime.USAGE_SCRIPT_VARIABLE
        @test props[2].usage == Runtime.USAGE_SCRIPT_VARIABLE
        @test props[3].type == Godot.FFI.GDEXTENSION_VARIANT_TYPE_OBJECT && props[3].class_name === :Node &&
              props[3].hint == Runtime.HINT_NODE_TYPE
        @test Runtime.property_type(Vector{Float64})[1] == Godot.FFI.GDEXTENSION_VARIANT_TYPE_PACKED_FLOAT64_ARRAY
        @test Runtime.property_type(Any)[5] == Runtime.USAGE_NIL_IS_VARIANT

        @test Runtime.find_methods(info, :take_damage).f === ScriptTestA.take_damage
        @test Runtime.find_methods(info, :helper) === nothing          # untyped first argument: not a method
        @test Runtime.find_methods(info, :_ready).virtual
        @test Runtime.find_methods(info, :_process) === nothing        # unimplemented callbacks are not reported
        @test Runtime.find_methods(info, :free) === nothing            # Godot's own functions are not script methods
        m = Runtime.find_methods(info, :take_damage).methods[1]
        @test Runtime.arity(m) == 1 && Runtime.arg_types(m, 1) == Any[Int]
        @test :take_damage in Runtime.script_method_names(info)
        md = Runtime.method_dict(:take_damage, m)
        @test md["name"] == "take_damage" && md["args"][1]["name"] == "n" && md["args"][1]["type"] == 2

        tinfo = Runtime.script_info(ScriptTestA.ToolThing)
        @test tinfo.tool && tinfo.global_class && tinfo.icon == "res://icon.svg" && tinfo.native_base === :Resource
    end

    @testset "script inheritance" begin
        info = Runtime.script_info(ScriptTestB.Boss)
        @test info.base === Runtime.script_info(ScriptTestA.Mover)
        @test info.is_abstract && info.native_base === :Node2D
        @test fieldnames(info.instance_type) == (:__ptr, :speed, :health, :target, :scratch, :armor)
        obj = Runtime.construct_instance(info, Ptr{Cvoid}(1))
        @test obj.armor === 2.0f0 && obj.speed == 300.0
        @test obj isa ScriptTestA.Mover
        @test Runtime.find_methods(info, :take_damage).f === ScriptTestA.take_damage
        @test [p.name for p in Runtime.script_props(info)] == [:speed, :health, :target, :armor]
    end

    @testset "diagnostics" begin
        m = Module()
        Core.eval(m, :(using Godot))
        bad(src) = try
            Core.eval(m, Meta.parse(src))
            nothing
        catch e
            while e isa LoadError
                e = e.error
            end
            e
        end
        code(src) = (e = bad(src); e isa Runtime.ScriptDiagnostic ? e.code : e)
        @test code("@godot_class struct A1 <: Node end") == "GDJL0001"
        @test code("@godot_class mutable struct A2 end") == "GDJL0401"
        @test code("@godot_class mutable struct A3{T} <: Node end") == "GDJL0402"
        @test code("@godot_class mutable struct A4 <: Integer end") == "GDJL0401"
        @test code("@godot_class mutable struct A5 <: Node\n f(x) = 1\nend") == "GDJL0006"
        @test code("@godot_class mutable struct A6 <: Node\n @export x::Base.RefValue{Int} = Ref(1)\nend") == "GDJL0102"
        @test code("@godot_class mutable struct A7 <: Node\n x::Int = 1\n x::Int = 2\nend") == "GDJL0007"
        @test bad("@godot_class mutable struct A8 <: NotAType\nend") isa UndefVarError
        @test code("@godot_class weird mutable struct A9 <: Node\nend") == "GDJL0005"
        @test code("@godot_class mutable struct A10 <: Node\n @export_bogus x::Int = 1\nend") == "GDJL0005"
        @test code("@godot_class mutable struct A11 <: Node\n @export const x::Int = 1\nend") == "GDJL0103"
        @test code("@godot_class mutable struct A12 <: Node\n @export_range (0, 1) s::String = \"\"\nend") == "GDJL0106"
        @test code("@godot_class mutable struct A13 <: Node\n @export_range (0,) x::Int = 0\nend") == "GDJL0105"
        @test code("@godot_class mutable struct A14 <: Resource\n @export n::Node\nend") == "GDJL0107"
        @test code("@godot_class mutable struct A15 <: Node\n @export_tool_button (\"Go\",) go = f\nend") == "GDJL0108"
        @test code("@tool @godot_class mutable struct A16 <: Node\n @export_tool_button (\"Go\",) go = 1\nend") == "GDJL0110"
        @test code("@godot_class mutable struct A17 <: Node\n @signal s(x::Base.RefValue{Int})\nend") == "GDJL0202"
        @test code("@godot_class mutable struct A18 <: Node\n @export xs::GDArray{Base.RefValue{Int}}\nend") == "GDJL0301"
        @test code("@tool @godot_class mutable struct A19 <: Node\n @export @export_tool_button (\"Go\",) go = f\nend") == "GDJL0006"   # GD0109
        @test code("@godot_class mutable struct A20 <: Node\n @signal s(x::Int)::Int\nend") == "GDJL0006"   # GD0203
        @test code("@rpc f(x::Int) = 1") == "GDJL0501"
        @test code("@rpc :bogus f(self::Node) = 1") == "GDJL0501"
        @test sprint(showerror, Runtime.ScriptDiagnostic("GDJL0102", "msg")) == "GDJL0102: msg"
        # Every code raised by the implementation is documented.
        doc = read(joinpath(REPO_ROOT, "docs", "diagnostics.md"), String)
        srcdir = joinpath(pkgdir(Godot), "src")
        files = [joinpath(root, f) for (root, _, fs) in walkdir(srcdir) for f in fs
                 if endswith(f, ".jl") && !occursin("generated", root)]
        for c in unique(x.match for f in files for x in eachmatch(r"GDJL\d{4}", read(f, String)))
            @test occursin("| $c |", doc)
        end
        # Every C# source-generator diagnostic of Godot 4.7.2 is mapped or explained (parity audit, phase 17).
        for n in (1:3..., 101:111..., 201:203..., 301:303..., 401:402...)
            c = "GD" * lpad(n, 4, '0')
            @test occursin(Regex("\\b$c\\b"), doc)
        end
    end

    @testset "exports" begin
        info = Runtime.script_info(ScriptTestC.Exports)
        props = Dict(String(p.name) => p for p in Runtime.script_props(info))
        names = [String(p.name) for p in Runtime.script_props(info)]
        H(n) = Runtime.hint_value(n)
        U = Runtime.USAGE_DEFAULT | Runtime.USAGE_SCRIPT_VARIABLE
        @test names[1:5] == ["Movement", "speed", "health", "ratio", "Visuals"]
        @test props["Movement"].usage == Runtime.USAGE_CATEGORY
        @test props["speed"].usage == U && props["speed"].hint == 0
        @test props["health"].hint == H(:RANGE) && props["health"].hint_string == "0,100,1,or_greater"
        @test props["ratio"].hint_string == "0.0,1.0,0.05,suffix:m"
        @test props["Visuals"].usage == Runtime.USAGE_GROUP && props["Visuals"].hint_string == "visual_"
        @test props["visual_bg"].hint == H(:COLOR_NO_ALPHA)
        @test props["Text"].usage == Runtime.USAGE_SUBGROUP
        @test props["notes"].hint == H(:MULTILINE_TEXT) && props["title"].hint_string == "Name..."
        @test props["size"].hint == H(:ENUM) && props["size"].hint_string == "Small,Large:5"
        @test props["mode"].type == 2 && props["mode"].hint == H(:ENUM) && props["mode"].hint_string == "Walk:0,Run:1,Fly:2"
        @test props["elements"].hint == H(:FLAGS) && props["elements"].hint_string == "Fire,Water"
        @test props["layers"].hint == H(:LAYERS_2D_PHYSICS)
        @test props["image"].hint == H(:FILE) && props["image"].hint_string == "*.png,*.jpg"
        @test props["sprite_path"].hint == H(:NODE_PATH_VALID_TYPES) && props["sprite_path"].hint_string == "Sprite2D"
        @test props["target"].hint == Runtime.HINT_NODE_TYPE && props["target"].hint_string == "Node2D"
        @test props["items"].hint == H(:ARRAY_TYPE) && props["items"].hint_string == "2/0:"
        @test props["lookup"].hint == H(:DICTIONARY_TYPE) && props["lookup"].hint_string == "4/0:;2/0:"
        @test props["hidden"].usage == Runtime.USAGE_STORAGE | Runtime.USAGE_SCRIPT_VARIABLE
        @test props["password"].hint == H(:PASSWORD) && props["password"].usage == U
        @test props["reset_button"].type == Godot.FFI.GDEXTENSION_VARIANT_TYPE_CALLABLE &&
              props["reset_button"].hint == H(:TOOL_BUTTON) && props["reset_button"].hint_string == "Reset,Reload" &&
              props["reset_button"].usage == Runtime.USAGE_EDITOR
        @test !haskey(props, "scratch")
        @test props["pm"].hint == H(:ENUM) && occursin("PROCESS_MODE_INHERIT:0", props["pm"].hint_string)
        @test props["msgs"].hint == H(:FLAGS)

        @test SignalName(ScriptTestC.Exports) === (changed = :changed,)
        @test PropertyName(ScriptTestC.Exports).speed === :speed && PropertyName(ScriptTestC.Exports).reset_button === :reset_button
        @test hasmethod(ScriptTestC.emit_changed, Tuple{ScriptTestC.Exports, Int, Int})
        @test Runtime.find_methods(info, :emit_changed) === nothing          # generated helpers are not engine methods
        @test Runtime.find_methods(info, :shoot) !== nothing
        @test :double_it in keys(MethodName(ScriptTestC.Exports)) && :shoot in keys(MethodName(ScriptTestC.Exports))
        @test Runtime.static_methods(info, :double_it).f === ScriptTestC.double_it
        @test Runtime.static_methods(info, :shoot) === nothing
        @test info.rpc[:shoot] == Dict("rpc_mode" => 1, "call_local" => true, "transfer_mode" => 1, "channel" => 1)
        @test info.rpc[:ping] == Dict("rpc_mode" => 2, "call_local" => false, "transfer_mode" => 2, "channel" => 0)

        obj = Runtime.construct_instance(Runtime.script_info(ScriptTestA.Mover), Ptr{Cvoid}(1))
        obj.speed = 3              # Julia fields take precedence and convert like struct fields
        @test obj.speed === 3.0
    end

    @testset "parse-only queries" begin
        h = Runtime.parse_header("using Godot\n@tool @global_class @icon \"res://i.svg\" @godot_class mutable struct Foo <: Node\nend\n")
        @test h.name === :Foo && h.tool && h.global_class && h.icon == "res://i.svg" && Runtime.base_type_name(h.base) == "Node"
        @test Runtime.parse_header("x = 1") === nothing
        @test Runtime.parse_header("x = (") === nothing
        @test Runtime.matches_file(:PlayerController, "player_controller") && !Runtime.matches_file(:Player, "Enemy")

        ok = Runtime.language_validate(C_NULL, "using Godot\n@godot_class mutable struct V <: Node\nend\nf(self::V) = 1\n",
                                       "res://V.jl", true, true, true, true)
        @test ok["valid"] && "f:4" in ok["functions"]
        bad = Runtime.language_validate(C_NULL, "x = 1\ny = (1 +\n", "res://V.jl", true, true, true, true)
        @test !bad["valid"] && bad["errors"][1]["line"] >= 2
        lowered = Runtime.language_validate(C_NULL, "@godot_class struct V <: Node\nend\n", "res://V.jl", false, true, true, true)
        @test !lowered["valid"] && occursin("GDJL0001", lowered["errors"][1]["message"])

        try
            include_string(Module(), "x = 1\ny = (1 +\n z", "res://a.jl")
        catch e
            line, msg = Runtime.script_error_location("res://a.jl", e, catch_backtrace())
            @test line == 3 && startswith(msg, "syntax error")
        end
    end

    @testset "templates and editor helpers" begin
        src = Runtime.language_make_template(C_NULL, Runtime.NODE_TEMPLATE, "Player", "Node2D")
        @test occursin("mutable struct Player <: Node2D", src) && occursin("Godot._ready(self::Player)", src)
        @test occursin("script_type(\"res://base.jl\")", Runtime.language_make_template(C_NULL, "", "X", "res://base.jl"))
        @test Meta.parseall(src).head === :toplevel
        @test Runtime.language_get_built_in_templates(C_NULL, :Node)[1]["inherit"] == "Node"
        @test isempty(Runtime.language_get_built_in_templates(C_NULL, :Node2D))
        for (base, ts) in Runtime.BUILT_IN_TEMPLATES, t in ts
            s = Runtime.language_make_template(C_NULL, t["content"], "MyScript", String(base))
            @test Runtime.language_validate(C_NULL, s, "res://MyScript.jl", false, true, false, false)["valid"]
            @test !occursin("_CLASS_", s) && !occursin("_TS_", s)
            startswith(String(base), "Editor") && @test occursin("@tool", s) && occursin("<: Godot.Editor.$base", s)
        end
        @test length(unique(t["id"] for ts in values(Runtime.BUILT_IN_TEMPLATES) for t in ts)) == 7
        @test Runtime.template_base("Node2D") == "Node2D"
        @test Runtime.language_validate_path(C_NULL, "res://scenes/Player.jl") == ""
        @test Runtime.language_validate_path(C_NULL, "res://my player.jl") != ""
        @test Runtime.language_validate_path(C_NULL, "res://2fast.jl") != ""
        @test Runtime.language_overrides_external_editor(C_NULL) === false
        f = Runtime.language_make_function(C_NULL, "Player", "_on_hit", ["damage:int", "who"])
        @test f == "function _on_hit(self::Player, damage, who)\nend\n"
        @test Runtime.language_find_function(C_NULL, "_ready", src) == 7
        @test Runtime.language_find_function(C_NULL, "nope", src) == -1
    end
end
