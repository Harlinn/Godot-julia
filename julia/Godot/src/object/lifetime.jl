# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Object identity and lifetime through GDExtension instance bindings.
# Ported from Godot's modules/mono/csharp_script.cpp (`_instance_binding_*_callback`, strong/weak GCHandle switching)
# and GodotSharp/Core/GodotObject.base.cs, DisposablesTracker.cs (MIT, Godot contributors).
#
# Every native object wrapped by Julia gets one binding (keyed by a Julia-owned token). The binding remembers the single
# Julia wrapper of the object:
# - non-RefCounted objects: held weakly; the native object lives until `free`/`queue_free`, which marks the wrapper dead.
# - RefCounted objects: the wrapper owns one reference. While the engine holds other references the binding keeps the
#   wrapper alive (strong); when only the wrapper's reference remains it is held weakly, so Julia's GC decides, and the
#   wrapper's finalizer releases the reference at the next safe point.
#
# Locking (see ADR 0007): Godot runs the binding callbacks with the object's binding mutex held. `create`/`free` take
# only `REGISTRY_LOCK`, a leaf lock never held while calling Godot; `reference` takes no lock. `BINDINGS_LOCK`
# serializes wrapper creation and may be held while calling Godot, because no callback takes it.

const FreedObjectError = Internals.FreedObjectError

mutable struct InstanceBinding
    const ptr::Ptr{Cvoid}
    @atomic strong::Any       # the wrapper while it must stay alive, else `nothing`
    @atomic weak::Base.WeakRef
    @atomic holds_ref::Bool   # the current wrapper owns a RefCounted reference
end

# Roots every live binding; Godot's binding pointer is the address of the `InstanceBinding` itself.
const BINDINGS = Dict{Ptr{Cvoid}, InstanceBinding}()
const REGISTRY_LOCK = ReentrantLock()
const BINDINGS_LOCK = ReentrantLock()
const BINDING_CALLBACKS = Ref{FFI.GDExtensionInstanceBindingCallbacks}()
# Binding token: godot-cpp (the native host) binds its own wrappers under the library token, so Julia needs its own key
# (C# likewise keys its bindings by the CSharpLanguage singleton). Any stable address works.
const BINDING_TOKEN = Ref{Ptr{Cvoid}}(C_NULL)

function _report_callback_error(err, bt)
    try
        Runtime.report_exception(err, bt)
    catch
    end
    return nothing
end

_wrapper(b::InstanceBinding) = (@atomic b.weak).value

# Callbacks must not call back into the object (Godot holds its binding mutex).
function _binding_create(token::Ptr{Cvoid}, instance::Ptr{Cvoid})::Ptr{Cvoid}
    try
        b = InstanceBinding(instance, nothing, Base.WeakRef(), false)
        key = pointer_from_objref(b)
        @lock REGISTRY_LOCK BINDINGS[key] = b
        return key
    catch err
        _report_callback_error(err, catch_backtrace())
        return C_NULL
    end
end

function _binding_free(token::Ptr{Cvoid}, instance::Ptr{Cvoid}, binding::Ptr{Cvoid})::Cvoid
    try
        b = @lock REGISTRY_LOCK pop!(BINDINGS, binding, nothing)
        if b !== nothing
            w = _wrapper(b)
            w === nothing || setfield!(w, :__ptr, C_NULL)
        end
    catch err
        _report_callback_error(err, catch_backtrace())
    end
    return nothing
end

function _binding_reference(token::Ptr{Cvoid}, binding::Ptr{Cvoid}, reference::UInt8)::UInt8
    try
        binding == C_NULL && return 0x01
        b = unsafe_pointer_to_objref(binding)::InstanceBinding   # rooted in BINDINGS until `_binding_free`
        rc = Internals.reference_count(b.ptr)
        if reference != 0
            # The engine references the object again: keep the Julia wrapper (and its state) alive.
            if rc > 1 && (@atomic b.holds_ref)
                w = _wrapper(b)
                w === nothing || (@atomic b.strong = w)
            end
            return 0x00
        end
        # Only the wrapper's reference is left: let Julia's GC decide.
        rc == 1 && (@atomic b.holds_ref) && (@atomic b.strong = nothing)
        return UInt8(rc == 0)
    catch err
        _report_callback_error(err, catch_backtrace())
        return 0x00
    end
end

"Create the callback table and token (function pointers are only valid in the running process)."
function init_bindings!()
    BINDING_CALLBACKS[] = FFI.GDExtensionInstanceBindingCallbacks(
        Runtime.guarded(:BINDING_CREATE, @cfunction(_binding_create, Ptr{Cvoid}, (Ptr{Cvoid}, Ptr{Cvoid}))),
        Runtime.guarded(:BINDING_FREE, @cfunction(_binding_free, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))),
        Runtime.guarded(:BINDING_REFERENCE, @cfunction(_binding_reference, UInt8, (Ptr{Cvoid}, Ptr{Cvoid}, UInt8))))
    BINDING_TOKEN[] = pointer_from_objref(BINDINGS)
    return nothing
end

function _get_binding(p::Ptr{Cvoid})
    key = GC.@preserve BINDING_CALLBACKS FFI.object_get_instance_binding(
        p, BINDING_TOKEN[], Base.unsafe_convert(Ptr{FFI.GDExtensionInstanceBindingCallbacks}, BINDING_CALLBACKS))
    key == C_NULL && error("could not create an instance binding")
    return unsafe_pointer_to_objref(key)::InstanceBinding
