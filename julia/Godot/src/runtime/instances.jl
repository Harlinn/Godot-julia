# Script instances: the GDExtensionScriptInstanceInfo3 table whose callbacks dispatch into Julia.
# Analog of CSharpInstance (modules/mono/csharp_script.cpp) and GodotSharp/Core/Bridge/CSharpInstanceBridge.cs
# (MIT, Godot contributors). Every callback catches exceptions (`@godot_entry`).

"Data behind a script instance: the user's struct (also the engine object's Julia wrapper) and its class."
mutable struct ScriptInstance
    obj::GodotObject                 # replaced by a struct of the new generation on hot reload
    const owner::Ptr{Cvoid}
    info::ScriptClassInfo
    const script::Ptr{Cvoid}
    suspended::Bool                  # the script failed to reload: state is kept, no user code runs
end

ScriptInstance(obj, owner, info, script) = ScriptInstance(obj, owner, info, script, false)

"Script method `name` of the instance, or `nothing` (always while the instance is suspended)."
user_method(si::ScriptInstance, name::Symbol) = si.suspended ? nothing : find_methods(si.info, name)

const INSTANCES = Dict{Ptr{Cvoid}, ScriptInstance}()   # roots instance data while Godot holds its pointer
const INSTANCES_LOCK = ReentrantLock()
const INSTANCE_INFO = Ref{FFI.GDExtensionScriptInstanceInfo3}()

@inline instance_data(p::Ptr{Cvoid}) = unsafe_pointer_to_objref(p)::ScriptInstance

# --- Cached names and strings handed to Godot ----------------------------------------------------------------------

# Interned StringName data pointer => Symbol. A copy of each StringName is kept so its data (the key) is never reused.
const NAME_CACHE = Dict{UInt64, Symbol}()
const NAME_KEEP = FFI.RawStringName[]
const NAME_LOCK = ReentrantLock()

"Symbol for the borrowed StringName at `p`."
function name_symbol(p::Ptr{Cvoid})
    raw = unsafe_load(Ptr{FFI.RawStringName}(p))
    key = raw._data[1]
    @lock NAME_LOCK begin
        s = get(NAME_CACHE, key, nothing)
        s === nothing || return s
        s = Symbol(FFI.julia_string(raw))
        push!(NAME_KEEP, FFI.construct(FFI.RawStringName, raw))
        NAME_CACHE[key] = s
        return s
    end
end

const STRINGS = Dict{String, Base.RefValue{FFI.RawString}}()
const STRINGS_LOCK = ReentrantLock()

"Pointer to a cached Godot String (lives until shutdown) for property hint strings."
function string_ptr(s::String)
    box = @lock STRINGS_LOCK get!(() -> Ref(FFI.new_string(s)), STRINGS, s)
    return Ptr{Cvoid}(Base.unsafe_convert(Ptr{FFI.RawString}, box))
end

function destroy_script_strings!()
    FFI.INITIALIZED[] || return nothing
    @lock STRINGS_LOCK begin
        foreach(b -> FFI.destroy!(b[]), values(STRINGS))
        empty!(STRINGS)
    end
    @lock NAME_LOCK begin
        foreach(FFI.destroy!, NAME_KEEP)
        empty!(NAME_KEEP)
        empty!(NAME_CACHE)
    end
    return nothing
end

native_prop(p::PropInfo) = FFI.GDExtensionPropertyInfo(p.type, Ptr{Cvoid}(FFI.string_name_ptr(p.name)),
                                                       Ptr{Cvoid}(FFI.string_name_ptr(p.class_name)), p.hint,
                                                       string_ptr(p.hint_string), p.usage)

# Lists returned to Godot stay rooted until it calls the matching free callback.
const BUFFERS = Dict{Ptr{Cvoid}, Any}()
const BUFFERS_LOCK = ReentrantLock()

function keep_buffer!(v::Vector, extra = nothing)
    isempty(v) && return Ptr{eltype(v)}(C_NULL)
    p = pointer(v)
    @lock BUFFERS_LOCK BUFFERS[Ptr{Cvoid}(p)] = (v, extra)
    return p
end

