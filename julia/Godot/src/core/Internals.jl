# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

"""
    Godot.Internals

Marshaling, object wrapping and lifetime helpers used by the generated bindings. Not part of the public API.
"""
module Internals

using ..Godot: Godot, FFI, GodotObject, GodotEnum, GodotBitfield, NodePath, RID, GDArray, GDDictionary,
               Callable, Signal, PackedArray
using ..FFI: RawVariant, RawString, RawStringName, RawNodePath, RawArray, RawDictionary, RawCallable, RawSignal,
             RawRID

const StringNameLike = Union{Symbol, AbstractString}
const NodePathLike = Union{NodePath, AbstractString}

"Tag selecting the row-major constructor of `Basis`."
struct Rows end
const ROWS = Rows()

# --- Registries filled by generated code ---------------------------------------------------------

"Godot class name => concrete native wrapper type."
const CLASS_WRAPPERS = Dict{Symbol, DataType}()

struct SignalInfo
    name::Symbol
    args::Vector{Pair{Symbol, String}}
end

struct VirtualInfo
    name::Symbol
    args::Vector{Pair{Symbol, String}}
    ret::Union{String, Nothing}
    hash::Int64
    is_const::Bool
    is_required::Bool
end

const CLASS_SIGNALS = Dict{Symbol, Vector{SignalInfo}}()
const CLASS_VIRTUALS = Dict{Symbol, Vector{VirtualInfo}}()

"`((name, value), ...)` of an enum type (generated)."
function enum_values end
"Property names declared by a class itself (generated)."
class_property_names(::Type) = ()
"Engine singleton instance for a singleton class (generated)."
function singleton end

struct ReadOnlyPropertyError <: Exception
    class::String
    property::Symbol
end
Base.showerror(io::IO, e::ReadOnlyPropertyError) = print(io, "property ", e.property, " of ", e.class, " is read-only")

"Thrown when a wrapper is used after its native object was freed or the wrapper was disposed (C#: `ObjectDisposedException`)."
struct FreedObjectError <: Exception
    type::Type
end
Base.showerror(io::IO, e::FreedObjectError) = print(io, "FreedObjectError: cannot use a freed or disposed ", nameof(e.type), " object")

# --- Cached method binds and utility functions ---------------------------------------------------

"Per-call-site cached `MethodBind` (equivalent to C#'s cached method-bind statics)."
macro method_bind(class, method, hash)
    cache = Ref{Ptr{Cvoid}}(C_NULL)
    return quote
        p = $cache[]
        p == C_NULL ? ($cache[] = FFI.method_bind($class, $method, $hash)) : p
    end
end

"Per-call-site cached utility function pointer."
macro utility_function(name, hash)
    cache = Ref{Ptr{Cvoid}}(C_NULL)
    return quote
        p = $cache[]
        p == C_NULL ? ($cache[] = FFI.utility_function($name, $hash)) : p
    end
end

"Per-call-site cached builtin-type method pointer (`type` is the Godot builtin name, e.g. `\"Array\"`)."
macro builtin_method(type, method, hash)
    cache = Ref{Ptr{Cvoid}}(C_NULL)
    return quote
        p = $cache[]
        p == C_NULL ? ($cache[] = FFI.builtin_method(FFI.BUILTIN_VARIANT_TYPES[$type], $method, $hash)) : p
    end
end

"Call the vararg builtin method `method` on `self` through Variants (`Callable.call`, `Signal.emit`, ...)."
function builtin_varcall(self, method::Symbol, args...)
    sv = Ref(to_variant(self))
    vs = RawVariant[to_variant(a) for a in args]
    ptrs = Ptr{Cvoid}[pointer(vs, i) for i in eachindex(vs)]
    ret = Ref{RawVariant}()
    err = Ref(FFI.GDExtensionCallError(FFI.GDEXTENSION_CALL_OK, 0, 0))
    try
        GC.@preserve sv vs ptrs FFI.variant_call(sv, FFI.string_name_ptr(method), ptrs, length(vs), ret, err)
        if err[].error != FFI.GDEXTENSION_CALL_OK
            FFI.destroy!(ret[])
            throw(FFI.GodotCallError(err[].error, err[].argument, err[].expected))
        end
        return take_variant(ret[])
    finally
        FFI.destroy!(sv[])
        foreach(FFI.destroy!, vs)
    end
