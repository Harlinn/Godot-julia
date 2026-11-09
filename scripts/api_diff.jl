#!/usr/bin/env julia
# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Compares GodotSharp's public API (builtin types, GD, Mathf, GodotObject helpers and extensions, collections, string
# extensions, Variant, Callable, Signal) with the Julia `Godot` package and prints the C# members that have no Julia
# counterpart. Names are mapped with the documented rules: snake_case functions taking the value first (ADR 0003,
# 0005), static members taking the type (`from_angle(Vector2, a)`), constants as `Type_UPPER_SNAKE`, Base/LinearAlgebra
# generics where Julia has them (`length`, `push!`, `haskey`, ...), and `convert`/constructors for Variant conversions.
# Members with no Julia equivalent by design are listed in EXCLUDED with the reason.
# Usage: julia --project=julia/Godot scripts/api_diff.jl [--source=<GodotSharp/Core dir>] [--strict] [--verbose]
#   Without --source, Godot's modules/mono is sparse-cloned at the GODOT_VERSION tag into .tools/godot-mono.
#   --strict exits with 1 when a member is missing; --verbose also lists the members that were found.

using Godot
using LinearAlgebra
using Random

const ROOT = normpath(joinpath(@__DIR__, ".."))
const TAG = strip(read(joinpath(ROOT, "GODOT_VERSION"), String))
const CORE_REL = joinpath("modules", "mono", "glue", "GodotSharp", "GodotSharp", "Core")

function source_dir()
    for a in ARGS
        startswith(a, "--source=") && return a[10:end]
    end
    clone = joinpath(ROOT, ".tools", "godot-mono")
    if !isdir(joinpath(clone, CORE_REL))
        run(`git clone --depth 1 --branch $TAG --filter=blob:none --sparse https://github.com/godotengine/godot.git $clone`)
        run(`git -C $clone sparse-checkout set modules/mono`)
    end
    return joinpath(clone, CORE_REL)
end

# --- C# side -------------------------------------------------------------------------------------------------------

struct CsMember
    file::String
    type::String
    name::String
    kind::Symbol      # :method, :property, :field, :const
    static::Bool
    generic::Bool     # Name<T>(...)
    extension::Bool   # static method with a `this` first parameter
    receiver::String  # type of the `this` parameter of an extension method
    line::Int
end

const MODIFIERS = Set(["static", "readonly", "override", "virtual", "new", "unsafe", "sealed", "abstract", "extern",
                       "partial", "const", "ref", "scoped", "async", "implicit", "explicit"])

"Public members of the top-level types of a C# file (nested types, operators, constructors and indexers skipped)."
function parse_cs(path::String)
    members = CsMember[]
    lines = readlines(path)
    type_re = r"^(\s*)public\s+(?:(?:static|readonly|partial|sealed|abstract|unsafe|ref)\s+)*(?:class|struct|interface)\s+(\w+)"
    type_indent = minimum((length(m[1]) for m in (match(type_re, l) for l in lines) if m !== nothing); init = typemax(Int))
    current = ""
    hidden = false
    for (i, l) in enumerate(lines)
        s = strip(l)
        indent = length(l) - length(lstrip(l))
        if startswith(s, "[")
            occursin(r"Obsolete|EditorBrowsable\(EditorBrowsableState\.Never\)", s) && (hidden = true)
            continue
        end
        isempty(s) || startswith(s, "//") || startswith(s, "///") ? continue : nothing
        m = match(type_re, l)
        if m !== nothing && length(m[1]) == type_indent
            current = String(m[2])
            hidden = false
            continue
        end
        if indent == type_indent + 4 && startswith(s, "public ") && !isempty(current) && !hidden
            mem = parse_member(s[8:end], current, basename(path), i)
            mem === nothing || push!(members, mem)
        end
        hidden = false
    end
    return members
end

