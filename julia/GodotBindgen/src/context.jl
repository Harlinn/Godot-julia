# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Shared lookups and naming/type-mapping rules for the class generator.

const MATH_BUILTINS = ["Vector2", "Vector2i", "Rect2", "Rect2i", "Vector3", "Vector3i", "Transform2D", "Vector4",
                       "Vector4i", "Plane", "Quaternion", "AABB", "Basis", "Transform3D", "Projection", "Color"]

const PACKED_TYPES = ["PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array",
                      "PackedFloat64Array", "PackedStringArray", "PackedVector2Array", "PackedVector3Array",
                      "PackedColorArray", "PackedVector4Array"]

"Type mapping for one Godot API type."
struct TypeSpec
    annot::String          # Julia argument annotation
    native::String         # isbits type passed through ptrcall
    arg::String            # expression converting `%` (the Julia argument) to `native`
    owned::Bool            # whether the converted argument must be destroyed after the call
    ret::String            # expression converting `%` (a native return value, owned) to the Julia value
end

mutable struct Context
    api::Dict{String, Any}
    classes::Dict{String, Any}
    editor::Set{String}
    scope::Symbol                         # :core (module Godot) or :editor (package GodotEditor)
    enum_refs::Dict{String, Tuple{Bool, String}}  # "Node.ProcessMode" => (owner is editor class, "Node_ProcessMode")
    base_functions::Set{String}           # exported Base functions that Godot methods extend
    reserved::Set{String}                 # names that cannot be used as method functions
    renames::Vector{String}
    skipped::Vector{String}
end

type_name(class::AbstractString) = class == "Object" ? "GodotObject" : String(class)

function Context(api; scope::Symbol = :core)
    scope in (:core, :editor) || throw(ArgumentError("scope must be :core or :editor"))
    classes = Dict(c["name"] => c for c in api["classes"])
    editor = Set(c["name"] for c in api["classes"] if c["api_type"] in ("editor", "editor_extension"))
    exported = [String(s) for s in names(Base) if Base.isexported(Base, s) && isdefined(Base, s)]
    funcs = Set(s for s in exported if getfield(Base, Symbol(s)) isa Function &&
                                      !(getfield(Base, Symbol(s)) isa Core.Builtin) &&
                                      !(getfield(Base, Symbol(s)) isa Core.IntrinsicFunction))
    # Every module defines its own `eval` and `include`.
    reserved = union(Set(setdiff(exported, funcs)), JULIA_KEYWORDS, Set(["eval", "include"]))
    ctx = Context(api, classes, editor, scope, Dict{String, Tuple{Bool, String}}(), funcs, reserved, String[], String[])
    for c in api["classes"], e in get(c, "enums", [])
        ctx.enum_refs["$(c["name"]).$(e["name"])"] = (c["name"] in editor, "$(type_name(c["name"]))_$(e["name"])")
    end
    for e in api["global_enums"]
        ctx.enum_refs[e["name"]] = (false, replace(e["name"], "." => ""))
    end
    for b in api["builtin_classes"], e in get(b, "enums", [])
        ctx.enum_refs["$(b["name"]).$(e["name"])"] = (false, "$(b["name"])_$(e["name"])")
    end
    return ctx
end

is_editor(ctx::Context, class) = class in ctx.editor

"Qualify a name owned by `Godot` (`editor_owned = false`) or `GodotEditor` for use in the current scope."
qualify(ctx::Context, editor_owned::Bool, name::AbstractString) =
    ctx.scope == :editor && !editor_owned ? "Godot.$name" : String(name)

"Reference to a class-scoped name (type, enum, constant) of `class` from the module being generated."
class_ref(ctx::Context, class, name = type_name(class)) = qualify(ctx, is_editor(ctx, class), name)
native_ref(ctx::Context, class) = qualify(ctx, is_editor(ctx, class), "Native." * type_name(class))

"Julia generic function used for a Godot method name (extends `Base` when Base exports a function of that name)."
function method_function(ctx::Context, name::AbstractString)
    name in ctx.base_functions && return "Base.$name"
    # All method generic functions are owned by `Godot`, including those only editor classes implement.
    return qualify(ctx, false, name in ctx.reserved ? name * "_" : String(name))
end

function safe_arg(name::AbstractString)
    name in JULIA_KEYWORDS && return name * "_"
    name == "self" && return "self_"
    return String(name)
end

