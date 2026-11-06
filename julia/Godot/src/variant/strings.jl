# String, StringName, NodePath and RID conveniences (the builtin methods themselves are generated).
# Ported from GodotSharp/Core/StringName.cs, NodePath.cs, Rid.cs (MIT, Godot contributors).

"""
    StringName

Godot `StringName`s are represented by Julia `Symbol`s, which are interned the same way (`StringName("x") === :x`).
"""
const StringName = Symbol

NodePath(s::Symbol) = NodePath(String(s))
Base.convert(::Type{NodePath}, s::Union{AbstractString, Symbol}) = NodePath(s)
Base.string(p::NodePath) = p.path
Base.show(io::IO, p::NodePath) = print(io, "NodePath(", repr(p.path), ")")

Base.show(io::IO, r::RID) = print(io, "RID(", r.raw._data[1], ")")
Base.isless(a::RID, b::RID) = a.raw._data[1] < b.raw._data[1]