release_buffer!(p::Ptr) = (p == C_NULL || @lock BUFFERS_LOCK delete!(BUFFERS, Ptr{Cvoid}(p)); nothing)

# --- Conversions ---------------------------------------------------------------------------------------------------

"Convert a borrowed Variant to the declared Julia type `T` (C#: marshalling per parameter type)."
function convert_arg(@nospecialize(T), raw::FFI.RawVariant)
    T === Any && return Internals.from_variant(raw)
    x = try
        Internals.from_variant(T, raw)
    catch e
        e isa MethodError || rethrow()
        Internals.from_variant(raw)
    end
    return x isa T ? x : convert(T, x)
end

is_conversion_error(e) = e isa Union{Godot.VariantConversionError, MethodError, InexactError, ArgumentError, TypeError}

function expected_variant_type(@nospecialize(T))
    t = property_type(T)
    return t === nothing ? Int32(VT_NIL) : Int32(t[1])
end

store_call_error!(err::Ptr{FFI.GDExtensionCallError}, code, argument = 0, expected = 0) =
    (unsafe_store!(err, FFI.GDExtensionCallError(code, Int32(argument), Int32(expected))); nothing)

function object_class_name(p::Ptr{Cvoid})
    r = Ref{FFI.RawStringName}()
    FFI.object_get_class_name(p, FFI.LIBRARY[], r)
    return Internals.take_string_name(r[])
end

# --- Creation and teardown -----------------------------------------------------------------------------------------

"Bridge handler for `JuliaScript::_instance_create`: returns the new script instance pointer (0 on failure)."
function script_instance_create(self::Ptr{Cvoid}, owner_handle::Int64)
    st = find_state(self)
    info = st === nothing ? nothing : st.info
    info === nothing && return Int64(0)
    owner = Ptr{Cvoid}(owner_handle)
    class = object_class_name(owner)
    if class !== info.native_base && !Godot.is_parent_class(Godot.ClassDB, class, info.native_base)
        report_script_error(st.path, info.line, "script inherits from native type $(info.native_base), so it can't be " *
                                                "assigned to an object of type $class")
        return Int64(0)
    end
    obj = Base.invokelatest(construct_instance, info, owner)
    si = ScriptInstance(obj, owner, info, self)
    data = pointer_from_objref(si)
    @lock INSTANCES_LOCK INSTANCES[data] = si
    # Godot 4.7 objects reach their script only through the script instance, which must own a reference to it
    # (like GDScriptInstance's Ref<GDScript>); released in `_inst_free`.
    Internals.reference_object(self)
    inst = GC.@preserve INSTANCE_INFO FFI.script_instance_create3(
        Base.unsafe_convert(Ptr{FFI.GDExtensionScriptInstanceInfo3}, INSTANCE_INFO), data)
    Godot.bind_wrapper!(owner, obj)
    @lock SCRIPTS_LOCK push!(st.instances, owner)
    sm = find_methods(info, :_init)
    if sm !== nothing
        try
            Base.invokelatest(sm.f, obj)
        catch e
            report_exception(e, catch_backtrace())
        end
    end
    return Int64(UInt(inst))
end

"Detach every live Julia script instance (the runtime is shutting down and Godot must not call back afterwards)."
function detach_instances!()
    FFI.INITIALIZED[] || return nothing
    for si in @lock INSTANCES_LOCK collect(values(INSTANCES))
        try
            getfield(si.obj, :__ptr) == C_NULL || Godot.set_script(si.obj, nothing)
        catch e
            report_exception(e, catch_backtrace())
        end
    end
    return nothing
end

# --- Callbacks -----------------------------------------------------------------------------------------------------

function _inst_set(p::Ptr{Cvoid}, name::Ptr{Cvoid}, value::Ptr{Cvoid})::UInt8
    @godot_entry 0x00 begin
        si = instance_data(p)
        s = name_symbol(name)
        raw = unsafe_load(Ptr{FFI.RawVariant}(value))
        handled = try
            script_set_field!(si.obj, s, raw)
        catch e
            is_conversion_error(e) || rethrow()
            report_exception(ArgumentError("cannot assign a $(Godot.VariantType(FFI.variant_type(raw))) to " *
                                           "$(si.info.name).$s"), catch_backtrace())
            true
        end
        handled && return 0x01
        find_tool_button(si.info, s) === nothing || return 0x01   # read-only
        sm = user_method(si, :_set)
        sm === nothing && return 0x00
        UInt8(Base.invokelatest(sm.f, si.obj, s, Internals.from_variant(raw)) === true)
    end