function enum_type_ref(ctx::Context, t::AbstractString)
    key = split(t, "::"; limit = 2)[2]
    ref = get(ctx.enum_refs, key, nothing)
    return ref === nothing ? nothing : qualify(ctx, ref...)
end

function type_spec(ctx::Context, t::AbstractString)
    t == "int" && return TypeSpec("Integer", "Int64", "Int64(%)", false, "%")
    t == "float" && return TypeSpec("Real", "Float64", "Float64(%)", false, "%")
    t == "bool" && return TypeSpec("Bool", "Bool", "%", false, "%")
    t == "String" && return TypeSpec("AbstractString", "FFI.RawString", "FFI.new_string(%)", true, "Internals.take_string(%)")
    t == "StringName" && return TypeSpec("Internals.StringNameLike", "FFI.RawStringName", "FFI.new_string_name(%)", true,
                                         "Internals.take_string_name(%)")
    t == "NodePath" && return TypeSpec("Internals.NodePathLike", "FFI.RawNodePath", "Internals.new_node_path(%)", true,
                                       "Internals.take_node_path(%)")
    t == "Variant" && return TypeSpec("Any", "FFI.RawVariant", "Internals.to_variant(%)", true, "Internals.take_variant(%)")
    t == "RID" && return TypeSpec("RID", "FFI.RawRID", "%.raw", false, "RID(%)")
    t == "Callable" && return TypeSpec("Any", "FFI.RawCallable", "Internals.new_callable(%)", true, "Internals.take_callable(%)")
    t == "Signal" && return TypeSpec("Any", "FFI.RawSignal", "Internals.new_signal(%)", true, "Internals.take_signal(%)")
    if t == "Dictionary"
        return TypeSpec("Any", "FFI.RawDictionary", "Internals.new_dictionary(%)", true, "Internals.take_dictionary(%)")
    end
    if startswith(t, "typeddictionary::")
        kv = split(t[(length("typeddictionary::") + 1):end], ";")
        k, v = typed_element(ctx, kv[1]), typed_element(ctx, kv[2])
        ret = k === nothing || v === nothing ? "Internals.take_dictionary(%)" : "Internals.take_dictionary(GDDictionary{$k, $v}, %)"
        return TypeSpec("Any", "FFI.RawDictionary", "Internals.new_dictionary(%)", true, ret)
    end
    if t == "Array"
        return TypeSpec("Any", "FFI.RawArray", "Internals.new_array(%)", true, "Internals.take_array(%)")
    end
    if startswith(t, "typedarray::")
        e = typed_element(ctx, t[(length("typedarray::") + 1):end])
        ret = e === nothing ? "Internals.take_array(%)" : "Internals.take_array(GDArray{$e}, %)"
        return TypeSpec("Any", "FFI.RawArray", "Internals.new_array(%)", true, ret)
    end
    if t in PACKED_TYPES
        return TypeSpec("Any", "FFI.Raw$t", "Internals.new_packed(FFI.Raw$t, %)", true, "Internals.take_packed(%)")
    end
    t in MATH_BUILTINS && return TypeSpec(t, t, "%", false, "%")
    if startswith(t, "enum::") || startswith(t, "bitfield::")
        ref = enum_type_ref(ctx, t)
        ref === nothing && return TypeSpec("Integer", "Int64", "Int64(%)", false, "%")
        return TypeSpec("Union{$ref, Integer}", "Int64", "Internals.enum_value(%)", false, "$ref(%)")
    end
    if haskey(ctx.classes, t)
        # Core never references editor classes in 4.7; if it ever does, degrade to the root type.
        ctx.scope == :core && is_editor(ctx, t) && (t = "Object")
        ref = class_ref(ctx, t)
        owned = get(ctx.classes[t], "is_refcounted", false)
        return TypeSpec("Union{Nothing, $ref}", "Ptr{Cvoid}", "Internals.object_ptr(%)", false,
                        "Internals.take_object($ref, %, $owned)")
    end
    endswith(t, "*") && return TypeSpec("Ptr", "Ptr{Cvoid}", "Ptr{Cvoid}(%)", false, "%")
    return nothing
end

subst(template::AbstractString, x::AbstractString) = replace(template, "%" => x)

const TYPED_BUILTINS = Dict("int" => "Int64", "float" => "Float64", "bool" => "Bool", "String" => "String",
                            "StringName" => "Symbol", "NodePath" => "NodePath", "RID" => "RID", "Variant" => "Any",
                            "Callable" => "Callable", "Signal" => "Signal", "Array" => "GDArray{Any}",
                            "Dictionary" => "GDDictionary{Any, Any}")