end

const BUILTIN_FNS = Dict{Tuple{Symbol, Symbol}, Ptr{Cvoid}}()
const BUILTIN_FNS_LOCK = ReentrantLock()

function builtin_fn(type::Symbol, method::Symbol)
    @lock BUILTIN_FNS_LOCK get!(BUILTIN_FNS, (type, method)) do
        FFI.builtin_method(FFI.BUILTIN_VARIANT_TYPES[String(type)], method, FFI.builtin_method_hash(type, method))
    end
end

"Call builtin method `type.method` on the value stored at `base`."
builtin_call(::Type{R}, type::Symbol, method::Symbol, base::Ptr{Cvoid}, args...) where {R} =
    FFI.builtin_ptrcall(R, builtin_fn(type, method), base, args...)

"Call a vararg utility function with Variant arguments."
function utility_varcall(::Type{R}, fn::Ptr{Cvoid}, args::Vector{RawVariant}) where {R}
    ptrs = Ptr{Cvoid}[pointer(args, i) for i in eachindex(args)]
    ret = R === Nothing ? nothing : FFI.needs_initialized_return(R) ? Ref(FFI.construct(R)) : Ref{R}()
    GC.@preserve args ptrs ret ccall(fn, Cvoid, (Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Cint),
                                     ret === nothing ? C_NULL : ret, ptrs, length(args))
    return ret === nothing ? nothing : ret[]
end

# --- Deferred releases -------------------------------------------------------------------------
# Finalizers may run on any thread in the middle of arbitrary code, so they only enqueue work; the queue is
# flushed at safe points (runtime entry points now, every frame once the main-thread scheduler exists).

struct PendingUnref
    ptr::Ptr{Cvoid}
end

const PENDING = Any[]
const PENDING_LOCK = Threads.SpinLock()

function enqueue_release!(x)
    lock(PENDING_LOCK)
    try
        push!(PENDING, x)
    finally
        unlock(PENDING_LOCK)
    end
    return nothing
end

finalize_builtin(x) = enqueue_release!(x.raw)
function finalize_object(o)
    p = getfield(o, :__ptr)
    p == C_NULL && return nothing
    setfield!(o, :__ptr, C_NULL)
    enqueue_release!(PendingUnref(p))
    return nothing
end

release!(r::PendingUnref) = Godot.release_reference!(r.ptr)
release!(raw) = FFI.destroy!(raw)

"Release everything finalizers queued. Call only from safe points."
function flush_releases!()
    FFI.INITIALIZED[] || return 0
    lock(PENDING_LOCK)
    items = try
        isempty(PENDING) ? Any[] : splice!(PENDING, eachindex(PENDING))
    finally
        unlock(PENDING_LOCK)
    end
    foreach(release!, items)
    return length(items)
end

# --- Objects -----------------------------------------------------------------------------------

@inline function native_ptr(o::GodotObject)
    p = getfield(o, :__ptr)
    p == C_NULL && throw(FreedObjectError(typeof(o)))
    return p
end

object_ptr(::Nothing) = C_NULL
object_ptr(o::GodotObject) = native_ptr(o)

reference_object(p::Ptr{Cvoid}) = FFI.ptrcall(Bool, FFI.method_bind(:RefCounted, :reference), p)
reference_count(p::Ptr{Cvoid}) = FFI.ptrcall(Int64, FFI.method_bind(:RefCounted, :get_reference_count), p)

function unreference_object(p::Ptr{Cvoid})
    FFI.ptrcall(Bool, FFI.method_bind(:RefCounted, :unreference), p) && FFI.object_destroy(p)
    return nothing
end

const WRAPPER_BY_CLASS_NAME = Dict{UInt64, DataType}()
const WRAPPER_LOCK = ReentrantLock()

"Register generated classes (called by `Godot` at load time and by `GodotEditor.__init__`)."
function register_classes!(wrappers, signals, virtuals)
    @lock WRAPPER_LOCK begin
        merge!(CLASS_WRAPPERS, wrappers)
        merge!(CLASS_SIGNALS, signals)
        merge!(CLASS_VIRTUALS, virtuals)
        # Classes seen before registration were resolved to a known ancestor.
        empty!(WRAPPER_BY_CLASS_NAME)
    end
    return nothing
