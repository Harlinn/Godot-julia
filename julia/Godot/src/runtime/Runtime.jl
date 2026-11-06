"""
    Godot.Runtime

Internal bridge called by the native host (analog of `ScriptManagerBridge`/`CSharpInstanceBridge`).
"""
module Runtime

using ..Godot: Godot, GodotObject, GodotEnum, GodotBitfield, GDArray, GDDictionary
using ..FFI: FFI
using ..Internals: Internals

include("abi.jl")
include("entry.jl")
include("pins.jl")
include("output.jl")
include("debugging.jl")
include("debugserver.jl")
include("callables.jl")
include("scripts.jl")
include("export.jl")
include("instances.jl")
include("reload.jl")
include("bridge.jl")
include("init.jl")

end # module Runtime