function parse_member(decl::AbstractString, type::String, file::String, line::Int)
    decl = replace(decl, r"\bwhere\b.*$" => "")
    occursin(r"\boperator\b|\bthis\s*\[|\b(enum|class|struct|interface|delegate|event)\b", decl) && return nothing
    words = split(decl)
    static = "static" in words
    isconst = "const" in words
    while !isempty(words) && words[1] in MODIFIERS
        popfirst!(words)
    end
    rest = join(words, " ")
    # Constructor: `Vector2(real_t x, real_t y)`.
    m = match(r"^(\w+)\s*\(", rest)
    m !== nothing && m[1] == type && return nothing
    m = match(r"^([\w\.\?\[\]<>,\s\*]+?)\s+(\w+)\s*(<[^>]*>)?\s*(\(|\{|=>|;|=|$)", rest)
    m === nothing && return nothing
    # Only generics returning their type argument (`T GetNode<T>(...)`) need the typed Julia form.
    name, generic, tail = m[2], m[3] !== nothing && strip(m[1]) == "T", m[4]
    kind = tail == "(" ? :method : isconst ? :const : tail in ("{", "=>", "") ? :property : :field
    extension = kind === :method && occursin(r"\(\s*this\s", rest)
    r = match(r"\(\s*this\s+([^\s]+)", rest)
    return CsMember(file, type, String(name), kind, static, generic, extension, r === nothing ? "" : String(r[1]), line)
end

# --- Julia side ----------------------------------------------------------------------------------------------------

"PascalCase → snake_case (`IsEqualApprox` → `is_equal_approx`, `Atan2` → `atan2`, `ToUtf16Buffer` → `to_utf16_buffer`)."
function snake(s::AbstractString)
    s = replace(s, r"([A-Z]+)([A-Z][a-z])" => s"\1_\2")
    s = replace(s, r"([a-z0-9])([A-Z])" => s"\1_\2")
    return lowercase(s)
end

const JULIA_TYPES = Dict(
    "Aabb" => AABB, "Basis" => Basis, "Color" => Color, "Colors" => Color, "Plane" => Plane, "Projection" => Projection,
    "Quaternion" => Quaternion, "Rect2" => Rect2, "Rect2I" => Rect2i, "Rid" => RID, "Transform2D" => Transform2D,
    "Transform3D" => Transform3D, "Vector2" => Vector2, "Vector2I" => Vector2i, "Vector3" => Vector3,
    "Vector3I" => Vector3i, "Vector4" => Vector4, "Vector4I" => Vector4i, "Callable" => Callable, "Signal" => Signal,
    "StringName" => Symbol, "NodePath" => NodePath, "Variant" => Variant, "Array" => GDArray,
    "Dictionary" => GDDictionary, "GodotObject" => GodotObject, "StringExtensions" => String,
    "Node" => Godot.Node, "PackedScene" => Godot.PackedScene, "ResourceLoader" => Godot.ResourceLoader)

# Value types whose static members take the type in Julia (`from_hsv(Color, ...)`).
const VALUE_TYPES = Set(["Aabb", "Basis", "Color", "Colors", "Plane", "Projection", "Quaternion", "Rect2", "Rect2I",
                         "Rid", "Transform2D", "Transform3D", "Vector2", "Vector2I", "Vector3", "Vector3I", "Vector4",
                         "Vector4I"])

# Receiver of a C# extension method by its `this` parameter type.
const RECEIVERS = Dict("string" => AbstractString, "byte[]" => AbstractVector{UInt8}, "Span<byte>" => AbstractVector{UInt8},
                       "ReadOnlySpan<byte>" => AbstractVector{UInt8})

