# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# In-engine tests for Godot.FFI. parity: 1.7
using Test
using GodotTestRunner
using Godot.FFI: FFI, @sn_str

os_call(::Type{R}, method::Symbol, args...) where {R} = FFI.ptrcall(R, FFI.method_bind(:OS, method), FFI.singleton(:OS), args...)

static_memory() = os_call(Int64, :get_static_memory_usage)

function churn_strings(n)
    for i in 1:n
        s = FFI.new_string("leak check string number $i")
        FFI.destroy!(s)
        v = FFI.to_variant(Int64(i))
        FFI.destroy!(v)
    end
end

ticks_usec(mb, time) = FFI.ptrcall(Int64, mb, time)

function ticks_loop(mb, time, n)
    s = Int64(0)
    for _ in 1:n
        s += ticks_usec(mb, time)
    end
    return s
end

ts = @testset EngineTestSet "ffi" begin
    @testset "String round trips" begin
        for text in ("", "hello", "héllo wörld", "日本語テキスト", "emoji 🎮🚀", "tab\tnew\nline", repeat("x", 10_000))
            s = FFI.new_string(text)
            @test FFI.julia_string(s) == text
            copy = FFI.construct(FFI.RawString, s)
            @test FFI.julia_string(copy) == text
            FFI.destroy!(copy)
            FFI.destroy!(s)
        end
        @test FFI.julia_string(FFI.construct(FFI.RawString)) == ""
    end

    @testset "StringName and NodePath" begin
        sn = FFI.new_string_name("player_health")
        @test FFI.julia_string(sn) == "player_health"
        FFI.destroy!(sn)
        np = FFI.new_node_path("Root/Child:position")
        @test FFI.julia_string(np) == "Root/Child:position"
        FFI.destroy!(np)
        @test FFI.string_name_ptr(:cached_name) == FFI.string_name_ptr(:cached_name)
        get_sn() = sn"literal_name"
        @test FFI.julia_string(get_sn()) == "literal_name"
        @test get_sn() === get_sn()
    end

    @testset "Variant" begin
        nil = FFI.construct(FFI.RawVariant)
        @test FFI.variant_type(nil) == FFI.GDEXTENSION_VARIANT_TYPE_NIL
        FFI.destroy!(nil)
        for x in (Int64(-42), 3.25, true)
            v = FFI.to_variant(x)
            @test FFI.variant_type(v) == FFI.variant_type(typeof(x))
            @test FFI.from_variant(typeof(x), v) === x
            v2 = FFI.construct(FFI.RawVariant, v)
            @test FFI.from_variant(typeof(x), v2) === x
            FFI.destroy!(v2)
            FFI.destroy!(v)
        end
        s = FFI.new_string("in a variant")
        v = FFI.to_variant(s)
        FFI.destroy!(s)
        @test FFI.variant_type(v) == FFI.GDEXTENSION_VARIANT_TYPE_STRING
        back = FFI.from_variant(FFI.RawString, v)
        @test FFI.julia_string(back) == "in a variant"
        @test_throws ArgumentError FFI.from_variant(Int64, v)
        FFI.destroy!(back)
        FFI.destroy!(v)
    end

    @testset "no leaks" begin
        churn_strings(1_000)
        before = static_memory()
        churn_strings(100_000)
        @test static_memory() - before < 64 * 1024
    end

    @testset "ptrcall" begin
        expected = Sys.iswindows() ? "Windows" : Sys.isapple() ? "macOS" : "Linux"
        name = os_call(FFI.RawString, :get_name)
        @test FFI.julia_string(name) == expected
        FFI.destroy!(name)

        feature = FFI.new_string("pc")
        @test os_call(Bool, :has_feature, feature) == true
        FFI.destroy!(feature)
        feature = FFI.new_string("no_such_feature_tag")
        @test os_call(Bool, :has_feature, feature) == false
        FFI.destroy!(feature)

        @test os_call(Int64, :get_processor_count) == Sys.CPU_THREADS
    end

    @testset "builtin methods and utility functions" begin
        s = FFI.new_string("héllo")
        len = FFI.builtin_method(FFI.GDEXTENSION_VARIANT_TYPE_STRING, :length, FFI.builtin_method_hash(:String, :length))
        r = Ref(s)
        @test GC.@preserve(r, FFI.builtin_ptrcall(Int64, len, Base.unsafe_convert(Ptr{Cvoid}, r))) == 5
        FFI.destroy!(s)
        @test FFI.utility_ptrcall(Float64, FFI.utility_function(:sin), 0.5) ≈ sin(0.5)
    end

    @testset "Variant call path" begin
        feature = FFI.new_string("pc")
        arg = FFI.to_variant(feature)
        FFI.destroy!(feature)
        result = FFI.variant_call(FFI.method_bind(:OS, :has_feature), FFI.singleton(:OS), [arg])
        @test FFI.from_variant(Bool, result) == true
        FFI.destroy!(result)
        @test_throws FFI.GodotCallError FFI.variant_call(FFI.method_bind(:OS, :has_feature), FFI.singleton(:OS), FFI.RawVariant[])
        FFI.destroy!(arg)
    end

    @testset "zero-allocation ptrcall benchmark" begin
        mb = FFI.method_bind(:Time, :get_ticks_usec)
        time = FFI.singleton(:Time)
        ticks_loop(mb, time, 10)
        allocated = @allocated ticks_loop(mb, time, 1_000_000)
        elapsed = @elapsed ticks_loop(mb, time, 1_000_000)
        println("ptrcall Time.get_ticks_usec: ", round(elapsed * 1000; digits = 1), " ns/call over 1M calls, ", allocated, " bytes allocated")
        @test allocated == 0
    end

    @testset "error reporting" begin
        FFI.godot_warning("ffi warning from julia", LineNumberNode(12, Symbol("test_ffi.jl")))
        @test true
    end
end

report(ts)