end

function _inst_get(p::Ptr{Cvoid}, name::Ptr{Cvoid}, ret::Ptr{Cvoid})::UInt8
    @godot_entry 0x00 begin
        si = instance_data(p)
        s = name_symbol(name)
        script_get_field(si.obj, s, ret) && return 0x01
        si.suspended && return 0x00
        tb = find_tool_button(si.info, s)
        if tb !== nothing
            ci, b = tb
            obj = si.obj
            Internals.assign_variant_slot!(ret, Godot.Callable(() -> Base.invokelatest(getglobal(ci.mod, b.target), obj)))
            return 0x01
        end
        sm = user_method(si, :_get)
        sm === nothing && return 0x00
        r = Base.invokelatest(sm.f, si.obj, s)
        r === nothing && return 0x00
        Internals.assign_variant_slot!(ret, r)
        0x01
    end
end

function _inst_get_property_list(p::Ptr{Cvoid}, r_count::Ptr{UInt32})::Ptr{FFI.GDExtensionPropertyInfo}
    unsafe_store!(r_count, UInt32(0))
    @godot_entry Ptr{FFI.GDExtensionPropertyInfo}(C_NULL) begin
        si = instance_data(p)
        props = script_props(si.info; categories = true)
        sm = user_method(si, :_get_property_list)
        if sm !== nothing
            extra = Base.invokelatest(sm.f, si.obj)
            extra === nothing || foreach(d -> push!(props, PropInfo(d)), extra)
        end
        # Like GDScriptInstance, the instance validates its own properties; Godot validates engine properties.
        vm = user_method(si, :_validate_property)
        if vm !== nothing
            for (i, p) in pairs(props)
                d = prop_dict(p)
                Base.invokelatest(vm.f, si.obj, d)
                props[i] = PropInfo(d)
            end
        end
        v = FFI.GDExtensionPropertyInfo[native_prop(x) for x in props]
        unsafe_store!(r_count, UInt32(length(v)))
        keep_buffer!(v)
    end
end

_inst_free_property_list(p::Ptr{Cvoid}, list::Ptr{FFI.GDExtensionPropertyInfo}, count::UInt32)::Cvoid =
    @godot_entry nothing release_buffer!(list)

function _inst_property_can_revert(p::Ptr{Cvoid}, name::Ptr{Cvoid})::UInt8
    @godot_entry 0x00 begin
        si = instance_data(p)
        sm = user_method(si, :_property_can_revert)
        sm === nothing ? 0x00 : UInt8(Base.invokelatest(sm.f, si.obj, name_symbol(name)) === true)
    end
end

function _inst_property_get_revert(p::Ptr{Cvoid}, name::Ptr{Cvoid}, ret::Ptr{Cvoid})::UInt8
    @godot_entry 0x00 begin
        si = instance_data(p)
        sm = user_method(si, :_property_get_revert)
        sm === nothing && return 0x00
        r = Base.invokelatest(sm.f, si.obj, name_symbol(name))
        r === nothing && return 0x00
        Internals.assign_variant_slot!(ret, r)
        0x01
    end
end

_inst_get_owner(p::Ptr{Cvoid})::Ptr{Cvoid} = @godot_entry C_NULL instance_data(p).owner

function _inst_get_property_state(p::Ptr{Cvoid}, add::Ptr{Cvoid}, ud::Ptr{Cvoid})::Cvoid
    @godot_entry nothing begin
        si = instance_data(p)
        for f in si.info.fields
            property_type(f.type) === nothing && continue
            v = Ref(Internals.to_variant(getfield(si.obj, f.name)))
            try
                GC.@preserve v ccall(add, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), FFI.string_name_ptr(f.name), v, ud)
            finally
                FFI.destroy!(v[])
            end
        end
        nothing
    end
end

