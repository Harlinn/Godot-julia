# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot.Runtime: Runtime

# Export builds (ADR 0014): scripts compiled ahead of time and loaded by path without their sources. parity: 10.1, 10.8
const EXPORT_SOURCES = Dict(
    "res://Base1.jl" => """
    using Godot
    @global_class @godot_class mutable struct Base1 <: Node
        hp::Int = 10
    end
    hurt!(self::Base1, n::Int) = (self.hp -= n; self.hp)
    """,
    "res://sub/Derived1.jl" => """
    using Godot
    @godot_class mutable struct Derived1 <: Base1
        armor::Int = 2
    end
    const IS_WIN = Godot.@feature(:windows)
    const IS_EDITOR = Godot.@feature(:editor)
    Godot._process(self::Derived1, delta::Float64) = nothing
    """,
    "res://Uses.jl" => """
    using Godot
    const D = Godot.script_type("res://sub/Derived1.jl")
    @godot_class mutable struct Uses <: Node
        other::Any = nothing
    end
    """,
    "res://Broken1.jl" => """
    using Godot
    const X = Godot.get_process_frames(Godot.Engine)
    @godot_class mutable struct Broken1 <: Node
    end
    """,
    "res://Misnamed.jl" => """
    using Godot
    @godot_class mutable struct Other <: Node
    end
    """,
)

@testset "Export" begin
    @testset "precompile_scripts!" begin
        empty!(Runtime.PRECOMPILED_SCRIPTS)
        failed = Runtime.precompile_scripts!(EXPORT_SOURCES, Dict("Base1" => "res://Base1.jl"), ["windows", "pc", "debug"])
        @test Runtime.EXPORT_BUILD[] === nothing
        @test sort(collect(keys(failed))) == ["res://Broken1.jl", "res://Misnamed.jl"]
        @test occursin("GDJL0004", failed["res://Misnamed.jl"])
        P = Runtime.PRECOMPILED_SCRIPTS
        @test sort(collect(keys(P))) == ["res://Base1.jl", "res://Uses.jl", "res://sub/Derived1.jl"]
        d = P["res://sub/Derived1.jl"]
        @test d.info.name === :Derived1 && d.info.base === P["res://Base1.jl"].info
        @test d.deps == ["res://Base1.jl"]                       # global class resolved by name at build time
        @test P["res://Uses.jl"].deps == ["res://sub/Derived1.jl"]
        @test getglobal(d.mod, :IS_WIN) === true && getglobal(d.mod, :IS_EDITOR) === false   # compile-time features
        obj = Runtime.construct_instance(d.info, Ptr{Cvoid}(1))
        @test obj.hp == 10 && obj.armor == 2
        @test getglobal(P["res://Base1.jl"].mod, :hurt!)(obj, 3) == 7
        # The methods are compiled for the concrete instance types.
        C = d.info.instance_type
        @test any(mi -> mi.specTypes == Tuple{typeof(Godot._process), C, Float64}, Base.specializations(only(methods(Godot._process, Tuple{C, Float64}))))
        @test Runtime.is_precompiled(d.mod)
    end

    @testset "loading precompiled scripts" begin
        st = Runtime.ScriptState(Ptr{Cvoid}(UInt(0x1234)))
        st.path = "res://Base1.jl"
        @test Runtime.load_script!(st, "") == Runtime.ERR_OK      # an empty stub: no source is evaluated
        pre = Runtime.PRECOMPILED_SCRIPTS["res://Base1.jl"]
        @test st.valid && st.info === pre.info && st.mod === pre.mod && pre.info.state === st
        pre.info.state = nothing
    end

    @testset "sources of scripts not compiled in" begin
        mktempdir() do dir
            mkpath(joinpath(dir, "scripts", "sub"))
            write(joinpath(dir, "scripts", "sub", "Late.jl"), "x")
            @test Runtime.exported_source("res://sub/Late.jl") === nothing   # not an exported game
            Runtime.EXPORT_DIR[] = dir
            try
                @test Runtime.is_exported()
                @test Runtime.exported_source("res://sub/Late.jl") == "x"
                @test Runtime.exported_source("res://Missing.jl") === nothing
            finally
                Runtime.EXPORT_DIR[] = ""
            end
        end
        empty!(Runtime.PRECOMPILED_SCRIPTS)
    end

    @testset "@feature outside export builds" begin
        @test @macroexpand(Godot.@feature(:windows)) == :($(GlobalRef(Godot, :has_feature))("windows"))
        @test_throws Exception @macroexpand(Godot.@feature(1 + 1))
    end
end
