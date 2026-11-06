# GDDictionary / GDDictionary{K, V} as AbstractDict with reference semantics.
# Ported from GodotSharp/Core/Dictionary.cs (MIT, Godot contributors).

function _set_typed!(d::GDDictionary{K, V}) where {K, V}
    (K === Any && V === Any) && return d
    kvt, kclass = typed_info(K)
    vvt, vclass = typed_info(V)
    kscript = Ref(FFI.construct(RawVariant))
    vscript = Ref(FFI.construct(RawVariant))
    GC.@preserve d kscript vscript FFI.dictionary_set_typed(Internals.raw_ptr(d), kvt, FFI.string_name_ptr(kclass), kscript,
                                                            vvt, FFI.string_name_ptr(vclass), vscript)
    return d
end

GDDictionary() = GDDictionary{Any, Any}()
GDDictionary{K, V}() where {K, V} = _set_typed!(GDDictionary{K, V}(FFI.construct(RawDictionary)))
GDDictionary(items::AbstractDict) = GDDictionary{Any, Any}(items)
GDDictionary(items::Pair...) = GDDictionary{Any, Any}(items)
GDDictionary{K, V}(items::Pair...) where {K, V} = GDDictionary{K, V}(items)
function GDDictionary{K, V}(items) where {K, V}
    d = GDDictionary{K, V}()
    for (k, v) in items
        d[k] = v
    end
    return d
end

function _dictionary_typed_info(raw::RawDictionary)
    r = Ref(raw)
    GC.@preserve r begin
        p = Base.unsafe_convert(Ptr{Cvoid}, r)
        kvt = Int32(Internals.builtin_call(Int64, :Dictionary, :get_typed_key_builtin, p))
        kclass = Internals.take_string_name(Internals.builtin_call(RawStringName, :Dictionary, :get_typed_key_class_name, p))
        vvt = Int32(Internals.builtin_call(Int64, :Dictionary, :get_typed_value_builtin, p))
        vclass = Internals.take_string_name(Internals.builtin_call(RawStringName, :Dictionary, :get_typed_value_class_name, p))
    end
    return kvt, kclass, vvt, vclass
end

"Wrap an owned raw Dictionary as `D`, checking that typed dictionaries match the requested key/value types."
function _wrap_dictionary(::Type{GDDictionary}, raw::RawDictionary)
    kvt, kclass, vvt, vclass = _dictionary_typed_info(raw)
    return GDDictionary{element_type(kvt, kclass), element_type(vvt, vclass)}(raw)
end
function _wrap_dictionary(::Type{GDDictionary{K, V}}, raw::RawDictionary) where {K, V}
    kvt, kclass, vvt, vclass = _dictionary_typed_info(raw)
    if !(_typed_matches(K, kvt, kclass) && _typed_matches(V, vvt, vclass))
        FFI.destroy!(raw)
        throw(ArgumentError("the Dictionary is typed as {$(element_type(kvt, kclass)), $(element_type(vvt, vclass))}, not {$K, $V}"))
    end
    return GDDictionary{K, V}(raw)
end
Internals.take_dictionary(::Type{D}, raw::RawDictionary) where {D <: GDDictionary} = _wrap_dictionary(D, raw)

function Base.length(d::GDDictionary)
    return Int(GC.@preserve d Internals.builtin_call(Int64, :Dictionary, :size, Internals.raw_ptr(d)))
end

function Base.haskey(d::GDDictionary, key)
    kv = Internals.to_variant(key)
    try
        return GC.@preserve d Internals.builtin_call(Bool, :Dictionary, :has, Internals.raw_ptr(d), kv)
    finally
        FFI.destroy!(kv)
    end
end

function Base.get(d::GDDictionary{K, V}, key, default) where {K, V}
    haskey(d, key) || return default
    kv = Ref(Internals.to_variant(key))
    try
        slot = GC.@preserve d kv FFI.dictionary_operator_index_const(Internals.raw_ptr(d), kv)
        return Internals.from_variant(V, unsafe_load(Ptr{RawVariant}(slot)))
    finally
        FFI.destroy!(kv[])
    end
end

const _MISSING = Ref(:missing)
function Base.getindex(d::GDDictionary, key)
    v = get(d, key, _MISSING)
    v === _MISSING && throw(KeyError(key))
    return v
end

function Base.setindex!(d::GDDictionary{K, V}, value, key) where {K, V}
    _check_writable(d)
    GC.@preserve d Internals.set_dictionary_slot!(Internals.raw_ptr(d), _element(K, key), _element(V, value))
    return d
end

Base.delete!(d::GDDictionary, key) = (_check_writable(d); erase(d, key); d)
function Base.pop!(d::GDDictionary, key)
    v = d[key]
    delete!(d, key)
    return v
end
Base.pop!(d::GDDictionary, key, default) = haskey(d, key) ? pop!(d, key) : default
Base.empty!(d::GDDictionary) = (_check_writable(d); clear(d); d)

_raw_keys(d::GDDictionary) = GDArray{Any}(GC.@preserve d Internals.builtin_call(RawArray, :Dictionary, :keys, Internals.raw_ptr(d)))
_raw_values(d::GDDictionary) = GDArray{Any}(GC.@preserve d Internals.builtin_call(RawArray, :Dictionary, :values, Internals.raw_ptr(d)))
Base.keys(d::GDDictionary{K}) where {K} = (ks = _raw_keys(d); K[Internals.from_variant(K, _slot_variant(ks, i)) for i in 1:length(ks)])
Base.values(d::GDDictionary{K, V}) where {K, V} = (vs = _raw_values(d); V[Internals.from_variant(V, _slot_variant(vs, i)) for i in 1:length(vs)])

function Base.iterate(d::GDDictionary{K, V}, state = (_raw_keys(d), _raw_values(d), 1)) where {K, V}
    ks, vs, i = state
    i > length(ks) && return nothing
    k = Internals.from_variant(K, _slot_variant(ks, i))
    v = Internals.from_variant(V, _slot_variant(vs, i))
    return (k => v, (ks, vs, i + 1))
end

_duplicate(d::GDDictionary{K, V}, deep::Bool) where {K, V} =
    GDDictionary{K, V}(GC.@preserve d Internals.builtin_call(RawDictionary, :Dictionary, :duplicate, Internals.raw_ptr(d), deep))
"Shallow copy (Godot `duplicate()`)."
Base.copy(d::GDDictionary) = _duplicate(d, false)
Base.deepcopy_internal(d::GDDictionary, ::IdDict) = _duplicate(d, true)

Base.convert(::Type{GDDictionary{K, V}}, d::AbstractDict) where {K, V} = GDDictionary{K, V}(d)
Base.convert(::Type{GDDictionary}, d::AbstractDict) = GDDictionary(d)
Base.convert(::Type{GDDictionary{K, V}}, d::GDDictionary{K, V}) where {K, V} = d
Base.convert(::Type{GDDictionary}, d::GDDictionary) = d
