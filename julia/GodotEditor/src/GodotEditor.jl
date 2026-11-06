"""
    GodotEditor

Editor-only engine API (`EditorPlugin`, `EditorInterface`, ...), the analog of C#'s GodotSharpEditor assembly.
The native host loads it only when the Godot editor runs and binds it as `Godot.Editor`; exported games never load it.
"""
module GodotEditor

using Godot
using Godot: Internals, FFI, GodotEnum, GodotBitfield

include(joinpath(@__DIR__, "generated", "classes.jl"))
include(joinpath(@__DIR__, "tools", "Tools.jl"))

function __init__()
    Internals.register_classes!(__CLASS_WRAPPERS, __CLASS_SIGNALS, __CLASS_VIRTUALS)
    Tools.install!()
end

end # module GodotEditor
