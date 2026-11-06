# Hand-written behavior of engine object wrappers: properties, equality, casting, dynamic access, free.
# Ported from GodotSharp/Core/GodotObject.base.cs and Node.cs (GetNode<T>) (MIT, Godot contributors).

# Julia fields (`__ptr`, user script fields) first; otherwise a property defined dynamically (e.g. by a GDScript).
@inline function Base.getproperty(o::GodotObject, s::Symbol)
    hasfield(typeof(o), s) && return getfield(o, s)
    return dynamic_get(o, s)
end
@inline function Base.setproperty!(o::GodotObject, s::Symbol, v)
    hasfield(typeof(o), s) && return setfield!(o, s, convert(fieldtype(typeof(o), s), v))
    dynamic_set!(o, s, v)
    return v
end
Base.propertynames(o::GodotObject, private::Bool = false) = property_names(typeof(o))

function property_names(T::Type)
    names = Symbol[]
    while T !== GodotObject && T !== Any
        append!(names, Internals.class_property_names(T))
        T = supertype(T)
    end
    return Tuple(names)
end

"`true` if the object (including its script) exposes property `name`."
function has_property(o::GodotObject, name::Union{Symbol, AbstractString})
    s = String(name)
    for p in get_property_list(o)
        get(p, "name", nothing) == s && return true
    end
    return false
end

function dynamic_get(o::GodotObject, s::Symbol)
    v = get(o, s)
    v === nothing && !has_property(o, s) && throw(ArgumentError("$(class_name(o)) has no property $s"))
    return v
end
function dynamic_set!(o::GodotObject, s::Symbol, v)
    has_property(o, s) || throw(ArgumentError("$(class_name(o)) has no property $s"))
    set(o, s, v)
    return nothing
end

"Set property `name` dynamically (Godot `Object.set`), e.g. one defined by a GDScript script."
set!(o::GodotObject, name::Union{Symbol, AbstractString}, value) = (set(o, name, value); o)

# One wrapper per native object (instance bindings), so identity is equality.
Base.:(==)(a::GodotObject, b::GodotObject) = a === b

"Name of the engine class an object wrapper (or user script struct) derives from."
class_name(o::GodotObject) = godot_class_name(typeof(o))

function Base.show(io::IO, o::GodotObject)
    p = getfield(o, :__ptr)
    if p == C_NULL
        print(io, class_name(o), "(<freed>)")
    else
        print(io, class_name(o), "(#", FFI.object_get_instance_id(p), ")")
    end
end

# --- Casting (C#: `as`, `is`, explicit casts, GetNode<T>) ---------------------------------------------------------

Base.convert(::Type{T}, o::T) where {T <: GodotObject} = o
Base.convert(::Type{T}, o::GodotObject) where {T <: GodotObject} =
    o isa T ? o : throw(TypeError(:convert, "Godot object cast", T, o))

"""
    as(T, obj) -> Union{Nothing, T}

`obj` if it is a `T`, otherwise `nothing` (C#'s `obj as T`).
"""
as(::Type{T}, o) where {T <: GodotObject} = o isa T ? o : nothing

"Godot `WeakRef` to `obj` (C#'s `GodotObject.WeakRef`); `get_ref(w)` returns the object or `nothing`."
weakref(o::GodotObject) = GD.weakref(o)

# --- Lifetime ----------------------------------------------------------------------------------------------------

"""
    free(obj::GodotObject)

Destroy a non-reference-counted engine object immediately (Godot's `Object.free()`). The wrapper is marked dead;
using it afterwards throws `FreedObjectError`. `RefCounted` objects are freed automatically when the last reference
goes away. To release the Julia side of an object without destroying it (C#'s `Dispose`), use `finalize(obj)`.
"""
function free(o::GodotObject)
    o isa RefCounted && throw(ArgumentError("RefCounted objects are freed automatically; they cannot be freed manually"))
    FFI.object_destroy(Internals.native_ptr(o))
    setfield!(o, :__ptr, C_NULL)
    return nothing
end

"""
    singleton(T)

Engine singleton instance of class `T` (e.g. `singleton(Engine)`). Methods can also be called on the class
directly: `get_version_info(Engine)`.
"""
singleton(::Type{T}) where {T <: GodotObject} = Internals.singleton(T)
