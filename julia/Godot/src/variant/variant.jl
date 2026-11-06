# Variant, typed Variant conversions and the Variant-compatible type trait.
# Ported from GodotSharp/Core/Variant.cs and NativeInterop/VariantUtils*.cs, Marshaling.cs (MIT, Godot contributors).

using .FFI: RawVariant, RawArray, RawDictionary, RawString, RawStringName, RawNodePath, RawCallable, RawSignal, RawRID

const MathType = Union{MATH_TYPES...}
const _VariantInt = Base.BitInteger
const _VariantFloat = Union{Float16, Float32, Float64}

"Thrown when a Variant cannot be converted to the requested Julia type."
struct VariantConversionError <: Exception
    target::Type
    variant_type::Int32
end
Base.showerror(io::IO, e::VariantConversionError) =
    print(io, "VariantConversionError: cannot convert a Variant holding ", VariantType(e.variant_type), " to ", e.target)
@noinline _conv_error(T, vt) = throw(VariantConversionError(T, vt))

@inline _vt(v::RawVariant) = FFI.variant_type(v)

# --- Variant-compatible types ([MustBeVariant] equivalent) --------------------------------------------------------

"""
    isvarianttype(T) -> Bool

`true` if values of type `T` can be stored in a Godot Variant (C#'s `[MustBeVariant]` constraint): `Bool`, fixed-size
integers and floats, strings, `Symbol` (StringName), `NodePath`, `RID`, the math builtins, `Callable`, `Signal`,
`GodotObject` subtypes, enums, `GDArray`, `GDDictionary`, packed arrays, `Variant`, `nothing`, and `Vector{T}` of
Variant-compatible `T` (packed arrays for packable `T`, like C#'s `T[]`).
"""
isvarianttype(::Type) = false
isvarianttype(::Type{<:Union{Bool, _VariantInt, _VariantFloat, AbstractString, Symbol, NodePath, RID, MathType,
                             Callable, Signal, GodotObject, GodotEnum, GDArray, GDDictionary, PackedArray, Variant,
                             Nothing}}) = true
isvarianttype(::Type{Vector{T}}) where {T} = isvarianttype(T)
isvarianttype(::Type{<:Base.Enum}) = true
isvarianttype(::Type{Union{Nothing, T}}) where {T <: GodotObject} = true
isvarianttype(::Type{Any}) = true

"Packed array type used for `Vector{T}` (`nothing` when `T` is not packable)."
packed_for(::Type) = nothing
packed_for(::Type{UInt8}) = PackedByteArray
packed_for(::Type{Int32}) = PackedInt32Array
packed_for(::Type{Int64}) = PackedInt64Array
packed_for(::Type{Float32}) = PackedFloat32Array
packed_for(::Type{Float64}) = PackedFloat64Array
packed_for(::Type{String}) = PackedStringArray
packed_for(::Type{Vector2}) = PackedVector2Array
packed_for(::Type{Vector3}) = PackedVector3Array
packed_for(::Type{Vector4}) = PackedVector4Array
packed_for(::Type{Color}) = PackedColorArray

# --- Typed container element info --------------------------------------------------------------------------------

"Godot class name of a Julia class type (`GodotObject` → `:Object`)."
godot_class_name(::Type{T}) where {T <: GodotObject} = (S = isabstracttype(T) ? T : supertype(T); S === GodotObject ? :Object : nameof(S))