# C# names whose Julia counterpart has a different spelling (Base/LinearAlgebra generics, Julia idioms).
const RENAMED = Dict{String, Vector{Symbol}}(
    "Length" => [:length], "LengthSquared" => [:length_squared], "Inverse" => [:inv, :inverse],
    "Transposed" => [:transpose], "Determinant" => [:det, :determinant], "Normalized" => [:normalized, :normalize],
    "IsEqualApprox" => [:isapprox, :is_equal_approx], "Add" => [:push!], "AddRange" => [:append!],
    "Clear" => [:empty!], "Contains" => [:in, :contains, :occursin], "ContainsKey" => [:haskey],
    "Count" => [:length, :count], "IndexOf" => [:findfirst, :find], "Insert" => [:insert!], "RemoveAt" => [:deleteat!],
    "Remove" => [:erase, :delete!, :filter!], "Keys" => [:keys], "Values" => [:values],
    "TryGetValue" => [:get], "Resize" => [:resize!], "Shuffle" => [:shuffle!], "Sort" => [:sort!],
    "Reverse" => [:reverse!, :reverse], "Fill" => [:fill!], "Max" => [:max, :maximum], "Min" => [:min, :minimum],
    "Slice" => [:slice, :view, :getindex], "Duplicate" => [:duplicate, :copy, :deepcopy], "Concat" => [:vcat, :append!],
    "Merge" => [:merge!, :merge], "PickRandom" => [:pick_random, :rand], "Filter" => [:filter],
    "Find" => [:findfirst, :find], "FindN" => [:findfirst, :findn], "RFind" => [:findlast, :rfind],
    "Substr" => [:substr, :SubString], "StartsWith" => [:startswith, :begins_with], "EndsWith" => [:endswith, :ends_with],
    "ToUpper" => [:uppercase, :to_upper], "ToLower" => [:lowercase, :to_lower], "Split" => [:split],
    "Replace" => [:replace], "Repeat" => [:repeat], "Join" => [:join],
    "Print" => [:print, :println], "Str" => [:str, :string], "Hash" => [:hash], "Abs" => [:abs], "Sign" => [:sign],
    "Exp" => [:exp], "Log" => [:log], "Pow" => [:pow, :^], "Sqrt" => [:sqrt], "IsNaN" => [:isnan, :is_nan],
    "IsInf" => [:isinf, :is_inf], "IsFinite" => [:isfinite, :is_finite], "Atan2" => [:atan, :atan2],
    "Pi" => [:PI, :pi], "Tau" => [:TAU], "Inf" => [:INF, :Inf], "NaN" => [:NAN, :NaN], "E" => [:E, :ℯ],
    "Sqrt2" => [:SQRT2], "Epsilon" => [:EPSILON], "Instantiate" => [:instantiate], "Load" => [:load],
    "Bind" => [:bind], "Call" => [:call], "CallDeferred" => [:call_deferred], "Emit" => [:emit],
    "Owner" => [:owner, :get_object], "Name" => [:name, :get_name], "Target" => [:target, :get_object],
    "Method" => [:method, :get_method], "VariantType" => [:variant_type],
    "IsEmpty" => [:isempty, :is_empty], "Size" => [:size, :length], "MakeReadOnly" => [:make_read_only],
    "IsReadOnly" => [:is_read_only], "IsTyped" => [:is_typed], "Floor" => [:floor], "Ceil" => [:ceil],
    "Round" => [:round], "Clamp" => [:clamp], "Lerp" => [:lerp], "Dot" => [:dot], "Cross" => [:cross],
    "Snapped" => [:snapped], "PosMod" => [:posmod], "Wrap" => [:wrap], "ToSignal" => [:to_signal],
    "IsInstanceValid" => [:is_instance_valid], "WeakRef" => [:weakref], "InstanceFromId" => [:instance_from_id],
    "IsInstanceIdValid" => [:is_instance_id_valid], "FromHtml" => [:html], "Intersect3" => [:intersect_3],
    "PerspectiveZNearAdjusted" => [:perspective_znear_adjusted], "GetSubName" => [:get_subname],
    "GetSubNameCount" => [:get_subname_count], "GetConcatenatedSubNames" => [:get_concatenated_subnames],
    "PrintErr" => [:printerr], "PrintRaw" => [:printraw], "PrintS" => [:prints], "PrintT" => [:printt],
    "RandRange" => [:randf_range, :randi_range], "TypeToVariantType" => [:variant_type],
    "SmoothStep" => [:smoothstep], "PingPong" => [:pingpong], "DecimalCount" => [:step_decimals, :decimal_count],
    "BinarySearch" => [:bsearch, :searchsortedfirst], "LastIndexOf" => [:rfind, :findlast], "CountN" => [:countn],
    "GetBaseName" => [:get_basename], "IsSubsequenceOfN" => [:is_subsequence_ofn], "IsValidFileName" => [:is_valid_filename],
    "MatchN" => [:matchn], "ReplaceN" => [:replacen], "RFindN" => [:rfindn], "Match" => [:glob_match],
    "Color8" => [:from_rgba8], "GetSliceRange" => [:slice], "Obj" => [:getindex])

# C# constant names whose Godot constant is spelled differently (`Vector2I.MinValue` → `Vector2i_MIN`).
const CONST_RENAMED = Dict("MinValue" => "MIN", "MaxValue" => "MAX")