"Julia element type for a typed Array/Dictionary hint (`Node`, `int`, `24/17:Font`, `27/0:`), or `nothing`."
function typed_element(ctx::Context, s::AbstractString)
    m = match(r"^(\d+)/\d+:(.*)$", s)
    if m !== nothing
        m[1] == "27" && return qualify(ctx, false, "GDDictionary{Any, Any}")
        m[1] == "24" && !isempty(m[2]) && (s = m[2])
    end
    if haskey(TYPED_BUILTINS, s)
        jt = TYPED_BUILTINS[s]
        return jt in ("Int64", "Float64", "Bool", "String", "Symbol", "Any") ? jt : qualify(ctx, false, jt)
    end
    (s in MATH_BUILTINS || s in PACKED_TYPES) && return qualify(ctx, false, s)
    if haskey(ctx.classes, s)
        ctx.scope == :core && is_editor(ctx, s) && return "GodotObject"
        return class_ref(ctx, s)
    end
    return nothing
end

leaf_count(api_struct_fields, name) = haskey(api_struct_fields, name) ?
    sum(f -> leaf_count(api_struct_fields, f[2]), api_struct_fields[name]) : 1

function julia_string_literal(godot_literal::AbstractString)
    return repr(unescape_string(chop(godot_literal; head = 1, tail = 1)))
end

function symbol_literal(s::AbstractString)
    return Base.isidentifier(s) ? ":" * s : "Symbol($(repr(s)))"
end

"""
    julia_default(ctx, type, default, struct_fields) -> Union{String, Nothing}

Julia expression for a Godot default argument, or `nothing` when it cannot be expressed (the argument becomes required).
"""
function julia_default(ctx::Context, t::AbstractString, d::AbstractString, struct_fields)
    d == "null" && return "nothing"
    if t == "int" || startswith(t, "enum::") || startswith(t, "bitfield::")
        return occursin(r"^-?\d+$", d) ? String(d) : nothing
    elseif t == "float"
        d == "inf" && return "Inf"
        d == "-inf" && return "-Inf"
        occursin(r"^-?\d+$", d) && return d * ".0"
        x = tryparse(Float64, d)
        return x === nothing ? nothing : repr(x)
    elseif t == "bool"
        return d in ("true", "false") ? String(d) : nothing
    elseif t == "String"
        return startswith(d, "\"") ? julia_string_literal(d) : nothing
    elseif t == "StringName"
        startswith(d, "&\"") && return symbol_literal(unescape_string(chop(d; head = 2, tail = 1)))
        startswith(d, "\"") && return symbol_literal(unescape_string(chop(d; head = 1, tail = 1)))
        return nothing
    elseif t == "NodePath"
        m = match(r"^NodePath\((\".*\")\)$", d)
        m !== nothing && return "NodePath($(julia_string_literal(m[1])))"
        return startswith(d, "\"") ? "NodePath($(julia_string_literal(d)))" : nothing
    elseif t == "Variant"
        d in ("true", "false") && return String(d)
        occursin(r"^-?\d+$", d) && return String(d)
        tryparse(Float64, d) !== nothing && return repr(parse(Float64, d))
        startswith(d, "\"") && return julia_string_literal(d)
        return nothing
    elseif t in MATH_BUILTINS
        m = match(r"^(\w+)\((.*)\)$", d)
        (m === nothing || m[1] != t) && return nothing
        args = strip.(split(m[2], ","))
        args = [a == "inf" ? "Inf" : a == "-inf" ? "-Inf" : a for a in args if !isempty(a)]
        all(a -> a in ("Inf", "-Inf") || tryparse(Float64, a) !== nothing, args) || return nothing
        length(args) == leaf_count(struct_fields, t) || return nothing
        return "$t($(join(args, ", ")))"
    elseif t == "RID"
        return d == "RID()" ? "RID()" : nothing
    elseif t in ("Array", "Dictionary", "Callable", "Signal") || t in PACKED_TYPES ||
           startswith(t, "typedarray::") || startswith(t, "typeddictionary::")
        empty = d in ("[]", "{}", "Callable()", "Signal()", "Array()", "Dictionary()", "$t()") ||
                occursin(r"^Array\[[^\]]*\]\(\[\]\)$", d) || occursin(r"^Dictionary\[[^\]]*\]\(\{\}\)$", d)
        return empty ? "nothing" : nothing
    end
    return nothing
end