function _inst_get_method_list(p::Ptr{Cvoid}, r_count::Ptr{UInt32})::Ptr{FFI.GDExtensionMethodInfo}
    unsafe_store!(r_count, UInt32(0))
    @godot_entry Ptr{FFI.GDExtensionMethodInfo}(C_NULL) begin
        si = instance_data(p)
        infos = FFI.GDExtensionMethodInfo[]
        args_keep = Vector{FFI.GDExtensionPropertyInfo}[]
        for n in (si.suspended ? Symbol[] : script_method_names(si.info))
            _, args, ret = method_prop_info(n, find_methods(si.info, n).methods[1])
            av = FFI.GDExtensionPropertyInfo[native_prop(a) for a in args]
            push!(args_keep, av)
            push!(infos, FFI.GDExtensionMethodInfo(Ptr{Cvoid}(FFI.string_name_ptr(n)), native_prop(ret),
                                                   UInt32(METHOD_FLAG_NORMAL), Int32(0), UInt32(length(av)),
                                                   isempty(av) ? C_NULL : Ptr{Cvoid}(pointer(av)), UInt32(0), C_NULL))
        end
        unsafe_store!(r_count, UInt32(length(infos)))
        keep_buffer!(infos, args_keep)
    end
end

_inst_free_method_list(p::Ptr{Cvoid}, list::Ptr{FFI.GDExtensionMethodInfo}, count::UInt32)::Cvoid =
    @godot_entry nothing release_buffer!(list)

function _inst_get_property_type(p::Ptr{Cvoid}, name::Ptr{Cvoid}, r_valid::Ptr{UInt8})::Int32
    unsafe_store!(r_valid, 0x00)
    @godot_entry Int32(0) begin
        si = instance_data(p)
        i = property_index(si.info, name_symbol(name))
        i == 0 && return Int32(0)
        unsafe_store!(r_valid, 0x01)
        Int32(property_type(si.info.fields[i].type)[1])
    end
end

function _inst_validate_property(p::Ptr{Cvoid}, prop::Ptr{FFI.GDExtensionPropertyInfo})::UInt8
    @godot_entry 0x00 begin
        si = instance_data(p)
        sm = user_method(si, :_validate_property)
        sm === nothing && return 0x00
        pi = unsafe_load(prop)
        d = Dict{String, Any}("name" => String(name_symbol(pi.name)), "class_name" => String(name_symbol(pi.class_name)),
                              "type" => Int(pi.type_), "hint" => Int(pi.hint), "usage" => Int(pi.usage),
                              "hint_string" => FFI.julia_string(unsafe_load(Ptr{FFI.RawString}(pi.hint_string))))
        Base.invokelatest(sm.f, si.obj, d)
        unsafe_store!(prop, native_prop(PropInfo(d)))
        0x01
    end
end

_inst_has_method(p::Ptr{Cvoid}, name::Ptr{Cvoid})::UInt8 =
    @godot_entry 0x00 UInt8(user_method(instance_data(p), name_symbol(name)) !== nothing)

function _inst_get_method_argument_count(p::Ptr{Cvoid}, name::Ptr{Cvoid}, r_valid::Ptr{UInt8})::Int64
    unsafe_store!(r_valid, 0x00)
    @godot_entry Int64(0) begin
        sm = user_method(instance_data(p), name_symbol(name))
        sm === nothing && return Int64(0)
        unsafe_store!(r_valid, 0x01)
        Int64(arity(sm.methods[1]))
    end
end

struct CallFailed end
const CALL_FAILED = CallFailed()

"""
Compile a thunk `(obj, args, err) -> result` converting the Variant arguments to the declared types of the single
method accepting `argc` arguments (C#: generated `InvokeGodotClassMethod`), or `nothing` if dispatch is ambiguous.
"""
function make_thunk(sm::ScriptMethod, argc::Int)
    cands = Method[m for m in sm.methods if accepts(m, argc)]
    length(cands) == 1 || return nothing
    types = arg_types(cands[1], argc)
    xs = [Symbol("x", i) for i in 1:argc]
    convs = [quote
                 $(xs[i]) = try
                     convert_arg($(types[i]), unsafe_load(Ptr{FFI.RawVariant}(unsafe_load(args, $i))))
                 catch e
                     is_conversion_error(e) || rethrow()
                     store_call_error!(err, FFI.GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT, $(i - 1),
                                       $(expected_variant_type(types[i])))
                     return CALL_FAILED
                 end
             end for i in 1:argc]
    return Core.eval(@__MODULE__, :((obj, args::Ptr{Ptr{Cvoid}}, err::Ptr{FFI.GDExtensionCallError}) -> begin
                                         $(convs...)
                                         $(sm.f)(obj, $(xs...))
                                     end))
