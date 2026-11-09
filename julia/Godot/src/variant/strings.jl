# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

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

"""
    glob_match(s, expr) -> Bool

Godot's `String.match` (C#: `string.Match`): whether `s` matches the wildcard expression `expr`, where `*` matches
any run of characters and `?` one character. Case-sensitive; `matchn` ignores case. Named `glob_match` because
`Base.match` is Julia's regular-expression match.
"""
function glob_match(s::Union{AbstractString, Symbol}, expr::AbstractString)
    m = Internals.@builtin_method("String", :match, 2566493496)
    raw_expr = FFI.new_string(expr)
    raw_self = FFI.new_string(String(s))
    try
        self = Ref(raw_self)
        return GC.@preserve self FFI.builtin_ptrcall(Bool, m, Base.unsafe_convert(Ptr{Cvoid}, self), raw_expr)
    finally
        FFI.destroy!(raw_self)
        FFI.destroy!(raw_expr)
    end
end