# C# members with no Julia counterpart by design, and why.
const EXCLUDED = Dict{String, String}(
    "Equals" => "`==`/`isequal`", "GetHashCode" => "`hash`", "ToString" => "`string`/`show`",
    "Deconstruct" => "destructuring uses fields or `Tuple(v)`", "Dispose" => "lifetime is GC-managed (`finalize`)",
    "GetEnumerator" => "`iterate`", "CopyTo" => "`copyto!`", "NativeInstance" => "internal pointer",
    "GetAwaiter" => "`wait`/`@await`", "CompareTo" => "`isless`/`cmp`", "Trampoline" => "internal (delegate thunk)",
    "Delegate" => "Julia callables are functions", "Item" => "indexing (`a[i]`)", "this" => "indexing (`a[i]`)",
    "AsSpan" => "Julia arrays/views", "AsReadOnly" => "`make_read_only`", "IsFixedSize" => "Julia arrays are resizable",
    "IsSynchronized" => ".NET collection interface", "SyncRoot" => ".NET collection interface",
    "CreateTakingOwnershipOfDisposableValue" => "internal marshalling", "CreateCopyingBorrowed" => "internal marshalling",
    "NativeVar" => "internal marshalling", "CreateFrom" => "`Variant(x)`", "From" => "`Variant(x)` / `Callable(f)`",
    "As" => "`convert(T, v)`", "IsUnsafe" => "internal", "TypeOf" => "`variant_type`",
    "Column0" => "`b.x` (columns are `x/y/z`)", "Column1" => "`b.y`", "Column2" => "`b.z`",
    "CopyNativeVariant" => "internal marshalling", "UnderlyingArray" => "internal marshalling",
    "UnderlyingDictionary" => "internal marshalling")

"Resolve `name` as a function visible from `Godot` (incl. Base/LinearAlgebra re-exports) or the given modules."
function resolve(name::Symbol, mods::Vector{Module} = Module[Godot])
    for m in (mods..., Godot, Base, LinearAlgebra, Random)
        isdefined(m, name) && return getglobal(m, name)
    end
    return nothing
end

applies(f, sig) = f !== nothing && !(f isa Type && !(f isa DataType || f isa UnionAll)) &&
                  (try !isempty(methods(f, sig)) catch; false end)

function candidates(m::CsMember)
    names = Symbol[]
    haskey(RENAMED, m.name) && append!(names, RENAMED[m.name])
    s = snake(m.name)
    push!(names, Symbol(s), Symbol(s * "!"))
    m.kind === :property && push!(names, Symbol("get_" * s), Symbol("is_" * s))
    return unique(names)
end

sample(T) = Dict{Any, Any}(Vector2 => Vector2(1, 2), Vector2i => Vector2i(1, 2), Vector3 => Vector3(1, 2, 3),
                           Vector3i => Vector3i(1, 2, 3), Vector4 => Vector4(1, 2, 3, 4),
                           Vector4i => Vector4i(1, 2, 3, 4), Rect2 => Rect2(0, 0, 1, 1), Rect2i => Rect2i(0, 0, 1, 1),
                           AABB => AABB(Vector3(0, 0, 0), Vector3(1, 1, 1)), Basis => Basis_IDENTITY,
                           Transform2D => Transform2D_IDENTITY, Transform3D => Transform3D_IDENTITY,
                           Quaternion => Quaternion_IDENTITY, Plane => Plane(Vector3(0, 1, 0), 0),
                           Projection => Projection_IDENTITY, Color => Color(0.1, 0.2, 0.3, 1.0))[T]

function has_property(T, name::Symbol)
    x = try sample(T) catch; return false end
    return try getproperty(x, name); true catch; false end
end