"`(variant_type, class_name)` describing the elements of a typed container with Julia element type `T`."
typed_info(::Type{Any}) = (FFI.GDEXTENSION_VARIANT_TYPE_NIL, Symbol(""))
typed_info(::Type{Bool}) = (FFI.GDEXTENSION_VARIANT_TYPE_BOOL, Symbol(""))
typed_info(::Type{<:Union{_VariantInt, GodotEnum, Base.Enum}}) = (FFI.GDEXTENSION_VARIANT_TYPE_INT, Symbol(""))
typed_info(::Type{<:_VariantFloat}) = (FFI.GDEXTENSION_VARIANT_TYPE_FLOAT, Symbol(""))
typed_info(::Type{<:AbstractString}) = (FFI.GDEXTENSION_VARIANT_TYPE_STRING, Symbol(""))
typed_info(::Type{Symbol}) = (FFI.GDEXTENSION_VARIANT_TYPE_STRING_NAME, Symbol(""))
typed_info(::Type{NodePath}) = (FFI.GDEXTENSION_VARIANT_TYPE_NODE_PATH, Symbol(""))
typed_info(::Type{RID}) = (FFI.GDEXTENSION_VARIANT_TYPE_RID, Symbol(""))
typed_info(::Type{Callable}) = (FFI.GDEXTENSION_VARIANT_TYPE_CALLABLE, Symbol(""))
typed_info(::Type{Signal}) = (FFI.GDEXTENSION_VARIANT_TYPE_SIGNAL, Symbol(""))
typed_info(::Type{<:GDArray}) = (FFI.GDEXTENSION_VARIANT_TYPE_ARRAY, Symbol(""))
typed_info(::Type{<:GDDictionary}) = (FFI.GDEXTENSION_VARIANT_TYPE_DICTIONARY, Symbol(""))
typed_info(::Type{PackedArray{T, R}}) where {T, R} = (FFI.variant_type(R), Symbol(""))
typed_info(::Type{T}) where {T <: MathType} = (FFI.variant_type(T), Symbol(""))
typed_info(::Type{T}) where {T <: GodotObject} = (FFI.GDEXTENSION_VARIANT_TYPE_OBJECT, godot_class_name(T))
typed_info(::Type{T}) where {T} = throw(ArgumentError("$T is not a Variant-compatible element type"))

"Julia element type for an engine typed container (inverse of `typed_info`)."
function element_type(vt::Integer, class::Symbol)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_NIL && return Any
    vt == FFI.GDEXTENSION_VARIANT_TYPE_BOOL && return Bool
    vt == FFI.GDEXTENSION_VARIANT_TYPE_INT && return Int64
    vt == FFI.GDEXTENSION_VARIANT_TYPE_FLOAT && return Float64
    vt == FFI.GDEXTENSION_VARIANT_TYPE_STRING && return String
    vt == FFI.GDEXTENSION_VARIANT_TYPE_STRING_NAME && return Symbol
    vt == FFI.GDEXTENSION_VARIANT_TYPE_NODE_PATH && return NodePath
    vt == FFI.GDEXTENSION_VARIANT_TYPE_RID && return RID
    vt == FFI.GDEXTENSION_VARIANT_TYPE_CALLABLE && return Callable
    vt == FFI.GDEXTENSION_VARIANT_TYPE_SIGNAL && return Signal
    vt == FFI.GDEXTENSION_VARIANT_TYPE_ARRAY && return GDArray{Any}
    vt == FFI.GDEXTENSION_VARIANT_TYPE_DICTIONARY && return GDDictionary{Any, Any}
    if vt == FFI.GDEXTENSION_VARIANT_TYPE_OBJECT
        W = get(Internals.CLASS_WRAPPERS, class, nothing)
        return W === nothing ? GodotObject : supertype(W)
    end
    for T in MATH_TYPES
        FFI.variant_type(T) == vt && return T
    end
    for P in PACKED_TYPES
        FFI.variant_type(raw_type(P)) == vt && return P
    end
    return Any
end

# --- Julia → Variant ---------------------------------------------------------------------------------------------

Internals.to_variant(x::Variant) = FFI.construct(RawVariant, x.raw)
Internals.to_variant(x::Base.Enum) = FFI.to_variant(Int64(Integer(x)))
function Internals.to_variant(x::Vector{T}) where {T}
    P = packed_for(T)
    P === nothing && return (a = Internals.new_array(x); try FFI.to_variant(a) finally FFI.destroy!(a) end)
    p = Internals.new_packed(raw_type(P), x)
    try
        return FFI.to_variant(p)
    finally
        FFI.destroy!(p)
    end
end

"""
    to_variant!(dst::Ptr{RawVariant}, x)

Write an owned Variant holding `x` into the uninitialized slot `dst` (marshalling entry point for script instances).
"""
to_variant!(dst::Ptr{RawVariant}, x) = (unsafe_store!(dst, Internals.to_variant(x)); nothing)

# --- Variant → Julia (typed) -------------------------------------------------------------------------------------

"""
    from_variant(T, v::RawVariant) / from_variant(T, src::Ptr{RawVariant})

Convert a borrowed Variant to `T`, throwing [`VariantConversionError`](@ref) when the Variant holds an incompatible type.
Integers and floats widen/narrow with checked conversion; Strings, StringNames and NodePaths convert into each other.
"""
from_variant(::Type{T}, src::Ptr{RawVariant}) where {T} = Internals.from_variant(T, unsafe_load(src))
from_variant(::Type{T}, v::RawVariant) where {T} = Internals.from_variant(T, v)