end

function parent_class(name::Symbol)
    sn = FFI.new_string_name(name)
    try
        r = FFI.ptrcall(RawStringName, FFI.method_bind(:ClassDB, :get_parent_class), FFI.singleton(:ClassDB), sn)
        return Symbol(take_string_name_raw(r))
    finally
        FFI.destroy!(sn)
    end
end

function resolve_wrapper(name::Symbol)
    while !isempty(String(name))
        T = @lock WRAPPER_LOCK get(CLASS_WRAPPERS, name, nothing)
        T === nothing || return T
        name = parent_class(name)
    end
    return Godot.Native.GodotObject
end

"Most-derived generated wrapper type for the object at `p`."
function wrapper_type(p::Ptr{Cvoid})
    r = Ref{RawStringName}()
    FFI.object_get_class_name(p, FFI.LIBRARY[], r)
    name = r[]
    try
        return @lock WRAPPER_LOCK get!(WRAPPER_BY_CLASS_NAME, name._data[1]) do
            resolve_wrapper(Symbol(FFI.julia_string(name)))
        end
    finally
        FFI.destroy!(name)
    end
end

"""
    take_object(C, p, owned) -> Union{Nothing, C}

The unique Julia wrapper of the object at `p` (see `Godot.wrap_object`). For `RefCounted` objects `owned` says
whether the caller already holds a reference that the wrapper adopts.
"""
function take_object(::Type{C}, p::Ptr{Cvoid}, owned::Bool) where {C}
    p == C_NULL && return nothing
    return Godot.wrap_object(p, owned)::C
end

"Construct a new engine object of class `class` wrapped as `T`."
function construct_object(::Type{T}, class::Symbol) where {T}
    # RefCounted objects come with their first reference taken, which the wrapper adopts.
    p = FFI.classdb_construct_object3(FFI.string_name_ptr(class))
    p == C_NULL && error("Godot could not construct a $class")
    w = Godot.wrap_object(p, T <: Godot.RefCounted; type = T)::T
    # Required after classdb_construct_object* (Controls set up their theme caches here; godot-cpp's memnew does too).
    Godot.notification(w, Godot.GodotObject_NOTIFICATION_POSTINITIALIZE)
    return w
end

mutable struct SingletonCache{T}
    name::Symbol
    value::T
    SingletonCache{T}(name::Symbol) where {T} = new{T}(name)
end

@inline get_singleton!(c::SingletonCache{T}) where {T} =
    isdefined(c, :value) ? c.value : (c.value = Godot.wrap_object(FFI.singleton(c.name), false; type = T)::T)

# --- Strings and enums ---------------------------------------------------------------------------

take_string(r::RawString) = (s = FFI.julia_string(r); FFI.destroy!(r); s)
take_string_name_raw(r::RawStringName) = (s = FFI.julia_string(r); FFI.destroy!(r); s)
take_string_name(r::RawStringName) = Symbol(take_string_name_raw(r))
new_node_path(p::NodePath) = FFI.new_node_path(p.path)
new_node_path(p::AbstractString) = FFI.new_node_path(p)
take_node_path(r::RawNodePath) = (s = FFI.julia_string(r); FFI.destroy!(r); NodePath(s))

enum_value(x::GodotEnum) = x.value
enum_value(x::Integer) = Int64(x)

# --- Containers (Julia collection semantics are in src/variant/) ---------------------------------------------------

raw_ptr(x) = Ptr{Cvoid}(pointer_from_objref(x))

new_array(::Nothing) = FFI.construct(RawArray)
new_array(a::GDArray) = FFI.construct(RawArray, a.raw)
function new_array(items::Union{AbstractVector, Tuple})
    r = Ref(FFI.construct(RawArray))
    GC.@preserve r for x in items
        v = to_variant(x)
        try
            builtin_call(Nothing, :Array, :push_back, Base.unsafe_convert(Ptr{Cvoid}, r), v)
        finally
            FFI.destroy!(v)
        end
    end
    return r[]
