# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Precompile workload. Dependency-free stand-in for PrecompileTools: inside the engine, LOAD_PATH holds only the
# Godot-julia packages and stdlibs. Engine calls cannot execute at precompile time, so they are compiled, not run.
let
    R = Runtime
    precompile(R.__init_runtime__, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{R.HostAPI}, Ptr{R.JuliaAPI}))
    precompile(R._eval_string, (Ptr{UInt8}, Int64, Ptr{Cvoid}))
    precompile(R._shutdown, ())
    precompile(R.load_editor_api!, ())
    precompile(R.install_output!, ())
    precompile(R.host_string_out, (Ptr{Cvoid}, String))
    precompile(R.report_exception, (Exception, Vector{Union{Ptr{Nothing}, Base.InterpreterIP}}))
    precompile(FFI.init!, (Ptr{Cvoid}, Ptr{Cvoid}, UInt32))
    precompile(include_string, (Module, String, String))
    precompile(repr, (Any,))
    precompile(Base.unsafe_write, (R.GodotStream, Ptr{UInt8}, UInt))
    precompile(Base.flush, (R.GodotStream,))
    precompile(Internals.flush_releases!, ())

    # Common engine calls from scripts.
    for T in (Native.Node, Native.Node2D, Native.Node3D, Native.Control, Native.Sprite2D, Native.CharacterBody2D,
              Native.CharacterBody3D, Native.Area2D, Native.Camera2D, Native.Label)
        precompile(add_child, (T, Native.Node))
        precompile(get_child_count, (T,))
        precompile(get_children, (T,))
        precompile(get_node, (T, String))
        precompile(get_parent, (T,))
        precompile(get_name, (T,))
        precompile(queue_free, (T,))
        precompile(is_inside_tree, (T,))
        precompile(Base.getproperty, (T, Symbol))
        precompile(Base.setproperty!, (T, Symbol, Any))
    end
    for T in (Native.Node2D, Native.Sprite2D, Native.CharacterBody2D, Native.Area2D, Native.Camera2D)
        precompile(get_position, (T,))
        precompile(set_position, (T, Vector2))
        precompile(get_global_position, (T,))
        precompile(set_rotation, (T, Float64))
    end
    for T in (Native.Node3D, Native.CharacterBody3D)
        precompile(get_position, (T,))
        precompile(set_position, (T, Vector3))
    end
    precompile(move_and_slide, (Native.CharacterBody2D,))
    precompile(move_and_slide, (Native.CharacterBody3D,))
    precompile(set_text, (Native.Label, String))
    precompile(is_action_pressed, (Type{Input}, String))
    precompile(is_action_just_pressed, (Type{Input}, String))
    precompile(get_vector, (Type{Input}, String, String, String, String))
    precompile(Internals.singleton, (Type{Input},))
    precompile(Internals.singleton, (Type{Engine},))
    precompile(Internals.take_object, (Type{Node}, Ptr{Cvoid}, Bool))
    precompile(Internals.construct_object, (Type{Native.Node}, Symbol))
    for X in (Nothing, Bool, Int, Float64, String, Symbol, Vector2, Vector3, Color, Native.Node)
        precompile(Internals.to_variant, (X,))
    end
    precompile(Internals.from_variant, (FFI.RawVariant,))
    precompile(Internals.take_variant, (FFI.RawVariant,))
    precompile(GD.print, (String,))
    precompile(GD.push_error, (String,))
    precompile(GD.load, (String,))

    # Engine-free code can run.
    sprint(show, Node_PROCESS_MODE_ALWAYS)
    sprint(show, MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT)
    Vector2(1, 2) == Vector2(1.0f0, 2.0f0)
    for v in (Vector2(1, 2), Vector3(1, 2, 3))
        normalized(v + v * 2.0 - v / 2)
        length(v)
        lerp(v, v, 0.5)
        distance_to(v, v)
        dot(v, v)
        move_toward(v, v, 0.1)
    end
    rotated(Vector2(1, 2), 0.5)
    Transform2D(0.5, Vector2(1, 2)) * Vector2(1, 2)
    b = from_euler(Basis, Vector3(0.1, 0.2, 0.3))
    t = Transform3D(b, Vector3(1, 2, 3))
    t * t * Vector3(1, 2, 3)
    affine_inverse(t)
    rotated(t, Vector3(0, 1, 0), 0.5)
    looking_at(t, Vector3(0, 0, -5))
    slerp(Quaternion(b), Quaternion(), 0.5)
    Color(0.1, 0.2, 0.3) * 0.5
end
