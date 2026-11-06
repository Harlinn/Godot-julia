# GDArray / GDArray{T} as AbstractVector with reference semantics.
# Ported from GodotSharp/Core/Array.cs (MIT, Godot contributors).

Base.IndexStyle(::Type{<:GDArray}) = IndexLinear()

"Copy of `x` suitable for storing in a container with element type `T` (Julia-side type enforcement)."
_element(::Type{Any}, x) = x
_element(::Type{T}, x) where {T} = convert(T, x)
_element(::Type{T}, x) where {T <: GodotObject} =
    x === nothing || x isa T ? x : throw(ArgumentError("cannot store a $(typeof(x)) in a container of $T"))

function _set_typed!(a::GDArray{T}) where {T}
    T === Any && return a
    vt, class = typed_info(T)
    script = Ref(FFI.construct(RawVariant))
    GC.@preserve a script FFI.array_set_typed(Internals.raw_ptr(a), vt, FFI.string_name_ptr(class), script)
    return a
end

GDArray() = GDArray{Any}()
GDArray{T}() where {T} = _set_typed!(GDArray{T}(FFI.construct(RawArray)))
GDArray(items::Union{AbstractVector, Tuple}) = GDArray{Any}(items)
function GDArray{T}(items::Union{AbstractVector, Tuple}) where {T}
    a = GDArray{T}()
    for x in items
        push!(a, x)
    end
    return a
end

function _array_typed_info(raw::RawArray)
    r = Ref(raw)
    GC.@preserve r begin
        p = Base.unsafe_convert(Ptr{Cvoid}, r)
        vt = Internals.builtin_call(Int64, :Array, :get_typed_builtin, p)
        class = Internals.take_string_name(Internals.builtin_call(RawStringName, :Array, :get_typed_class_name, p))
    end
    return Int32(vt), class
end

function _typed_matches(::Type{T}, vt::Int32, class::Symbol) where {T}
    T === Any && return true
    tvt, _ = typed_info(T)
    tvt == vt || return false
    return vt != FFI.GDEXTENSION_VARIANT_TYPE_OBJECT || element_type(vt, class) <: T
end

"Wrap an owned raw Array as `A`, checking that typed arrays match the requested element type."
_wrap_array(::Type{GDArray}, raw::RawArray) = GDArray{element_type(_array_typed_info(raw)...)}(raw)
function _wrap_array(::Type{GDArray{T}}, raw::RawArray) where {T}
    vt, class = _array_typed_info(raw)
    if !_typed_matches(T, vt, class)
        FFI.destroy!(raw)
        throw(ArgumentError("the Array holds $(element_type(vt, class)) elements, not $T"))
    end
    return GDArray{T}(raw)
end
Internals.take_array(::Type{A}, raw::RawArray) where {A <: GDArray} = _wrap_array(A, raw)

"Borrowed Variant stored at index `i` (1-based)."
_slot_variant(a::GDArray, i::Integer) =
    GC.@preserve a unsafe_load(Ptr{RawVariant}(FFI.array_operator_index_const(Internals.raw_ptr(a), i - 1)))

_check_writable(a) = is_read_only(a) && throw(ArgumentError("cannot modify a read-only $(nameof(typeof(a)))"))

function Base.size(a::GDArray)
    return (Int(GC.@preserve a Internals.builtin_call(Int64, :Array, :size, Internals.raw_ptr(a))),)
end

Base.@propagate_inbounds function Base.getindex(a::GDArray{T}, i::Int) where {T}
    @boundscheck checkbounds(a, i)
    return Internals.from_variant(T, _slot_variant(a, i))
end

Base.@propagate_inbounds function Base.setindex!(a::GDArray{T}, x, i::Int) where {T}
    @boundscheck checkbounds(a, i)
    _check_writable(a)
    y = _element(T, x)
    GC.@preserve a Internals.assign_variant_slot!(FFI.array_operator_index(Internals.raw_ptr(a), i - 1), y)
    return a
end

Base.push!(a::GDArray{T}, x) where {T} = (_check_writable(a); push_back(a, _element(T, x)); a)
Base.pushfirst!(a::GDArray{T}, x) where {T} = (_check_writable(a); push_front(a, _element(T, x)); a)
function Base.append!(a::GDArray, items)
    for x in items
        push!(a, x)
    end
    return a
end
function Base.pop!(a::GDArray{T}) where {T}
    isempty(a) && throw(ArgumentError("array must be non-empty"))
    _check_writable(a)
    return _element(T, pop_back(a))
end
function Base.popfirst!(a::GDArray{T}) where {T}
    isempty(a) && throw(ArgumentError("array must be non-empty"))
    _check_writable(a)
    return _element(T, pop_front(a))
end
function Base.insert!(a::GDArray{T}, i::Integer, x) where {T}
    1 <= i <= length(a) + 1 || throw(BoundsError(a, i))
    _check_writable(a)
    insert(a, i - 1, _element(T, x))
    return a
end
function Base.deleteat!(a::GDArray, i::Integer)
    checkbounds(a, i)
    _check_writable(a)
    remove_at(a, i - 1)
    return a
end
Base.resize!(a::GDArray, n::Integer) = (_check_writable(a); resize(a, n); a)
Base.empty!(a::GDArray) = (_check_writable(a); clear(a); a)

_duplicate(a::GDArray{T}, deep::Bool) where {T} =
    GDArray{T}(GC.@preserve a Internals.builtin_call(RawArray, :Array, :duplicate, Internals.raw_ptr(a), deep))
"Shallow copy (Godot `duplicate()`): a new Array holding the same elements."
Base.copy(a::GDArray) = _duplicate(a, false)
Base.deepcopy_internal(a::GDArray, ::IdDict) = _duplicate(a, true)

Base.convert(::Type{GDArray{T}}, v::AbstractVector) where {T} = GDArray{T}(v)
Base.convert(::Type{GDArray}, v::AbstractVector) = GDArray(v)
Base.convert(::Type{GDArray{T}}, a::GDArray{T}) where {T} = a
Base.convert(::Type{GDArray}, a::GDArray) = a