Internals.from_variant(::Type{Any}, v::RawVariant) = Internals.from_variant(v)
Internals.from_variant(::Type{Variant}, v::RawVariant) = Variant(FFI.construct(RawVariant, v))
Internals.from_variant(::Type{Nothing}, v::RawVariant) = (vt = _vt(v); vt == FFI.GDEXTENSION_VARIANT_TYPE_NIL ? nothing : _conv_error(Nothing, vt))
function Internals.from_variant(::Type{Bool}, v::RawVariant)
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_BOOL || _conv_error(Bool, vt)
    return FFI.from_variant(Bool, v)
end
function Internals.from_variant(::Type{T}, v::RawVariant) where {T <: _VariantInt}
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_INT || _conv_error(T, vt)
    return convert(T, FFI.from_variant(Int64, v))
end
function Internals.from_variant(::Type{T}, v::RawVariant) where {T <: _VariantFloat}
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_FLOAT && return T(FFI.from_variant(Float64, v))
    vt == FFI.GDEXTENSION_VARIANT_TYPE_INT && return T(FFI.from_variant(Int64, v))
    _conv_error(T, vt)
end
function Internals.from_variant(::Type{String}, v::RawVariant)
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_STRING && return Internals.take_string(FFI.from_variant(RawString, v))
    vt == FFI.GDEXTENSION_VARIANT_TYPE_STRING_NAME && return Internals.take_string_name_raw(FFI.from_variant(RawStringName, v))
    vt == FFI.GDEXTENSION_VARIANT_TYPE_NODE_PATH && return Internals.take_node_path(FFI.from_variant(RawNodePath, v)).path
    _conv_error(String, vt)
end
function Internals.from_variant(::Type{Symbol}, v::RawVariant)
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_STRING_NAME && return Internals.take_string_name(FFI.from_variant(RawStringName, v))
    vt == FFI.GDEXTENSION_VARIANT_TYPE_STRING && return Symbol(Internals.take_string(FFI.from_variant(RawString, v)))
    _conv_error(Symbol, vt)
end
function Internals.from_variant(::Type{NodePath}, v::RawVariant)
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_NODE_PATH && return Internals.take_node_path(FFI.from_variant(RawNodePath, v))
    vt == FFI.GDEXTENSION_VARIANT_TYPE_STRING && return NodePath(Internals.take_string(FFI.from_variant(RawString, v)))
    _conv_error(NodePath, vt)
end
function Internals.from_variant(::Type{RID}, v::RawVariant)
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_RID || _conv_error(RID, vt)
    return RID(FFI.from_variant(RawRID, v))
end
function Internals.from_variant(::Type{T}, v::RawVariant) where {T <: MathType}
    vt = _vt(v)
    vt == FFI.variant_type(T) || _conv_error(T, vt)
    return Internals.variant_to_bits(T, vt, v)
end
function Internals.from_variant(::Type{T}, v::RawVariant) where {T <: GodotEnum}
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_INT || _conv_error(T, vt)
    return T(FFI.from_variant(Int64, v))
end
function Internals.from_variant(::Type{T}, v::RawVariant) where {T <: Base.Enum}
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_INT || _conv_error(T, vt)
    return T(FFI.from_variant(Int64, v))
end
for (T, R, VT) in ((:Callable, :RawCallable, :GDEXTENSION_VARIANT_TYPE_CALLABLE), (:Signal, :RawSignal, :GDEXTENSION_VARIANT_TYPE_SIGNAL))
    @eval function Internals.from_variant(::Type{$T}, v::RawVariant)
        vt = _vt(v)
        vt == FFI.$VT || _conv_error($T, vt)
        return $T(FFI.from_variant($R, v))
    end
end
function Internals.from_variant(::Type{P}, v::RawVariant) where {T, R, P <: PackedArray{T, R}}
    vt = _vt(v)
    vt == FFI.variant_type(R) || _conv_error(P, vt)
    return P(FFI.from_variant(R, v))
end
function Internals.from_variant(::Type{T}, v::RawVariant) where {T <: GodotObject}
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_NIL && return nothing
    vt == FFI.GDEXTENSION_VARIANT_TYPE_OBJECT || _conv_error(T, vt)
    obj = Internals.take_object(GodotObject, Internals.variant_to_bits(Ptr{Cvoid}, vt, v), false)
    obj === nothing || obj isa T || throw(ArgumentError("Variant holds a $(nameof(supertype(typeof(obj)))), not a $T"))
    return obj::Union{Nothing, T}
