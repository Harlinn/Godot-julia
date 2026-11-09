# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# In-engine tests for object identity, lifetime, casting and dynamic access. parity: 3.14, 4.1, 4.2, 4.4–4.8
using Test
using GodotTestRunner
using Godot
using Godot: Runtime, Internals

function collect_garbage()
    for _ in 1:3
        GC.gc()
        Internals.flush_releases!()
    end
end

# Stand-in for a user script struct (phase 09 generates these): a Julia type deriving from an engine class.
mutable struct ScriptedNode <: Godot.Node2D
    __ptr::Ptr{Cvoid}
    score::Int
end

# A Resource held only by Julia, carrying a Callable whose closure references Julia state.
function make_chain(state::Ref{Int})
    r = Resource()
    set_meta(r, :callback, Callable(() -> (state[] += 1)))
    return weakref(r)
end

function engine_held_resource(helper)
    r = Resource()
    r.resource_name = "held"
    Godot.call(helper, :keep, r)
    return objectid(r), weakref(r)
end

# Allocate in a separate frame so no temporary keeps the wrapper rooted in the caller.
@noinline function julia_only_resource()
    r = Resource()
    return get_reference_count(r), weakref(r)
end

@noinline function check_kept(helper, oid)
    back = get_meta(helper, :kept)
    return objectid(back) == oid, back.resource_name, get_reference_count(back)
end

