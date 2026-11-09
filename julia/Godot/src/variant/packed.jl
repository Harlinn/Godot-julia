# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Packed arrays as AbstractVector, with fast conversions and zero-copy views.
# Ported from GodotSharp/Core/NativeInterop/Marshaling.cs (packed array marshalling) (MIT, Godot contributors).

const PackedByteArray = PackedArray{UInt8, FFI.RawPackedByteArray}
const PackedInt32Array = PackedArray{Int32, FFI.RawPackedInt32Array}
const PackedInt64Array = PackedArray{Int64, FFI.RawPackedInt64Array}
const PackedFloat32Array = PackedArray{Float32, FFI.RawPackedFloat32Array}
const PackedFloat64Array = PackedArray{Float64, FFI.RawPackedFloat64Array}
const PackedStringArray = PackedArray{String, FFI.RawPackedStringArray}
const PackedVector2Array = PackedArray{Vector2, FFI.RawPackedVector2Array}
const PackedVector3Array = PackedArray{Vector3, FFI.RawPackedVector3Array}
const PackedColorArray = PackedArray{Color, FFI.RawPackedColorArray}
const PackedVector4Array = PackedArray{Vector4, FFI.RawPackedVector4Array}

const PACKED_TYPES = (PackedByteArray, PackedInt32Array, PackedInt64Array, PackedFloat32Array, PackedFloat64Array,
                      PackedStringArray, PackedVector2Array, PackedVector3Array, PackedColorArray, PackedVector4Array)

"Raw FFI type behind a packed array type."
raw_type(::Type{PackedArray{T, R}}) where {T, R} = R

for P in PACKED_TYPES
    R = raw_type(P)
    base = lowercase(replace(String(nameof(R))[4:end], r"(?<=[a-z0-9])(?=[A-Z])" => "_"))
    index, index_const = Symbol(base, "_operator_index"), Symbol(base, "_operator_index_const")
    @eval Internals.packed_type(::Type{$R}) = $P
    @eval Internals.packed_index_fns(::Type{$R}) = (FFI.$index, FFI.$index_const)
    @eval (::Type{$P})() = $P(FFI.construct($R))
    @eval (::Type{$P})(items::AbstractVector) = $P(Internals.new_packed($R, items))
end

builtin_name(::Type{PackedArray{T, R}}) where {T, R} = Symbol(String(nameof(R))[4:end])

Base.IndexStyle(::Type{<:PackedArray}) = IndexLinear()

function Base.size(p::PackedArray)
    n = GC.@preserve p Internals.builtin_call(Int64, builtin_name(typeof(p)), :size, Internals.raw_ptr(p))
    return (Int(n),)
end

Base.@propagate_inbounds function Base.getindex(p::PackedArray{T, R}, i::Int) where {T, R}
    @boundscheck checkbounds(p, i)
    _, index_const = Internals.packed_index_fns(R)
    return GC.@preserve p Internals.load_packed_element(T, index_const(Internals.raw_ptr(p), i - 1))
end

Base.@propagate_inbounds function Base.setindex!(p::PackedArray{T, R}, x, i::Int) where {T, R}
    @boundscheck checkbounds(p, i)
    index, _ = Internals.packed_index_fns(R)
    GC.@preserve p Internals.store_packed_element!(T, index(Internals.raw_ptr(p), i - 1), x)
    return p
end

_resize!(p::PackedArray, n::Integer) =
    (GC.@preserve p Internals.builtin_call(Int64, builtin_name(typeof(p)), :resize, Internals.raw_ptr(p), Int64(n)); p)
Base.resize!(p::PackedArray, n::Integer) = _resize!(p, n)
Base.push!(p::PackedArray{T}, x) where {T} = (n = length(p); _resize!(p, n + 1); @inbounds p[n + 1] = convert(T, x); p)
function Base.append!(p::PackedArray{T}, items) where {T}
    n = length(p)
    _resize!(p, n + length(items))
    for (i, x) in enumerate(items)
        @inbounds p[n + i] = convert(T, x)
    end
    return p
end
Base.empty!(p::PackedArray) = _resize!(p, 0)
function Base.insert!(p::PackedArray{T}, i::Integer, x) where {T}
    1 <= i <= length(p) + 1 || throw(BoundsError(p, i))
    insert(p, i - 1, convert(T, x))
    return p
end
function Base.deleteat!(p::PackedArray, i::Integer)
    checkbounds(p, i)
    remove_at(p, i - 1)
    return p
end
function Base.pop!(p::PackedArray)
    isempty(p) && throw(ArgumentError("packed array must be non-empty"))
    x = @inbounds p[end]
    _resize!(p, length(p) - 1)
    return x
end
"Shallow copy; Godot shares the buffer until either copy is written (copy-on-write)."
Base.copy(p::P) where {T, R, P <: PackedArray{T, R}} = P(FFI.construct(R, p.raw))

function Base.Vector{T}(p::PackedArray{T, R}) where {T, R}
    n = length(p)
    isbitstype(T) || return T[@inbounds(p[i]) for i in 1:n]
    v = Vector{T}(undef, n)
    if n > 0
        _, index_const = Internals.packed_index_fns(R)
        GC.@preserve p v unsafe_copyto!(pointer(v), Ptr{T}(index_const(Internals.raw_ptr(p), 0)), n)
    end
    return v
end
Base.Vector(p::PackedArray{T}) where {T} = Vector{T}(p)
Base.collect(p::PackedArray{T}) where {T} = Vector{T}(p)
Base.convert(::Type{Vector{T}}, p::PackedArray{T}) where {T} = Vector{T}(p)
Base.convert(::Type{P}, v::AbstractVector) where {P <: PackedArray} = P(v)
Base.convert(::Type{P}, p::P) where {P <: PackedArray} = p

"""
    unsafe_wrap(Array, p::PackedArray) -> Vector

Zero-copy view of the elements of `p` (isbits element types only). Writes go straight into Godot's buffer; obtaining the
view makes the buffer unique (copy-on-write). The view is invalid after `p` is resized, garbage collected, or copied
(including being passed to the engine, which shares the buffer); keep `p` alive with `GC.@preserve` while using it.
"""
function Base.unsafe_wrap(::Type{Array}, p::PackedArray{T, R}) where {T, R}
    isbitstype(T) || throw(ArgumentError("unsafe_wrap requires an isbits element type, not $T"))
    n = length(p)
    n == 0 && return T[]
    index, _ = Internals.packed_index_fns(R)
    return unsafe_wrap(Array, Ptr{T}(GC.@preserve p index(Internals.raw_ptr(p), 0)), n; own = false)
end

function Internals.new_packed(::Type{R}, items::Vector{T}) where {R <: FFI.RawBuiltin, T}
    P = Internals.packed_type(R)
    (eltype(P) === T && isbitstype(T)) || return invoke(Internals.new_packed, Tuple{Type{R}, AbstractVector}, R, items)
    r = Ref(FFI.construct(R))
    index, _ = Internals.packed_index_fns(R)
    GC.@preserve r items begin
        base = Base.unsafe_convert(Ptr{Cvoid}, r)
        Internals.builtin_call(Int64, builtin_name(P), :resize, base, Int64(length(items)))
        isempty(items) || unsafe_copyto!(Ptr{T}(index(base, 0)), pointer(items), length(items))
    end
    return r[]
end