"Julia counterpart of a C# member, or `nothing`."
function find_julia(m::CsMember)
    T = get(JULIA_TYPES, m.type, nothing)
    mods = Module[Godot, Godot.GD]
    m.type == "GD" && pushfirst!(mods, Godot.GD)
    m.type == "Mathf" && pushfirst!(mods, Godot.Mathf)
    # Constants and static properties of value types: `Vector2_ZERO`, `Color_ALICE_BLUE`.
    if T !== nothing && (m.kind === :const || (m.static && m.kind in (:property, :field)))
        c = Symbol(string(nameof(T)), "_", get(CONST_RENAMED, m.name, uppercase(snake(m.name))))
        isdefined(Godot, c) && return string(c)
    end
    for n in candidates(m)
        if m.type in ("GD", "Mathf")
            for mod in mods
                isdefined(mod, n) && return "$(nameof(mod)).$n"
            end
            continue
        end
        T === nothing && (resolve(n) === nothing ? continue : return string(n))
        if m.kind in (:field, :property) && !m.static && has_property(T, n)
            return "x.$n"
        end
        f = resolve(n, mods)
        f === nothing && continue
        # Generic C# methods (`GetNode<T>`) need the typed Julia form `f(T, x, ...)`; a concrete type argument keeps
        # singleton dispatch such as `instantiate(::Type{ClassDB}, ...)` from matching.
        TA = Type{m.name == "Load" ? Godot.Resource : Godot.Node}
        if m.generic
            if m.static
                any(mod -> isdefined(mod, n) && applies(getglobal(mod, n), Tuple{TA, Vararg{Any}}), (Godot.GD, Godot)) &&
                    return "$n(T, ...)"
            else
                applies(f, Tuple{TA, T, Vararg{Any}}) && return "$n(T, x, ...)"
            end
            continue
        end
        if m.extension
            recv = get(RECEIVERS, m.receiver, T)
            applies(f, Tuple{recv, Vararg{Any}}) && return "$n(x, ...)"
        elseif m.static
            applies(f, Tuple{Type{T}, Vararg{Any}}) && return "$n($(nameof(T)), ...)"
            m.type in VALUE_TYPES || (applies(f, Tuple{Vararg{Any}}) && return "$n(...)")
        else
            applies(f, Tuple{T, Vararg{Any}}) && return "$n(x, ...)"
        end
    end
    # Variant conversions: `AsInt32()`, `CreateFromVector2(...)`, `From(...)` → `convert` / `Variant(x)`.
    if m.type == "Variant" && occursin(r"^(As|CreateFrom|From)", m.name)
        return startswith(m.name, "As") ? "convert(T, v)" : "Variant(x)"
    end
    return nothing
end

# --- Report --------------------------------------------------------------------------------------------------------

const FILES = ["Aabb.cs", "Basis.cs", "Color.cs", "Colors.cs", "Plane.cs", "Projection.cs", "Quaternion.cs", "Rect2.cs",
               "Rect2I.cs", "Rid.cs", "Transform2D.cs", "Transform3D.cs", "Vector2.cs", "Vector2I.cs", "Vector3.cs",
               "Vector3I.cs", "Vector4.cs", "Vector4I.cs", "Callable.cs", "Callable.generics.cs", "Signal.cs",
               "StringName.cs", "NodePath.cs", "Variant.cs", "GD.cs", "Mathf.cs", "MathfEx.cs", "Array.cs",
               "Dictionary.cs", "StringExtensions.cs", "GodotObject.base.cs",
               joinpath("Extensions", "GodotObjectExtensions.cs"), joinpath("Extensions", "NodeExtensions.cs"),
               joinpath("Extensions", "PackedSceneExtensions.cs"), joinpath("Extensions", "ResourceLoaderExtensions.cs")]

function main()
    dir = source_dir()
    verbose = "--verbose" in ARGS
    missing_ = Tuple{CsMember, String}[]
    found = 0
    excluded = 0
    seen = Set{Tuple{String, String}}()
    for f in FILES
        path = joinpath(dir, f)
        isfile(path) || (println("skipped (not found): ", f); continue)
        for m in parse_cs(path)
            key = (m.type, m.name)
            key in seen && continue   # overloads
            push!(seen, key)
            if haskey(EXCLUDED, m.name)
                excluded += 1
                continue
            end
            j = find_julia(m)
            if j === nothing
                push!(missing_, (m, f))
            else
                found += 1
                verbose && println("  ok   $(m.type).$(m.name) -> $j")
            end
        end
    end
    println("GodotSharp $TAG vs Julia Godot: $found found, $excluded excluded by design, $(length(missing_)) missing")
    for (m, f) in missing_
        println("MISSING  $(m.type).$(m.name)  ($(m.static ? "static " : "")$(m.kind)$(m.generic ? ", generic" : ""); $f:$(m.line))")
    end
    return isempty(missing_)
end

ok = main()
"--strict" in ARGS && exit(ok ? 0 : 1)
