# Constructors, destructors and Variant conversions for opaque builtins.

const MAX_VARIANT_TYPES = 64
const DESTRUCTORS = fill(C_NULL, MAX_VARIANT_TYPES)
const VARIANT_FROM = fill(C_NULL, MAX_VARIANT_TYPES)
const VARIANT_TO = fill(C_NULL, MAX_VARIANT_TYPES)
const CONSTRUCTORS = Dict{Tuple{Int32, Int32}, Ptr{Cvoid}}()
const CONSTRUCTORS_LOCK = ReentrantLock()

@inline slot(vt::Int32) = Int(vt) + 1

function init_builtins!()
    for vt in Int32(1):Int32(GDEXTENSION_VARIANT_TYPE_VARIANT_MAX - 1)
        VARIANT_FROM[slot(vt)] = get_variant_from_type_constructor(vt)
        VARIANT_TO[slot(vt)] = get_variant_to_type_constructor(vt)
    end
    for T in RAW_BUILTINS
        has_destructor(T) && (DESTRUCTORS[slot(variant_type(T))] = variant_get_ptr_destructor(variant_type(T)))
    end
    return nothing
end

function reset_builtins!()
    fill!(DESTRUCTORS, C_NULL)
    fill!(VARIANT_FROM, C_NULL)
    fill!(VARIANT_TO, C_NULL)
    @lock CONSTRUCTORS_LOCK empty!(CONSTRUCTORS)
    return nothing
end

function constructor_ptr(vt::Int32, index::Int32)
    @lock CONSTRUCTORS_LOCK get!(CONSTRUCTORS, (vt, index)) do
        p = variant_get_ptr_constructor(vt, index)
        p == C_NULL && error("Godot has no constructor #$index for variant type $vt")
        p
    end
end

"Default-construct an owned value."
function construct(::Type{T}) where {T <: RawBuiltin}
    r = Ref{T}()
    ccall(constructor_ptr(variant_type(T), Int32(0)), Cvoid, (Ptr{Cvoid}, Ptr{Ptr{Cvoid}}), r, C_NULL)
    return r[]
end

"Construct an owned `T` from `src` (borrowed) using Godot's converting/copy constructor."
function construct(::Type{T}, src::S) where {T <: RawBuiltin, S <: RawBuiltin}
    r = Ref{T}()
    s = Ref(src)
    GC.@preserve s begin
        args = Ref(Base.unsafe_convert(Ptr{Cvoid}, s))
        ccall(constructor_ptr(variant_type(T), constructor_index(T, S)), Cvoid, (Ptr{Cvoid}, Ptr{Ptr{Cvoid}}), r, args)
    end
    return r[]
end

"Destroy an owned value; the bits must not be used afterwards."
function destroy!(x::T) where {T <: RawBuiltin}
    has_destructor(T) || return nothing
    ccall(DESTRUCTORS[slot(variant_type(T))], Cvoid, (Ptr{Cvoid},), Ref(x))
    return nothing
end

construct(::Type{RawVariant}) = (r = Ref{RawVariant}(); variant_new_nil(r); r[])
construct(::Type{RawVariant}, src::RawVariant) = (r = Ref{RawVariant}(); variant_new_copy(r, Ref(src)); r[])
destroy!(v::RawVariant) = (variant_destroy(Ref(v)); nothing)

"`GDEXTENSION_VARIANT_TYPE_*` of the value held by `v`."
variant_type(v::RawVariant) = variant_get_type(Ref(v))

variant_type(::Type{Bool}) = GDEXTENSION_VARIANT_TYPE_BOOL
variant_type(::Type{Int64}) = GDEXTENSION_VARIANT_TYPE_INT
variant_type(::Type{Float64}) = GDEXTENSION_VARIANT_TYPE_FLOAT

const VariantScalar = Union{Bool, Int64, Float64}

"Owned Variant holding a copy of `x` (`x` stays owned by the caller)."
function to_variant(x::T) where {T <: Union{RawBuiltin, VariantScalar}}
    r = Ref{RawVariant}()
    ccall(VARIANT_FROM[slot(variant_type(T))], Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}), r, Ref(x))
    return r[]
end

"Owned `T` extracted from `v` (borrowed). The Variant must hold exactly type `T`."
function from_variant(::Type{T}, v::RawVariant) where {T <: Union{RawBuiltin, VariantScalar}}
    actual = variant_type(v)
    actual == variant_type(T) || throw(ArgumentError("Variant holds type $actual, not $(variant_type(T)) ($T)"))
    r = Ref{T}()
    ccall(VARIANT_TO[slot(variant_type(T))], Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}), r, Ref(v))
    return r[]
end
