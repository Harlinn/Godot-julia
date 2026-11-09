# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# In-engine tests for Variant, strings, collections, packed arrays and Callables. parity: 3.4–3.10, 3.12, 3.13
using Test
using GodotTestRunner
using Godot
using Godot: Runtime, Internals

roundtrip(helper, x) = Godot.call(helper, :id, x)
memory() = get_static_memory_usage(OS)

struct Adder
    k::Int
end
(a::Adder)(x) = x + a.k

function collect_garbage()
    for _ in 1:3
        GC.gc()
        Internals.flush_releases!()
    end
end

# A closure Callable connected to a signal, emitted from GDScript, then disconnected.
function signal_roundtrip(helper)
    received = Ref{Any}(nothing)
    handler = Callable(v -> (received[] = v; nothing))
    alive = Runtime.pin_count()
    connect(helper, :ping, handler) == OK || error("connect failed")
    Godot.call(helper, :emit_ping, "hello")
    disconnect(helper, :ping, handler)
    return received[], alive
end

ts = @testset EngineTestSet "variant" begin
    helper = Node()
    set_script(helper, GD.load("res://helper.gd"))

    @testset "round trip through GDScript" begin
        values = Any[nothing, true, false, 42, -7, 3.5, "héllo ✓ 世界", :sym, NodePath("A/B:prop"), RID(),
                     Vector2(1, 2), Vector2i(3, 4), Rect2(1, 2, 3, 4), Rect2i(1, 2, 3, 4), Vector3(1, 2, 3),
                     Vector3i(1, 2, 3), Transform2D(0.5, Vector2(1, 2)), Vector4(1, 2, 3, 4), Vector4i(1, 2, 3, 4),
                     Plane(0, 1, 0, 2), Quaternion(0, 0, 0, 1), AABB(Vector3(1, 2, 3), Vector3(4, 5, 6)),
                     from_euler(Basis, Vector3(0.1, 0.2, 0.3)), Transform3D(Basis(), Vector3(1, 2, 3)),
                     create_perspective(Projection, 70, 1.5, 0.1, 50), Color(0.1, 0.2, 0.3, 0.4)]
        for x in values
            back = roundtrip(helper, x)
            @test typeof(back) == typeof(x)
            @test back == x
        end
        @test roundtrip(helper, Int32(5)) === 5
        @test roundtrip(helper, 1.5f0) === 1.5
        @test roundtrip(helper, helper) == helper
        a = GDArray([1, "two", 3.0])
        a2 = roundtrip(helper, a)
        @test a2 == a
        push!(a2, :four)
        @test length(a) == 4                       # reference semantics: the same Array
        d = GDDictionary("k" => 1)
        d2 = roundtrip(helper, d)
        d2["j"] = 2
        @test d["j"] == 2
        for P in Godot.PACKED_TYPES
            T = eltype(P)
            items = T === String ? ["a", "b"] : T === UInt8 ? UInt8[1, 2] : T <: Number ? T[1, 2] :
                    T === Color ? [Color(1, 0, 0), Color()] : [one(T), zero(T)]
            p = roundtrip(helper, P(items))
            @test p isa P && collect(p) == items
        end
        @test roundtrip(helper, Float32[1, 2, 3]) isa PackedFloat32Array   # Vector{T} marshals like C#'s T[]
        @test roundtrip(helper, Int64[1, 2]) isa PackedInt64Array
        @test roundtrip(helper, Any[1, "x"]) isa GDArray{Any}
        @test roundtrip(helper, Dict("a" => 1)) isa GDDictionary
        c = Callable(helper, :id)
        @test roundtrip(helper, c) == c
        s = Signal(helper, :ping)
        @test roundtrip(helper, s) == s
    end

    @testset "Variant" begin
        v = Variant(42)
        @test variant_type(v) == TYPE_INT
        @test convert(Int, v) === 42 && Int32(v) === Int32(42) && Float64(v) === 42.0
        @test v[] === 42
        @test_throws VariantConversionError String(v)
        @test_throws InexactError Int8(Variant(1000))
        @test variant_type(Variant()) == TYPE_NIL && isnothing(Variant(nothing))
        @test Vector2(Variant(Vector2(1, 2))) == Vector2(1, 2)
        @test String(Variant(:abc)) == "abc" && Symbol(Variant("abc")) === :abc
        @test NodePath(Variant("A/B")) == NodePath("A/B")
        @test Variant(1) == Variant(1) && Variant(1) != Variant(2)
        @test string(Variant(Vector2(1, 2))) == "(1.0, 2.0)"
        @test convert(Union{Nothing, Node}, Variant(helper)) == helper
        @test Node(Variant(helper)) == helper
        @test_throws ArgumentError Node2D(Variant(helper))
        @test convert(Vector{Float32}, Variant(Float32[1, 2])) == Float32[1, 2]
        @test convert(Vector{Int}, Variant(GDArray([1, 2]))) == [1, 2]
        @test convert(Dict{String, Int}, Variant(Dict("a" => 1))) == Dict("a" => 1)
        @test Variant(Variant(3))[] === 3
        @test Godot.from_variant(Int, Base.unsafe_convert(Ptr{Godot.FFI.RawVariant}, Ref(v.raw))) === 42
        @test isvarianttype(Int) && isvarianttype(Node) && isvarianttype(Vector{Float32}) && !isvarianttype(Dict{Int, Int})
    end

    @testset "strings, StringName, NodePath, RID" begin
        @test StringName("x") === :x
        @test capitalize("hello_world") == "Hello World"
        @test to_snake_case("HelloWorld") == "hello_world"
        @test begins_with("Godot", "Go") && begins_with(:Godot, "Go")
        @test md5_text("abc") == "900150983cd24fb0d6963f7d28e17f72"
        @test glob_match("player.jl", "*.jl") && glob_match(:Player, "P?ayer") && !glob_match("Player.jl", "p*")
        @test matchn("Player.jl", "p*")
        @test num(String, 3.14159, 2) == "3.14"
        @test get_slice("a,b,c", ",", 1) == "b"
        p = NodePath("Path/To/Node:property:sub")
        @test get_name_count(p) == 3 && get_name(p, 1) === :To && get_subname_count(p) == 2
        @test !is_absolute(p) && is_absolute(NodePath("/root"))
        @test convert(NodePath, "A") == NodePath("A")
        @test !is_valid(RID()) && get_id(RID()) == 0
        r = get_rid(Resource())
        @test r isa RID
    end

    @testset "GDArray" begin
        a = GDArray()
        push!(a, 1); push!(a, "two"); pushfirst!(a, 0.5)
        @test collect(a) == Any[0.5, 1, "two"]
        @test pop!(a) == "two" && popfirst!(a) == 0.5 && length(a) == 1
        insert!(a, 1, :x); append!(a, [2, 3])
        @test collect(a) == Any[:x, 1, 2, 3]
        deleteat!(a, 2)
        @test collect(a) == Any[:x, 2, 3]
        a[1] = "y"
        @test a[1] == "y" && a[end] == 3
        b = copy(a)
        b[1] = "changed"
        @test a[1] == "y"
        nested = GDArray([GDArray([1])])
        deep = deepcopy(nested)
        push!(deep[1], 2)
        @test length(nested[1]) == 1
        Godot.call(helper, :append_from_gdscript, a)
        @test a[end] == "from gdscript"
        make_read_only(a)
        @test is_read_only(a)
        @test_throws ArgumentError push!(a, 1)
        @test_throws ArgumentError (a[1] = 2)
        empty!(b)
        @test isempty(b)
        @test GDArray([1, 2]) == GDArray([1, 2])
        @test recursive_equal(GDArray([GDArray([1]), "a"]), GDArray([GDArray([1]), "a"]))
        @test !recursive_equal(GDArray([GDArray([1])]), GDArray([GDArray([2])]))
        @test sum(GDArray([1, 2, 3])) == 6
    end

    @testset "typed arrays" begin
        t = GDArray{Int64}([1, 2])
        @test eltype(t) === Int64 && t[2] === 2
        @test is_typed(t) && get_typed_builtin(t) == Int(TYPE_INT)
        @test_throws MethodError push!(t, "x")
        @test_throws InexactError push!(t, 1.5)
        ints = Godot.call(helper, :typed_ints)
        @test ints isa GDArray{Int64} && collect(ints) == [1, 2, 3]
        nodes = Godot.call(helper, :typed_nodes)
        @test nodes isa GDArray{Node} && nodes[1] == helper
        @test get_typed_class_name(GDArray{Node}()) === :Node
        @test_throws ArgumentError convert(GDArray{String}, Variant(ints))
        kids = get_children(helper)
        @test kids isa GDArray{Node}
        @test_throws ArgumentError push!(GDArray{Node2D}(), helper)
    end

    @testset "GDDictionary" begin
        d = GDDictionary()
        d["a"] = 1
        d[:b] = [1, 2]
        d[3] = nothing
        @test length(d) == 3 && haskey(d, "a") && !haskey(d, "zz")
        @test d["a"] == 1 && d[3] === nothing && get(d, "zz", :dflt) === :dflt
        @test_throws KeyError d["zz"]
        @test Set(keys(d)) == Set(Any["a", :b, 3])
        delete!(d, 3)
        @test length(d) == 2
        @test Dict(d)["a"] == 1
        @test pop!(d, "a") == 1 && !haskey(d, "a")
        merge!(d, Dict("x" => 10))
        @test d["x"] == 10
        c = copy(d)
        c["new"] = 1
        @test !haskey(d, "new")
        typed = GDDictionary{String, Int64}("one" => 1)
        @test typed["one"] === 1 && eltype(typed) == Pair{String, Int64}
        @test_throws MethodError (typed[1] = 2)
        gd = Godot.call(helper, :typed_dict)
        @test gd isa GDDictionary{String, Int64} && gd["b"] == 2
        @test collect(GDDictionary("k" => "v")) == ["k" => "v"]
    end

    @testset "packed arrays" begin
        p = PackedFloat32Array(Float32[1, 2, 3])
        push!(p, 4)
        @test collect(p) == Float32[1, 2, 3, 4] && Vector(p) isa Vector{Float32}
        q = copy(p)
        v = unsafe_wrap(Array, p)
        GC.@preserve p begin
            v[1] = 100
        end
        @test p[1] == 100 && q[1] == 1             # copy-on-write: the view made p's buffer unique
        resize!(p, 2)
        @test length(p) == 2
        insert!(p, 1, 7); deleteat!(p, 2)
        @test collect(p) == Float32[7, 2]
        s = PackedStringArray(["a", "β"])
        push!(s, "c")
        @test collect(s) == ["a", "β", "c"] && pop!(s) == "c"
        bytes = to_utf8_buffer("hé")
        @test bytes isa PackedByteArray && collect(bytes) == codeunits("hé")
        @test get_string_from_utf8(bytes) == "hé"
        @test has(PackedInt32Array(Int32[1, 2]), 2)
    end

    @testset "Callable" begin
        c = Callable(helper, :id)
        @test c(7) == 7 && call(c, "x") == "x"
        @test get_method(c) === :id && get_object(c) == helper
        hits = Ref(0)
        f = x -> (hits[] += x; x * 2)
        jc = Callable(f)
        @test jc(3) == 6 && hits[] == 3
        @test Godot.call(helper, :call_it, jc, 4) == 8 && hits[] == 7     # invoked from GDScript
        @test get_argument_count(jc) == 1 && is_custom(jc) && is_valid(jc)
        @test Callable(f) == Callable(f)
        @test Callable(Adder(10))(5) == 15
        @test call(Godot.bind(Callable((a, b) -> a - b), 1), 10) == 9
        jc = nothing
        collect_garbage()
        pins = Runtime.pin_count()
        received, alive_after_connect = signal_roundtrip(helper)
        @test received == "hello" && alive_after_connect == pins + 1
        collect_garbage()
        @test Runtime.pin_count() == pins            # the closure was released after the last Godot reference
    end

    @testset "no leaks: 1M Variants and Arrays" begin
        GC.gc(); Internals.flush_releases!()
        before = memory()
        for batch in 1:10
            for i in 1:100_000
                Variant(i)
                Variant("s")
                GDArray{Any}(Godot.FFI.construct(Godot.FFI.RawArray))
            end
            GC.gc(false)
            Internals.flush_releases!()
        end
        GC.gc(); Internals.flush_releases!()
        @test memory() - before < 1_000_000
    end

    free(helper)
end

GC.gc()
Godot.Internals.flush_releases!()
report(ts)