end

thunk_for(info::ScriptClassInfo, sm::ScriptMethod, argc::Int) =
    @lock info.methods_lock get!(() -> make_thunk(sm, argc), sm.thunks, argc)

function _inst_call(p::Ptr{Cvoid}, name::Ptr{Cvoid}, args::Ptr{Ptr{Cvoid}}, argc::Int64, ret::Ptr{Cvoid},
                    err::Ptr{FFI.GDExtensionCallError})::Cvoid
    store_call_error!(err, FFI.GDEXTENSION_CALL_OK)
    @godot_entry nothing begin
        si = instance_data(p)
        sm = user_method(si, name_symbol(name))
        sm === nothing && return store_call_error!(err, FFI.GDEXTENSION_CALL_ERROR_INVALID_METHOD)
        cands = Method[m for m in sm.methods if accepts(m, argc)]
        if isempty(cands)
            lo = minimum(m -> m.isva ? arity(m) - 1 : arity(m), sm.methods)
            hi = maximum(arity, sm.methods)
            return argc < lo ? store_call_error!(err, FFI.GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS, 0, lo) :
                   store_call_error!(err, FFI.GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS, 0, hi)
        end
        thunk = thunk_for(si.info, sm, Int(argc))
        r = if thunk !== nothing
            Base.invokelatest(thunk, si.obj, args, err)
        else
            # Several overloads: convert dynamically and let Julia's dispatch choose.
            xs = Any[Internals.from_variant(unsafe_load(Ptr{FFI.RawVariant}(unsafe_load(args, i)))) for i in 1:argc]
            Base.invokelatest(sm.f, si.obj, xs...)
        end
        r === CALL_FAILED && return nothing
        if r !== nothing
            try
                Internals.assign_variant_slot!(ret, r)
            catch e
                # Engine callbacks often end with an expression whose value is not meant as a result.
                e isa ArgumentError && sm.virtual || rethrow()
            end
        end
        nothing
    end
end

function _inst_notification(p::Ptr{Cvoid}, what::Int32, reversed::UInt8)::Cvoid
    @godot_entry nothing begin
        si = instance_data(p)
        sm = user_method(si, :_notification)
        if sm !== nothing
            T = arg_types(sm.methods[1], 1)[1]
            Base.invokelatest(sm.f, si.obj, T === Any ? Int(what) : convert(T, what))
        end
        nothing
    end
end

function _inst_to_string(p::Ptr{Cvoid}, r_valid::Ptr{UInt8}, r_out::Ptr{Cvoid})::Cvoid
    unsafe_store!(r_valid, 0x00)
    @godot_entry nothing begin
        si = instance_data(p)
        sm = user_method(si, :_to_string)
        if sm !== nothing
            s = string(Base.invokelatest(sm.f, si.obj))
            out = Ptr{FFI.RawString}(r_out)
            FFI.destroy!(unsafe_load(out))
            unsafe_store!(out, FFI.new_string(s))
            unsafe_store!(r_valid, 0x01)
        end
        nothing
    end
end

# Strong/weak switching is done by the instance binding's reference callback (object/lifetime.jl).
_inst_refcount_incremented(p::Ptr{Cvoid})::Cvoid = nothing
_inst_refcount_decremented(p::Ptr{Cvoid})::UInt8 = 0x01

_inst_get_script(p::Ptr{Cvoid})::Ptr{Cvoid} = @godot_entry C_NULL instance_data(p).script
_inst_is_placeholder(p::Ptr{Cvoid})::UInt8 = 0x00
_inst_get_language(p::Ptr{Cvoid})::Ptr{Cvoid} = LANGUAGE_PTR[]