ts = @testset EngineTestSet "objects" begin
    helper = Node()
    set_script(helper, GD.load("res://helper.gd"))

    @testset "identity" begin
        root = Node()
        a = Node2D()
        set_name(a, "A")
        add_child(root, a)
        @test get_node(root, "A") === get_node(root, "A") === a
        @test get_parent(a) === root
        @test get_children(root)[1] === a
        @test Godot.Native.Node2D === typeof(get_node(root, "A"))
        id = get_instance_id(a)
        a = nothing
        collect_garbage()
        again = get_node(root, "A")                 # weakly held wrapper was collected; a new one is created
        @test get_instance_id(again) == id && again === get_child(root, 0)
        @test singleton(Engine) === get_singleton(Engine, :Engine)
        free(root)
    end

    @testset "freed objects" begin
        n = Node()
        free(n)
        @test !is_instance_valid(n)
        @test_throws FreedObjectError get_name(n)
        parent = Node()
        child = Node()
        add_child(parent, child)
        free(parent)                                 # the engine frees the child
        @test !is_instance_valid(child)
        @test_throws FreedObjectError get_name(child)
        victim = Node()
        Godot.call(helper, :free_it, victim)         # freed by GDScript
        @test !is_instance_valid(victim)
        @test sprint(show, victim) == "Node(<freed>)"
        @test !is_instance_valid(nothing)
    end

    @testset "RefCounted lifetime" begin
        collect_garbage()
        bound = Godot.binding_count()
        rc, wr = julia_only_resource()
        @test rc == 1
        collect_garbage()
        @test get_ref(wr) === nothing               # only Julia referenced it: collected and freed
        @test Godot.binding_count() == bound + 1    # only the WeakRef object itself remains bound

        # Engine-held: the binding keeps the wrapper alive while the engine references the object.
        oid, wr2 = engine_held_resource(helper)
        collect_garbage()
        @test check_kept(helper, oid) == (true, "held", 2)
        Godot.call(helper, :drop)                   # engine releases; only the (weak) Julia wrapper remains
        collect_garbage()
        @test get_ref(wr2) === nothing

        # Chain Julia -> Resource -> Julia closure is released once Julia drops the Resource.
        collect_garbage()
        pins = Runtime.pin_count()
        state = Ref(0)
        wr3 = make_chain(state)
        @test Runtime.pin_count() == pins + 1
        collect_garbage()
        @test get_ref(wr3) === nothing && Runtime.pin_count() == pins

        # Dispose (finalize) releases the Julia side; the engine-held object stays valid.
        r = Resource()
        a = GDArray([r])
        finalize(r)
        @test !is_instance_valid(r)
        collect_garbage()
        r2 = a[1]
        @test is_instance_valid(r2) && r2 !== r && get_reference_count(r2) == 2
    end

    @testset "casting" begin
        root = Node()
        s = Sprite2D()
        set_name(s, "S")
        add_child(root, s)
        @test convert(Node2D, s) === s
        @test_throws TypeError convert(Node2D, root)
        @test as(Node2D, root) === nothing && as(Sprite2D, s) === s && as(Node, nothing) === nothing
        @test get_node(Sprite2D, root, "S") === s
        @test get_node(Node2D, root, NodePath("S")) === s
        @test_throws TypeError get_node(Camera2D, root, "S")
        @test_throws ArgumentError get_node(Node, root, "Missing")
        @test get_node_or_null(Node2D, root, "Missing") === nothing
        @test get_node_or_null(Camera2D, root, "S") === nothing
        # Typed child/parent/owner lookups (C#'s GetChild<T>, GetParentOrNull<T>, ...).
        @test get_child(Sprite2D, root, 0) === s && get_child(Node2D, root, -1) === s
        @test_throws TypeError get_child(Camera2D, root, 0)
        @test get_child_or_null(Sprite2D, root, 0) === s && get_child_or_null(Sprite2D, root, 1) === nothing
        @test get_child_or_null(Camera2D, root, 0) === nothing
        @test get_parent(Node, s) === root && get_parent_or_null(Node2D, s) === nothing
        @test_throws ArgumentError get_parent(Node, root)
        @test get_owner_or_null(Node, s) === nothing
        @test_throws ArgumentError get_owner(Node, s)
        set_owner(s, root)
        @test get_owner(Node, s) === root && get_owner_or_null(Node, s) === root
        # Typed scene instantiation (C#'s PackedScene.Instantiate<T> / InstantiateOrNull<T>).
        scene = PackedScene()
        pack(scene, root)
        inst = instantiate(Node, scene)
        @test inst isa Node && get_child_count(inst) == 1 && get_child(Sprite2D, inst, 0) isa Sprite2D
        free(inst)
        @test_throws ArgumentError instantiate(Node2D, scene)
        @test instantiate_or_null(Node2D, scene) === nothing
        w = weakref(s)
        @test get_ref(w) === s
        free(root)
        @test get_ref(w) === nothing
    end

    @testset "dynamic access to script members" begin
        @test helper.score == 5
        helper.score = 7
        @test get(helper, :score) == 7
        @test Godot.call(helper, :add, 1) == 8
        @test has_method(helper, :add) && !has_method(helper, :nope)
        set!(helper, :score, 9)
        @test helper.score == 9
        @test has_property(helper, :score) && !has_property(helper, :nope)
        @test_throws ArgumentError helper.nope
        @test_throws ArgumentError (helper.nope = 1)
    end

    @testset "script structs as the object's wrapper" begin
        n = Node2D()
        child = Node()
        add_child(n, child)
        w = ScriptedNode(Internals.native_ptr(n), 3)
        Godot.bind_wrapper!(Internals.native_ptr(n), w)
        @test get_parent(child) === w                # the engine returns the Julia struct
        @test !is_instance_valid(n)                  # the previous wrapper was retired
        @test w isa Node2D && w.score == 3
        w.position = Vector2(1, 2)
        @test w.position == Vector2(1, 2)
        free(w)
        @test !is_instance_valid(w)
    end

    @testset "threads" begin
        @test Threads.nthreads() == 4
        shared = [Resource() for _ in 1:8]
        ptrs = [Internals.native_ptr(r) for r in shared]
        done = Threads.Atomic{Int}(0)
        tasks = map(1:4) do t
            Threads.@spawn begin
                for i in 1:2000
                    k = mod1(i + t, 8)
                    Godot.wrap_object(ptrs[k], false) === shared[k] || return
                    tmp = RefCounted()                # created and dropped concurrently
                    get_reference_count(tmp) == 1 || return
                end
                Threads.atomic_add!(done, 1)
            end
        end
        foreach(wait, tasks)
        @test done[] == 4
        collect_garbage()
        @test all(r -> get_reference_count(r) == 1, shared)
    end

    free(helper)
end

collect_garbage()
report(ts)