end
function Internals.from_variant(::Type{A}, v::RawVariant) where {A <: GDArray}
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_ARRAY || _conv_error(A, vt)
    return _wrap_array(A, FFI.from_variant(RawArray, v))
end
function Internals.from_variant(::Type{D}, v::RawVariant) where {D <: GDDictionary}
    vt = _vt(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_DICTIONARY || _conv_error(D, vt)
    return _wrap_dictionary(D, FFI.from_variant(RawDictionary, v))
end
function Internals.from_variant(::Type{Vector{T}}, v::RawVariant) where {T}
    vt = _vt(v)
    P = packed_for(T)
    if P !== nothing && vt == FFI.variant_type(raw_type(P))
        return Vector{T}(Internals.from_variant(P, v))
    end
    vt == FFI.GDEXTENSION_VARIANT_TYPE_ARRAY || _conv_error(Vector{T}, vt)
    a = Internals.from_variant(GDArray{Any}, v)
    return T[Internals.from_variant(T, _slot_variant(a, i)) for i in 1:length(a)]
end
function Internals.from_variant(::Type{Dict{K, V}}, v::RawVariant) where {K, V}
    d = Internals.from_variant(GDDictionary{Any, Any}, v)
    return Dict{K, V}(convert(K, k) => convert(V, x) for (k, x) in d)
end
function Internals.from_variant(::Type{T}, v::RawVariant) where {T}
    x = Internals.from_variant(v)
    x isa T || _conv_error(T, _vt(v))
    return x
end

# --- Variant -----------------------------------------------------------------------------------------------------

Variant() = Variant(FFI.construct(RawVariant))
Variant(x) = Variant(Internals.to_variant(x))
Variant(v::Variant) = Variant(FFI.construct(RawVariant, v.raw))

"The `VariantType` (`TYPE_INT`, `TYPE_OBJECT`, ...) of the value held by `v`."
variant_type(v::Variant) = VariantType(_vt(v.raw))
Base.convert(::Type{Variant}, x) = Variant(x)
Base.convert(::Type{Variant}, v::Variant) = v
Base.convert(::Type{T}, v::Variant) where {T} = Internals.from_variant(T, v.raw)
Base.convert(::Type{T}, v::Variant) where {T >: Nothing} = Internals.from_variant(T, v.raw)
Base.convert(::Type{Any}, v::Variant) = v
for T in (Bool, Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64, Float32, Float64, String, Symbol, NodePath,
          RID, Callable, Signal, MATH_TYPES...)
    @eval (::Type{$T})(v::Variant) = Internals.from_variant($T, v.raw)
end
(::Type{A})(v::Variant) where {A <: GDArray} = Internals.from_variant(A, v.raw)
(::Type{T})(v::Variant) where {T <: GodotObject} = Internals.from_variant(T, v.raw)
(::Type{D})(v::Variant) where {D <: GDDictionary} = Internals.from_variant(D, v.raw)
(::Type{P})(v::Variant) where {P <: PackedArray} = Internals.from_variant(P, v.raw)

"Julia value held by `v` (dynamic type)."
Base.getindex(v::Variant) = Internals.from_variant(v.raw)
Base.isnothing(v::Variant) = _vt(v.raw) == FFI.GDEXTENSION_VARIANT_TYPE_NIL
Base.:(==)(a::Variant, b::Variant) = _variant_equal(a.raw, b.raw)
Base.hash(v::Variant, h::UInt) = hash(FFI.variant_hash(Ref(v.raw)), hash(:Variant, h))
Base.string(v::Variant) = _stringify(v.raw)
Base.show(io::IO, v::Variant) = print(io, "Variant(", repr(v[]), ")")

function _variant_equal(a::RawVariant, b::RawVariant)
    r = Ref{RawVariant}()
    valid = Ref{UInt8}(0)
    FFI.variant_evaluate(FFI.GDEXTENSION_VARIANT_OP_EQUAL, Ref(a), Ref(b), r, valid)
    return Internals.take_variant(r[]) === true && valid[] != 0
end

"Godot's string conversion of a Variant (`str(x)` in GDScript)."
function _stringify(v::RawVariant)
    r = Ref{RawString}()
    FFI.variant_stringify(Ref(v), r)
    return Internals.take_string(r[])
end