end
take_array(r::RawArray) = GDArray(r)

new_dictionary(::Nothing) = FFI.construct(RawDictionary)
new_dictionary(d::GDDictionary) = FFI.construct(RawDictionary, d.raw)
function new_dictionary(items::AbstractDict)
    r = Ref(FFI.construct(RawDictionary))
    GC.@preserve r for (k, x) in items
        set_dictionary_slot!(Base.unsafe_convert(Ptr{Cvoid}, r), k, x)
    end
    return r[]
end
take_dictionary(r::RawDictionary) = GDDictionary(r)

function set_dictionary_slot!(dict::Ptr{Cvoid}, key, value)
    kv = Ref(to_variant(key))
    vv = Ref(to_variant(value))
    try
        slot = FFI.dictionary_operator_index(dict, kv)
        FFI.variant_destroy(slot)
        FFI.variant_new_copy(slot, vv)
    finally
        FFI.destroy!(kv[])
        FFI.destroy!(vv[])
    end
    return nothing
end

"Copy `value` into the Variant slot at `slot` (which must hold an initialized Variant)."
function assign_variant_slot!(slot::Ptr{Cvoid}, value)
    vv = Ref(to_variant(value))
    try
        FFI.variant_destroy(slot)
        FFI.variant_new_copy(slot, vv)
    finally
        FFI.destroy!(vv[])
    end
    return nothing
end

new_callable(::Nothing) = FFI.construct(RawCallable)
new_callable(c::Callable) = FFI.construct(RawCallable, c.raw)
function new_callable(f)
    isempty(methods(f)) && throw(ArgumentError("cannot convert a $(typeof(f)) to a Godot Callable: it is not callable"))
    return FFI.construct(RawCallable, Godot.Callable(f).raw)
end
take_callable(r::RawCallable) = Callable(r)

new_signal(::Nothing) = FFI.construct(RawSignal)
new_signal(s::Signal) = FFI.construct(RawSignal, s.raw)
new_signal(x) = throw(ArgumentError("cannot convert $(typeof(x)) to a Godot Signal"))
take_signal(r::RawSignal) = Signal(r)

function packed_type end      # Raw packed type => PackedArray alias (defined with the aliases)
function packed_index_fns end # Raw packed type => (index, index_const) interface functions

new_packed(::Type{R}, ::Nothing) where {R} = FFI.construct(R)
new_packed(::Type{R}, p::PackedArray{T, R}) where {T, R} = FFI.construct(R, p.raw)
function new_packed(::Type{R}, items::AbstractVector) where {R}
    T = eltype(packed_type(R))
    r = Ref(FFI.construct(R))
    index, _ = packed_index_fns(R)
    GC.@preserve r begin
        base = Base.unsafe_convert(Ptr{Cvoid}, r)
        builtin_call(Int64, Symbol(String(nameof(R))[4:end]), :resize, base, Int64(length(items)))
        for (i, x) in enumerate(items)
            store_packed_element!(T, index(base, i - 1), x)
        end
    end
    return r[]
end
take_packed(r::R) where {R} = packed_type(R)(r)

store_packed_element!(::Type{T}, slot::Ptr, x) where {T} = unsafe_store!(Ptr{T}(slot), convert(T, x))
function store_packed_element!(::Type{String}, slot::Ptr, x)
    p = Ptr{RawString}(slot)
    FFI.destroy!(unsafe_load(p))
    unsafe_store!(p, FFI.new_string(x))
    return nothing
end
load_packed_element(::Type{T}, slot::Ptr) where {T} = unsafe_load(Ptr{T}(slot))
load_packed_element(::Type{String}, slot::Ptr) = FFI.julia_string(unsafe_load(Ptr{RawString}(slot)))

# --- Variant conversion (typed conversions and the Variant type live in src/variant/) ------------------------------

function variant_from_bits(vt::Int32, x)
    r = Ref{RawVariant}()
    ccall(FFI.VARIANT_FROM[Int(vt) + 1], Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}), r, Ref(x))
    return r[]
end

function variant_to_bits(::Type{T}, vt::Int32, v::RawVariant) where {T}
    r = Ref{T}()
    ccall(FFI.VARIANT_TO[Int(vt) + 1], Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}), r, Ref(v))
    return r[]
