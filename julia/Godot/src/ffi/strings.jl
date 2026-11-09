# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# String / StringName / NodePath conversions and the process-wide StringName cache.

"Owned Godot `String` holding a copy of `s`."
function new_string(s::AbstractString)
    str = String(s)
    r = Ref{RawString}()
    GC.@preserve str string_new_with_utf8_chars_and_len2(r, pointer(str), sizeof(str))
    return r[]
end

"Owned Godot `StringName` for `s`."
function new_string_name(s::Union{AbstractString, Symbol})
    str = String(s)
    r = Ref{RawStringName}()
    GC.@preserve str string_name_new_with_utf8_chars_and_len(r, pointer(str), sizeof(str))
    return r[]
end

"Owned Godot `NodePath` parsed from `s`."
function new_node_path(s::AbstractString)
    tmp = new_string(s)
    try
        return construct(RawNodePath, tmp)
    finally
        destroy!(tmp)
    end
end

"Julia `String` copy of a Godot `String` (borrowed)."
function julia_string(s::RawString)
    r = Ref(s)
    n = string_to_utf8_chars(r, C_NULL, 0)
    buf = Base.StringVector(n)
    n > 0 && GC.@preserve buf string_to_utf8_chars(r, pointer(buf), n)
    return String(buf)
end

function julia_string(s::Union{RawStringName, RawNodePath})
    tmp = construct(RawString, s)
    try
        return julia_string(tmp)
    finally
        destroy!(tmp)
    end
end

# Cache entries are boxed so their addresses stay stable (Julia's GC does not move objects).
const STRING_NAMES = Dict{Symbol, Base.RefValue{RawStringName}}()
const STRING_NAMES_LOCK = ReentrantLock()

"""
    string_name_ptr(name::Symbol) -> Ptr{RawStringName}

Pointer to a cached `StringName` that lives until the runtime shuts down. Borrowed: never destroy it.
"""
function string_name_ptr(name::Symbol)
    box = @lock STRING_NAMES_LOCK get!(() -> Ref(new_string_name(name)), STRING_NAMES, name)
    return Base.unsafe_convert(Ptr{RawStringName}, box)
end

"""
    sn"name" -> RawStringName

Borrowed `StringName` for a compile-time constant, looked up once per call site (like C#'s cached
`StringName` statics). Never destroy the result.
"""
macro sn_str(s)
    cache = Ref{Ptr{RawStringName}}(C_NULL)
    name = QuoteNode(Symbol(s))
    return quote
        p = $cache[]
        if p == C_NULL
            p = $string_name_ptr($name)
            $cache[] = p
        end
        unsafe_load(p)
    end
end

function destroy_string_names!()
    @lock STRING_NAMES_LOCK begin
        foreach(box -> destroy!(box[]), values(STRING_NAMES))
        empty!(STRING_NAMES)
    end
    return nothing
end