function _inst_free(p::Ptr{Cvoid})::Cvoid
    @godot_entry nothing begin
        si = @lock INSTANCES_LOCK pop!(INSTANCES, p, nothing)
        if si !== nothing
            st = find_state(si.script)
            st === nothing || @lock SCRIPTS_LOCK delete!(st.instances, si.owner)
            Godot.unbind_wrapper!(si.owner, si.obj)
            Internals.unreference_object(si.script)   # may free the script (JuliaScript calls script_free)
        end
        nothing
    end
end

function init_instance_info!()
    g = guarded
    INSTANCE_INFO[] = FFI.GDExtensionScriptInstanceInfo3(
        g(:INST_SET, @cfunction(_inst_set, UInt8, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))),
        g(:INST_GET, @cfunction(_inst_get, UInt8, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))),
        g(:INST_GET_PROPERTY_LIST, @cfunction(_inst_get_property_list, Ptr{FFI.GDExtensionPropertyInfo}, (Ptr{Cvoid}, Ptr{UInt32}))),
        g(:INST_FREE_PROPERTY_LIST, @cfunction(_inst_free_property_list, Cvoid, (Ptr{Cvoid}, Ptr{FFI.GDExtensionPropertyInfo}, UInt32))),
        C_NULL,                                                                    # get_class_category (deprecated)
        g(:INST_PROPERTY_CAN_REVERT, @cfunction(_inst_property_can_revert, UInt8, (Ptr{Cvoid}, Ptr{Cvoid}))),
        g(:INST_PROPERTY_GET_REVERT, @cfunction(_inst_property_get_revert, UInt8, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))),
        g(:INST_GET_OWNER, @cfunction(_inst_get_owner, Ptr{Cvoid}, (Ptr{Cvoid},))),
        g(:INST_GET_PROPERTY_STATE, @cfunction(_inst_get_property_state, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}))),
        g(:INST_GET_METHOD_LIST, @cfunction(_inst_get_method_list, Ptr{FFI.GDExtensionMethodInfo}, (Ptr{Cvoid}, Ptr{UInt32}))),
        g(:INST_FREE_METHOD_LIST, @cfunction(_inst_free_method_list, Cvoid, (Ptr{Cvoid}, Ptr{FFI.GDExtensionMethodInfo}, UInt32))),
        g(:INST_GET_PROPERTY_TYPE, @cfunction(_inst_get_property_type, Int32, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{UInt8}))),
        g(:INST_VALIDATE_PROPERTY, @cfunction(_inst_validate_property, UInt8, (Ptr{Cvoid}, Ptr{FFI.GDExtensionPropertyInfo}))),
        g(:INST_HAS_METHOD, @cfunction(_inst_has_method, UInt8, (Ptr{Cvoid}, Ptr{Cvoid}))),
        g(:INST_GET_METHOD_ARGUMENT_COUNT, @cfunction(_inst_get_method_argument_count, Int64, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{UInt8}))),
        g(:INST_CALL, @cfunction(_inst_call, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Int64, Ptr{Cvoid}, Ptr{FFI.GDExtensionCallError}))),
        g(:INST_NOTIFICATION, @cfunction(_inst_notification, Cvoid, (Ptr{Cvoid}, Int32, UInt8))),
        g(:INST_TO_STRING, @cfunction(_inst_to_string, Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Ptr{Cvoid}))),
        g(:INST_REFCOUNT_INCREMENTED, @cfunction(_inst_refcount_incremented, Cvoid, (Ptr{Cvoid},))),
        g(:INST_REFCOUNT_DECREMENTED, @cfunction(_inst_refcount_decremented, UInt8, (Ptr{Cvoid},))),
        g(:INST_GET_SCRIPT, @cfunction(_inst_get_script, Ptr{Cvoid}, (Ptr{Cvoid},))),
        g(:INST_IS_PLACEHOLDER, @cfunction(_inst_is_placeholder, UInt8, (Ptr{Cvoid},))),
        C_NULL, C_NULL,                                                            # set/get fallback (placeholders only)
        g(:INST_GET_LANGUAGE, @cfunction(_inst_get_language, Ptr{Cvoid}, (Ptr{Cvoid},))),
        g(:INST_FREE, @cfunction(_inst_free, Cvoid, (Ptr{Cvoid},))))
    return nothing
end
