"""
    Godot

Julia scripting support for the Godot engine (analog of `GodotSharp`).
"""
module Godot

"Godot version whose `extension_api.json` this package targets; must match the repository's `GODOT_VERSION`."
const GODOT_VERSION = v"4.7.2"

"Minimum Godot API version required at runtime (matches `compatibility_minimum` in the `.gdextension`)."
const GODOT_API_VERSION = v"4.7"

# Extended (not shadowed) so `using LinearAlgebra` and `using Godot` work together.
import LinearAlgebra: dot, cross, norm, normalize, det

include("ffi/FFI.jl")
include("core/types.jl")
include("core/Internals.jl")
include(joinpath(FFI.GENERATED_DIR, "builtin_structs.jl"))
include(joinpath(FFI.GENERATED_DIR, "global_enums.jl"))
include("core/enums.jl")
include("builtins/builtins.jl")
include("variant/packed.jl")
include("variant/variant.jl")
include("variant/array.jl")
include("variant/dictionary.jl")
include("variant/strings.jl")
include("variant/callable.jl")
include("object/lifetime.jl")
include("object/objects.jl")
include(joinpath(FFI.GENERATED_DIR, "builtin_methods.jl"))
include(joinpath(FFI.GENERATED_DIR, "classes.jl"))
include("object/nodes.jl")
include(joinpath(FFI.GENERATED_DIR, "globals.jl"))
include("runtime/Runtime.jl")
include("object/scripting.jl")
include("signals/signals.jl")
include("async/scheduler.jl")
include("async/awaiters.jl")
include("precompile.jl")

export GodotObject, GodotEnum, GodotBitfield, NodePath, RID, GDArray, GDDictionary, Callable, Signal, PackedArray,
       PackedByteArray, PackedInt32Array, PackedInt64Array, PackedFloat32Array, PackedFloat64Array, PackedStringArray,
       PackedVector2Array, PackedVector3Array, PackedColorArray, PackedVector4Array, free, singleton, Variant,
       variant_type, isvarianttype, VariantConversionError, StringName, FreedObjectError, as, is_instance_valid,
       weakref, set!, has_property, @godot_class, @tool, @global_class, @icon, @rpc, script_type, SignalName,
       PropertyName, MethodName, callable_target, connect_callable, godot_task, @async_godot, @await, to_signal,
       SignalAwaiter, SignalCancelled, next_frame, next_physics_frame, delay, @breakpoint, @feature

end # module Godot
