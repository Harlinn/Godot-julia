# Callables backed by Julia callables (GDExtension custom callables). Every entry point catches exceptions.

"What a custom Callable pins: the Julia callable (swapped on hot reload) and the hash Godot saw at creation."
mutable struct JuliaCallable
    f::Any
    const hash::UInt32
end

callable_box(ud::Ptr{Cvoid}) = deref(UInt64(UInt(ud)))::JuliaCallable

function _callable_call(ud::Ptr{Cvoid}, args::Ptr{Ptr{Cvoid}}, argc::Int64, ret::Ptr{Cvoid},
                        err::Ptr{FFI.GDExtensionCallError})::Cvoid
    unsafe_store!(err, FFI.GDExtensionCallError(FFI.GDEXTENSION_CALL_OK, 0, 0))
    @godot_entry nothing begin
        f = callable_box(ud).f
        xs = Any[Internals.from_variant(unsafe_load(Ptr{FFI.RawVariant}(unsafe_load(args, i)))) for i in 1:argc]
        result = f(xs...)
        try
            Internals.assign_variant_slot!(ret, result)
        catch e
            # Results that cannot be stored in a Variant (e.g. from callbacks used as signal handlers) become null.
            e isa ArgumentError || rethrow()
        end
        nothing
    end
end

"Hook run when Godot releases the last copy of a custom Callable wrapping `f` (any thread)."
callable_freed(@nospecialize(f)) = nothing

function _callable_free(ud::Ptr{Cvoid})::Cvoid
    @godot_entry nothing begin
        id = UInt64(UInt(ud))
        box = deref(id)::JuliaCallable
        unpin(id)
        callable_freed(box.f)
        nothing
    end
end
_callable_hash(ud::Ptr{Cvoid})::UInt32 = @godot_entry UInt32(0) callable_box(ud).hash
_callable_equal(a::Ptr{Cvoid}, b::Ptr{Cvoid})::UInt8 =
    @godot_entry UInt8(0) UInt8(callable_box(a).f === callable_box(b).f)
_callable_less(a::Ptr{Cvoid}, b::Ptr{Cvoid})::UInt8 =
    @godot_entry UInt8(0) UInt8(objectid(callable_box(a).f) < objectid(callable_box(b).f))

function _callable_to_string(ud::Ptr{Cvoid}, valid::Ptr{UInt8}, out::Ptr{Cvoid})::Cvoid
    @godot_entry nothing begin
        s = sprint(show, callable_box(ud).f; context = :limit => true)
        p = Ptr{FFI.RawString}(out)
        FFI.destroy!(unsafe_load(p))
        unsafe_store!(p, FFI.new_string(s))
        unsafe_store!(valid, 0x01)
        nothing
    end
end

function _callable_argcount(ud::Ptr{Cvoid}, valid::Ptr{UInt8})::Int64
    unsafe_store!(valid, 0x00)
    @godot_entry Int64(0) begin
        ms = methods(callable_box(ud).f)
        if length(ms) == 1 && !ms[1].isva
            unsafe_store!(valid, 0x01)
            return Int64(ms[1].nargs - 1)
        end
        Int64(0)
    end
end

const CALLABLE_FNS = Ref{NTuple{7, Ptr{Cvoid}}}()

"Guarded entry points of custom Callables (set by `__init_runtime__`)."
function init_callable_fns!()
    CALLABLE_FNS[] = (
        guarded(:CALLABLE_CALL, @cfunction(_callable_call, Cvoid, (Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Int64, Ptr{Cvoid}, Ptr{FFI.GDExtensionCallError}))),
        guarded(:CALLABLE_FREE, @cfunction(_callable_free, Cvoid, (Ptr{Cvoid},))),
        guarded(:CALLABLE_HASH, @cfunction(_callable_hash, UInt32, (Ptr{Cvoid},))),
        guarded(:CALLABLE_EQUAL, @cfunction(_callable_equal, UInt8, (Ptr{Cvoid}, Ptr{Cvoid}))),
        guarded(:CALLABLE_LESS, @cfunction(_callable_less, UInt8, (Ptr{Cvoid}, Ptr{Cvoid}))),
        guarded(:CALLABLE_TO_STRING, @cfunction(_callable_to_string, Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Ptr{Cvoid}))),
        guarded(:CALLABLE_ARGCOUNT, @cfunction(_callable_argcount, Int64, (Ptr{Cvoid}, Ptr{UInt8}))))
    return nothing
end

"Create a custom Callable that invokes `f`; `object` (optional) ties it to an engine object."
function custom_callable(f, object)
    isassigned(CALLABLE_FNS) || init_callable_fns!()
    call, free, hash, equal, less, to_string, argcount = CALLABLE_FNS[]
    id = pin(JuliaCallable(f, Base.hash(f) % UInt32))
    object_id = object === nothing ? UInt64(0) : UInt64(FFI.object_get_instance_id(Internals.native_ptr(object)))
    info = Ref(FFI.GDExtensionCallableCustomInfo2(
        Ptr{Cvoid}(UInt(id)), FFI.LIBRARY[], object_id, call, C_NULL, free, hash, equal, less, to_string, argcount))
    r = Ref{FFI.RawCallable}()
    GC.@preserve info FFI.callable_custom_create2(r, info)
    return Godot.Callable(r[])
end
