# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Generated bindings (no engine). parity: 2.8
using Godot
using Godot: Native, Internals

position_of(n::Node2D) = n.position
process_mode_of(n::Node) = n.process_mode

@testset "generated bindings" begin
    @testset "class hierarchy" begin
        @test Node2D <: CanvasItem <: Node <: GodotObject
        @test RefCounted <: GodotObject
        @test Native.Node2D <: Node2D
        @test isabstracttype(Node2D) && !isabstracttype(Native.Node2D)
        @test Internals.CLASS_WRAPPERS[:Node2D] === Native.Node2D
        @test Internals.CLASS_WRAPPERS[:Object] === Native.GodotObject
        @test length(Internals.CLASS_WRAPPERS) > 900
        @test !haskey(Internals.CLASS_WRAPPERS, :EditorPlugin)
        @test Godot.Timer <: Node
        @test !Base.isexported(Godot, :Timer)
        @test Base.isexported(Godot, :Node2D)
    end

    @testset "editor API (GodotEditor)" begin
        packages = normpath(joinpath(pkgdir(Godot), ".."))
        packages in LOAD_PATH || push!(LOAD_PATH, packages)
        editor = Godot.Runtime.load_editor_api!()
        @test nameof(editor) === :GodotEditor
        @test Godot.Runtime.load_editor_api!() === editor
        @test invokelatest(getglobal, Godot, :Editor) === editor
        @test editor.EditorPlugin <: Node
        @test editor.Native.EditorPlugin <: editor.EditorPlugin
        @test Internals.CLASS_WRAPPERS[:EditorPlugin] === editor.Native.EditorPlugin
        @test haskey(Internals.CLASS_VIRTUALS, :EditorPlugin)
        @test hasmethod(add_tool_menu_item, Tuple{editor.EditorPlugin, String, Any})
        @test hasmethod(get_editor_settings, Tuple{Type{editor.EditorInterface}})
        @test editor.EditorPlugin_DOCK_SLOT_BOTTOM isa GodotEnum
    end

    @testset "methods" begin
        @test hasmethod(add_child, Tuple{Node, Node})
        @test hasmethod(add_child, Tuple{Node, Node, Bool, Integer})
        @test hasmethod(get_version_info, Tuple{Type{Engine}})
        @test hasmethod(file_exists, Tuple{Type{FileAccess}, String})
        @test hasmethod(Base.close, Tuple{FileAccess})
        @test hasmethod(Godot.call, Tuple{GodotObject, Symbol, Int})
        @test hasmethod(Node2D, Tuple{})
        @test !hasmethod(Node, Tuple{Int})
        @test Base.return_types(position_of, (Native.Node2D,)) == [Vector2]
        @test Base.return_types(process_mode_of, (Native.Node,)) == [Node_ProcessMode]
    end

    @testset "enums, bitfields, constants" begin
        @test Node_PROCESS_MODE_ALWAYS isa Node_ProcessMode
        @test Node_PROCESS_MODE_ALWAYS isa GodotEnum
        @test Int(Node_PROCESS_MODE_ALWAYS) == 3
        @test repr(Node_PROCESS_MODE_ALWAYS) == "Node_PROCESS_MODE_ALWAYS"
        flags = GodotObject_CONNECT_DEFERRED | GodotObject_CONNECT_ONE_SHOT
        @test flags isa GodotBitfield
        @test GodotObject_CONNECT_ONE_SHOT in flags
        @test !(GodotObject_CONNECT_PERSIST in flags)
        @test occursin("CONNECT_DEFERRED", repr(flags))
        @test OK == Error(0) && ERR_BUG isa Error
        @test TYPE_STRING == VariantType(4)
        @test Vector2_AXIS_X isa Vector2_Axis
        @test Node_NOTIFICATION_READY == 13
        @test Internals.enum_value(Node_PROCESS_MODE_ALWAYS) === Int64(3)
        @test Internals.enum_value(2) === Int64(2)
    end

    @testset "builtin structs" begin
        @test sizeof(Vector2) == Godot.FFI.BUILTIN_SIZES["Vector2"]
        @test sizeof(Transform3D) == Godot.FFI.BUILTIN_SIZES["Transform3D"]
        @test sizeof(Color) == Godot.FFI.BUILTIN_SIZES["Color"]
        @test fieldnames(Rect2) == (:position, :size)
        @test Rect2(1, 2, 3, 4) == Rect2(Vector2(1, 2), Vector2(3, 4))
        @test Transform2D(1, 0, 0, 1, 5, 6).origin == Vector2(5, 6)
        @test all(isbitstype, Godot.MATH_TYPES)
    end

    @testset "metadata and docs" begin
        @test any(s -> s.name === :tree_entered, Internals.CLASS_SIGNALS[:Node])
        proc = only(filter(v -> v.name === :_process, Internals.CLASS_VIRTUALS[:Node]))
        @test proc.args == [:delta => "float"]
        @test :position in Godot.property_names(Native.Node2D)
        @test :name in Godot.property_names(Native.Node2D)
        doc = string(@doc Node2D)
        @test occursin("2D game object", doc)
        @test occursin("set_position", string(@doc set_position))
    end
end
