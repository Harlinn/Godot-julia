# In-engine tests for the generated class bindings. parity: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.9, 2.10, 2.11, 2.12
using Test
using GodotTestRunner
using Godot

child_count(n) = get_child_count(n)
position_of(n) = n.position

ts = @testset EngineTestSet "bindings" begin
    @testset "construction, properties, methods" begin
        n = Node2D()
        @test n isa Node2D
        @test n isa CanvasItem
        @test n isa GodotObject
        n.position = Vector2(3, 4)
        @test n.position == Vector2(3, 4)
        @test get_position(n) == Vector2(3, 4)
        set_position(n, Vector2(-1.5, 2))
        @test n.position == Vector2(-1.5, 2)
        @test :position in propertynames(n)
        @test :process_mode in propertynames(n)

        set_name(n, "Player")
        @test get_name(n) === :Player
        @test n.name === :Player

        c = Node()
        add_child(n, c)
        @test get_child_count(n) == 1
        @test get_child(n, 0) == c
        @test get_parent(c) isa Node2D
        @test get_parent(c) == n
        kids = get_children(n)
        @test length(kids) == 1
        @test kids[1] == c
        @test get_node_or_null(n, NodePath("Missing")) === nothing

        child_count(n)
        @test (@allocated child_count(n)) == 0
        position_of(n)
        @test (@allocated position_of(n)) == 0

        remove_child(n, c)
        free(c)
        @test_throws Godot.Internals.FreedObjectError get_name(c)
        free(n)
    end

    @testset "enums, bitfields and constants" begin
        n = Node()
        @test get_process_mode(n) == Node_PROCESS_MODE_INHERIT
        n.process_mode = Node_PROCESS_MODE_ALWAYS
        @test n.process_mode == Node_PROCESS_MODE_ALWAYS
        set_process_mode(n, 1)
        @test get_process_mode(n) == Node_PROCESS_MODE_PAUSABLE
        @test repr(Node_PROCESS_MODE_PAUSABLE) == "Node_PROCESS_MODE_PAUSABLE"
        @test Node_NOTIFICATION_READY == 13
        flags = GodotObject_CONNECT_DEFERRED | GodotObject_CONNECT_ONE_SHOT
        @test GodotObject_CONNECT_ONE_SHOT in flags
        @test KEY_A isa Key
        @test OK == Error(0)
        @test Vector2_AXIS_Y == Vector2_Axis(1)
        free(n)
    end

    @testset "singletons and static methods" begin
        info = get_version_info(Engine)
        @test info isa GDDictionary
        @test info["major"] == 4
        @test info["minor"] == 7
        @test haskey(info, "string")
        @test singleton(Engine).time_scale ≈ 1.0
        @test get_name(OS) == (Sys.iswindows() ? "Windows" : Sys.isapple() ? "macOS" : "Linux")
        @test file_exists(FileAccess, "res://project.godot")
        @test !file_exists(FileAccess, "res://no_such_file.txt")
        args = get_cmdline_args(OS)
        @test args isa PackedStringArray
        @test all(a -> a isa String, collect(args))
    end

    @testset "RefCounted lifetime" begin
        r = Resource()
        @test get_reference_count(r) == 1
        r.resource_name = "shared"
        a = GDArray([r, 1, "two"])
        @test get_reference_count(r) == 2
        back = a[1]
        @test back === r                            # same wrapper (instance binding): no extra reference
        @test get_reference_count(r) == 2
        @test back.resource_name == "shared"
        @test a[2] == 1 && a[3] == "two"
    end

    @testset "containers" begin
        line = Line2D()
        set_points(line, [Vector2(0, 0), Vector2(1, 1), Vector2(2, 0)])
        @test get_point_count(line) == 3
        pts = get_points(line)
        @test pts isa PackedVector2Array
        @test pts[2] == Vector2(1, 1)
        @test collect(pts) == [Vector2(0, 0), Vector2(1, 1), Vector2(2, 0)]
        free(line)
        d = GDDictionary(Dict("a" => 1, "b" => [1, 2]))
        @test d["a"] == 1
        @test collect(d["b"]) == [1, 2]
    end

    @testset "Variant calls and varargs" begin
        n = Node()
        set_name(n, "Caller")
        @test call(n, :get_name) === :Caller
        call(n, "set_name", "Renamed")
        @test get_name(n) === :Renamed
        @test get(n, :name) === :Renamed
        free(n)
    end

    @testset "utility functions (GD)" begin
        @test GD.sin(0.5) ≈ sin(0.5)
        @test GD.max(1, 5, 3) == 5
        @test GD.str(1, "a", :b) == "1ab"
        @test GD.type_string(4) == "String"
        GD.print("hello from GD.print")
        @test true
        scene = GD.load(PackedScene, "res://main.tscn")
        @test scene isa PackedScene
        @test can_instantiate(scene)
        @test_throws ArgumentError GD.load(Texture2D, "res://main.tscn")
    end

    @testset "builtin math through the engine" begin
        n2 = Node2D()
        t2 = Transform2D(0.5, Vector2(2, 1.5), 0.2, Vector2(3, -1))
        n2.transform = t2
        @test n2.transform ≈ t2
        @test n2.rotation ≈ 0.5 && n2.scale ≈ get_scale(t2) && n2.skew ≈ get_skew(t2)
        n3 = Node3D()
        t3 = Transform3D(from_euler(Basis, Vector3(0.3, -0.5, 1.1)), Vector3(4, -2, 1))
        n3.transform = t3
        @test n3.transform ≈ t3
        @test n3.basis ≈ t3.basis
        @test n3.rotation ≈ get_euler(t3.basis)
        @test n3.quaternion ≈ get_rotation_quaternion(t3.basis)
        free(n2)
        free(n3)
        # Memory layout and text form agree with the engine (Basis is stored as rows).
        b = Basis(Vector3(1, 2, 3), Vector3(0, 1, 4), Vector3(5, 6, 0))
        @test GD.var_to_str(b) == "Basis(1, 0, 5, 2, 1, 6, 3, 4, 0)"
        @test GD.str_to_var("Basis(1, 0, 5, 2, 1, 6, 3, 4, 0)") == b
        @test GD.str_to_var(GD.var_to_str(create_perspective(Projection, 70, 1.5, 0.1, 50))) ≈ create_perspective(Projection, 70, 1.5, 0.1, 50)
        @test GD.str_to_var(GD.var_to_str(Color_REBECCA_PURPLE)) == Color_REBECCA_PURPLE
        # The engine evaluating the same expressions as Julia (works for single and double precision builds).
        for (gd, jl) in (("Vector2(1, 2).rotated(0.7)", rotated(Vector2(1, 2), 0.7)),
                         ("Vector3(1, 2, 3).slerp(Vector3(-2, 0.5, 1), 0.3)", slerp(Vector3(1, 2, 3), Vector3(-2, 0.5, 1), 0.3)),
                         ("Basis(Vector3(0, 0.6, 0.8), 0.9).get_euler()", get_euler(Basis(Vector3(0, 0.6, 0.8), 0.9))),
                         ("Quaternion(Vector3(0, 0.6, 0.8), 0.9).slerp(Quaternion(Vector3(1, 0, 0), -0.4), 0.3)",
                          slerp(Quaternion(Vector3(0, 0.6, 0.8), 0.9), Quaternion(Vector3(1, 0, 0), -0.4), 0.3)),
                         ("Transform2D(0.5, Vector2(3, -1)).affine_inverse()", affine_inverse(Transform2D(0.5, Vector2(3, -1)))),
                         ("Color(0.8, 0.3, 0.6, 0.9).srgb_to_linear()", srgb_to_linear(Color(0.8, 0.3, 0.6, 0.9))))
            e = Expression()
            @test parse(e, gd) == OK
            @test execute(e) ≈ jl
        end
    end

    @testset "classes from other extensions" begin
        # JuliaRuntime is registered by the GodotJL extension itself, so it is absent from the core bindings.
        @test !haskey(Godot.Internals.CLASS_WRAPPERS, :JuliaRuntime)
        @test has_singleton(Engine, :JuliaRuntime)
        rt = get_singleton(Engine, :JuliaRuntime)
        @test rt isa Godot.Native.GodotObject  # wrapped as the nearest known ancestor
        @test get_class(rt) == "JuliaRuntime"
        @test Godot.call(rt, :is_available) === true
        @test Godot.call(rt, :get_julia_version) == string(VERSION)
        @test class_exists(ClassDB, :JuliaRuntime)
        @test get_parent_class(ClassDB, :JuliaRuntime) === :Object
    end

    @testset "metadata" begin
        @test any(s -> s.name === :ready, Godot.Internals.CLASS_SIGNALS[:Node])
        @test any(v -> v.name === :_process, Godot.Internals.CLASS_VIRTUALS[:Node])
        @test Godot._process isa Function
        @test !isdefined(Godot, :Editor)  # running the game: the editor API is not loaded
        @test Godot.Timer <: Node
    end
end

GC.gc()
Godot.Internals.flush_releases!()
report(ts)