end

"Owned Variant holding a copy of `x`."
to_variant(::Nothing) = FFI.construct(RawVariant)
to_variant(x::Bool) = FFI.to_variant(x)
to_variant(x::Integer) = FFI.to_variant(Int64(x))
to_variant(x::AbstractFloat) = FFI.to_variant(Float64(x))
to_variant(x::GodotEnum) = FFI.to_variant(x.value)
to_variant(x::FFI.RawBuiltin) = FFI.to_variant(x)
to_variant(x::RID) = FFI.to_variant(x.raw)
to_variant(x::Union{GDArray, GDDictionary, Callable, Signal, PackedArray}) = FFI.to_variant(x.raw)
to_variant(x::GodotObject) = variant_from_bits(FFI.GDEXTENSION_VARIANT_TYPE_OBJECT, native_ptr(x))
to_variant(x::RawVariant) = FFI.construct(RawVariant, x)
function to_variant(x::AbstractString)
    s = FFI.new_string(x)
    try
        return FFI.to_variant(s)
    finally
        FFI.destroy!(s)
    end
end
function to_variant(x::Symbol)
    s = FFI.new_string_name(x)
    try
        return FFI.to_variant(s)
    finally
        FFI.destroy!(s)
    end
end
function to_variant(x::NodePath)
    s = new_node_path(x)
    try
        return FFI.to_variant(s)
    finally
        FFI.destroy!(s)
    end
end
to_variant(x::Union{AbstractVector, Tuple}) = (a = new_array(x); try FFI.to_variant(a) finally FFI.destroy!(a) end)
to_variant(x::AbstractDict) = (d = new_dictionary(x); try FFI.to_variant(d) finally FFI.destroy!(d) end)
to_variant(x) = throw(ArgumentError("cannot convert a value of type $(typeof(x)) to a Godot Variant"))

"Julia value of a borrowed Variant."
function from_variant(v::RawVariant)
    vt = FFI.variant_type(v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_NIL && return nothing
    vt == FFI.GDEXTENSION_VARIANT_TYPE_BOOL && return FFI.from_variant(Bool, v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_INT && return FFI.from_variant(Int64, v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_FLOAT && return FFI.from_variant(Float64, v)
    vt == FFI.GDEXTENSION_VARIANT_TYPE_STRING && return take_string(FFI.from_variant(RawString, v))
    vt == FFI.GDEXTENSION_VARIANT_TYPE_STRING_NAME && return take_string_name(FFI.from_variant(RawStringName, v))
    vt == FFI.GDEXTENSION_VARIANT_TYPE_NODE_PATH && return take_node_path(FFI.from_variant(RawNodePath, v))
    vt == FFI.GDEXTENSION_VARIANT_TYPE_RID && return RID(FFI.from_variant(RawRID, v))
    if vt == FFI.GDEXTENSION_VARIANT_TYPE_OBJECT
        return take_object(GodotObject, variant_to_bits(Ptr{Cvoid}, vt, v), false)
    end
    vt == FFI.GDEXTENSION_VARIANT_TYPE_CALLABLE && return Callable(FFI.from_variant(RawCallable, v))
    vt == FFI.GDEXTENSION_VARIANT_TYPE_SIGNAL && return Signal(FFI.from_variant(RawSignal, v))
    vt == FFI.GDEXTENSION_VARIANT_TYPE_DICTIONARY && return Godot._wrap_dictionary(GDDictionary, FFI.from_variant(RawDictionary, v))
    vt == FFI.GDEXTENSION_VARIANT_TYPE_ARRAY && return Godot._wrap_array(GDArray, FFI.from_variant(RawArray, v))
    for R in FFI.RAW_BUILTINS
        FFI.variant_type(R) == vt && return take_packed(FFI.from_variant(R, v))
    end
    for T in Godot.MATH_TYPES
        FFI.variant_type(T) == vt && return variant_to_bits(T, vt, v)
    end
    error("unsupported Variant type $vt")
end

"Julia value of an owned Variant, which is destroyed."
take_variant(r::RawVariant) = (x = from_variant(r); FFI.destroy!(r); x)

end # module Internals