end

function _find_binding(p::Ptr{Cvoid})
    key = FFI.object_get_instance_binding(p, BINDING_TOKEN[], C_NULL)
    return key == C_NULL ? nothing : unsafe_pointer_to_objref(key)::InstanceBinding
end

_finalize_native(o) = (setfield!(o, :__ptr, C_NULL); nothing)

"""
    wrap_object(p, owned; type = nothing) -> GodotObject

The unique Julia wrapper of the native object at `p`, creating it if needed (as `type`, or the most-derived generated
wrapper). For `RefCounted` objects, `owned` says whether the caller holds a reference that the wrapper adopts.
"""
function wrap_object(p::Ptr{Cvoid}, owned::Bool; type::Union{Nothing, DataType} = nothing)
    b = _get_binding(p)
    @lock BINDINGS_LOCK begin
        w = _wrapper(b)
        if w !== nothing && getfield(w, :__ptr) == p
            owned && (@atomic b.holds_ref) && Internals.unreference_object(p)   # the wrapper already owns a reference
            return w
        end
        T = type === nothing ? Internals.wrapper_type(p) : type
        w = T(p)
        if w isa RefCounted
            owned || Internals.reference_object(p)
            @atomic b.holds_ref = true
            @atomic b.strong = Internals.reference_count(p) > 1 ? w : nothing
            finalizer(Internals.finalize_object, w)
        else
            @atomic b.holds_ref = false
            @atomic b.strong = nothing
            finalizer(_finalize_native, w)
        end
        @atomic b.weak = Base.WeakRef(w)
        return w
    end
end

"""
    bind_wrapper!(p, w)

Make `w` (a user script struct whose `__ptr` is `p`) the Julia wrapper of the native object at `p`, held strongly
while the object lives (subject to the RefCounted rules). Used when script instances are created.
"""
function bind_wrapper!(p::Ptr{Cvoid}, w::GodotObject)
    getfield(w, :__ptr) == p || throw(ArgumentError("wrapper does not point to the object"))
    b = _get_binding(p)
    @lock BINDINGS_LOCK begin
        old = _wrapper(b)
        if w isa RefCounted
            (@atomic b.holds_ref) || Internals.reference_object(p)
            @atomic b.holds_ref = true
            @atomic b.strong = Internals.reference_count(p) > 1 ? w : nothing
            finalizer(Internals.finalize_object, w)
        else
            @atomic b.strong = w
        end
        old === nothing || old === w || setfield!(old, :__ptr, C_NULL)
        @atomic b.weak = Base.WeakRef(w)
    end
    return w
end

"""
    unbind_wrapper!(p, w)

Undo [`bind_wrapper!`](@ref) when the script instance of the object at `p` goes away (the object is being freed or
its script was removed): `w` is marked dead and later lookups create a fresh engine wrapper.
"""
function unbind_wrapper!(p::Ptr{Cvoid}, w::GodotObject)
    b = _find_binding(p)
    if b !== nothing
        @lock BINDINGS_LOCK begin
            if _wrapper(b) === w
                @atomic b.weak = Base.WeakRef(nothing)
                @atomic b.strong = nothing
                if @atomic b.holds_ref
                    # The object is alive (a dying object has no references left): release ours at a safe point.
                    @atomic b.holds_ref = false
                    Internals.enqueue_release!(Internals.PendingUnref(p))
                end
            end
        end
    end
    setfield!(w, :__ptr, C_NULL)
    return nothing
end

"Release the reference queued by a RefCounted wrapper's finalizer (runs at a safe point on the main thread)."
function release_reference!(p::Ptr{Cvoid})
    b = _find_binding(p)
    if b !== nothing
        @lock BINDINGS_LOCK begin
            w = _wrapper(b)
            if w === nothing || getfield(w, :__ptr) == C_NULL
                @atomic b.holds_ref = false
                @atomic b.strong = nothing
            end
        end
    end
    Internals.unreference_object(p)
    return nothing
end

"Drop every Julia reference and binding before the runtime shuts down (Godot must not call back into Julia later)."
function release_bindings!()
    for b in @lock REGISTRY_LOCK collect(values(BINDINGS))
        w = _wrapper(b)
        w === nothing || setfield!(w, :__ptr, C_NULL)
        @atomic b.strong = nothing
        if @atomic b.holds_ref
            @atomic b.holds_ref = false
            Internals.unreference_object(b.ptr)        # may free the object (and remove its binding)
        end
    end
    for b in @lock REGISTRY_LOCK collect(values(BINDINGS))
        b.ptr == C_NULL || FFI.object_free_instance_binding(b.ptr, BINDING_TOKEN[])
    end
    @lock REGISTRY_LOCK empty!(BINDINGS)
    return nothing
end

"Number of native objects currently bound to Julia (for tests and diagnostics)."
binding_count() = @lock REGISTRY_LOCK length(BINDINGS)

"""
    is_instance_valid(obj) -> Bool

`false` for `nothing` and for wrappers whose native object was freed (or that were disposed with `finalize`).
"""
is_instance_valid(::Nothing) = false
is_instance_valid(o::GodotObject) = getfield(o, :__ptr) != C_NULL
