# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Method binds, singletons, and the ptrcall / Variant-call paths.

const METHOD_BINDS = Dict{Tuple{Symbol, Symbol, Int64}, Ptr{Cvoid}}()
const SINGLETONS = Dict{Symbol, Ptr{Cvoid}}()
const LOOKUP_LOCK = ReentrantLock()

"""
    method_bind(class, method[, hash]) -> Ptr{Cvoid}

Cached `MethodBind` for `class.method`. Without `hash`, the hash is looked up in the generated table.
"""
function method_bind(class::Symbol, method::Symbol, hash::Int64)
    @lock LOOKUP_LOCK get!(METHOD_BINDS, (class, method, hash)) do
        p = classdb_get_method_bind(string_name_ptr(class), string_name_ptr(method), hash)
        p == C_NULL && error("Godot has no method $class.$method with hash $hash")
        p
    end
end
method_bind(class::Symbol, method::Symbol) = method_bind(class, method, method_hash(class, method))

"Pointer to the engine singleton `name` (e.g. `:OS`)."
function singleton(name::Symbol)
    @lock LOOKUP_LOCK get!(SINGLETONS, name) do
        p = global_get_singleton(string_name_ptr(name))
        p == C_NULL && error("Godot has no singleton named $name")
        p
    end
end

"Builtin-type method pointer (`GDExtensionPtrBuiltInMethod`)."
function builtin_method(type::Int32, method::Symbol, hash::Int64)
    p = variant_get_ptr_builtin_method(type, string_name_ptr(method), hash)
    p == C_NULL && error("Godot has no builtin method $method with hash $hash for variant type $type")
    return p
end

"Utility function pointer (`GDExtensionPtrUtilityFunction`)."
function utility_function(name::Symbol, hash::Int64 = utility_hash(name))
    p = variant_get_ptr_utility_function(string_name_ptr(name), hash)
    p == C_NULL && error("Godot has no utility function $name with hash $hash")
    return p
end

function reset_calls!()
    @lock LOOKUP_LOCK begin
        empty!(METHOD_BINDS)
        empty!(SINGLETONS)
    end
    return nothing
end

# --- ptrcall code generation ------------------------------------------------------------------
# Arguments are boxed in `Ref`s whose pointers are gathered in a `Ref{NTuple}`; Julia keeps all of them on the
# stack, so calls with isbits arguments do not allocate.

function args_code(N::Int)
    refs = [Symbol(:arg, i) for i in 1:N]
    setup = [:($(refs[i]) = Ref(args[$i])) for i in 1:N]
    if N == 0
        return setup, refs, :(nothing), :(Ptr{Ptr{Cvoid}}(C_NULL))
    end
    tuple = Expr(:tuple, (:(Base.unsafe_convert(Ptr{Cvoid}, $r)) for r in refs)...)
    argv_ptr = :(Ptr{Ptr{Cvoid}}(Base.unsafe_convert(Ptr{NTuple{$N, Ptr{Cvoid}}}, argv)))
    return setup, refs, :(Ref($tuple)), argv_ptr
end

needs_initialized_return(::Type) = false
needs_initialized_return(::Type{<:RawBuiltin}) = true
needs_initialized_return(::Type{RawVariant}) = true

# Godot assigns into ptrcall return slots, so types with destructors must be constructed first.
function return_code(R::Type)
    R === Nothing && return :(ret = nothing), :(C_NULL), :(nothing)
    init = needs_initialized_return(R) ? :(ret = Ref(construct($R))) : :(ret = Ref{$R}())
    return init, :ret, :(ret[])
end

function ptrcall_body(R::Type, N::Int, call::Function)
    setup, refs, argv, argv_ptr = args_code(N)
    ret_init, ret_ptr, ret_value = return_code(R)
    return quote
        $(setup...)
        $ret_init
        GC.@preserve $(refs...) ret begin
            argv = $argv
            GC.@preserve argv $(call(argv_ptr, ret_ptr))
        end
        $ret_value
    end
end

"""
    ptrcall(R, method_bind, object, args...) -> R

Call an engine method with `object_method_bind_ptrcall`. `args` are isbits values laid out as Godot expects
(`Int64`, `Float64`, `Bool`, `Raw*` builtins, object pointers as `Ptr{Cvoid}`); they are borrowed. Use
`R = Nothing` for methods without a return value; `Raw*`/`RawVariant` results are owned by the caller.
"""
@generated function ptrcall(::Type{R}, method_bind::Ptr{Cvoid}, object::Ptr{Cvoid}, args::Vararg{Any, N}) where {R, N}
    return ptrcall_body(R, N, (argv, ret) -> :(ccall(INTERFACE[].object_method_bind_ptrcall, Cvoid,
                                                    (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Ptr{Cvoid}),
                                                    method_bind, object, $argv, $ret)))
end

"""
    ptrcall_gcsafe(R, method_bind, object, args...) -> R

[`ptrcall`](@ref) for engine methods that may block (`WorkerThreadPool.wait_for_task_completion`, `Mutex.lock`, ...):
the thread is GC-safe during the call, so Julia code on other threads (e.g. the awaited task) can collect garbage.
"""
@generated function ptrcall_gcsafe(::Type{R}, method_bind::Ptr{Cvoid}, object::Ptr{Cvoid}, args::Vararg{Any, N}) where {R, N}
    fptr = Expr(:$, :(INTERFACE[].object_method_bind_ptrcall))
    return ptrcall_body(R, N, (argv, ret) -> :(@ccall gc_safe = true $fptr(method_bind::Ptr{Cvoid}, object::Ptr{Cvoid},
                                                                          $argv::Ptr{Ptr{Cvoid}}, $ret::Ptr{Cvoid})::Cvoid))
end

"""
    builtin_ptrcall(R, method, base, args...) -> R

Call a builtin-type method obtained from [`builtin_method`](@ref). `base` points to the receiver (`C_NULL` for
static methods); mutating methods modify it in place.
"""
@generated function builtin_ptrcall(::Type{R}, method::Ptr{Cvoid}, base::Ptr{Cvoid}, args::Vararg{Any, N}) where {R, N}
    return ptrcall_body(R, N, (argv, ret) -> :(ccall(method, Cvoid, (Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Ptr{Cvoid}, Cint),
                                                    base, $argv, $ret, $N)))
end

"""
    utility_ptrcall(R, func, args...) -> R

Call a utility function obtained from [`utility_function`](@ref).
"""
@generated function utility_ptrcall(::Type{R}, func::Ptr{Cvoid}, args::Vararg{Any, N}) where {R, N}
    return ptrcall_body(R, N, (argv, ret) -> :(ccall(func, Cvoid, (Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Cint),
                                                    $ret, $argv, $N)))
end

# --- Variant call path (varargs methods) -------------------------------------------------------

"Error reported by Godot when a Variant call fails (mirrors `GDExtensionCallError`)."
struct GodotCallError <: Exception
    error::Int32
    argument::Int32
    expected::Int32
end

const CALL_ERROR_NAMES = Dict(
    GDEXTENSION_CALL_ERROR_INVALID_METHOD => "invalid method",
    GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT => "invalid argument",
    GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS => "too many arguments",
    GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS => "too few arguments",
    GDEXTENSION_CALL_ERROR_INSTANCE_IS_NULL => "instance is null",
    GDEXTENSION_CALL_ERROR_METHOD_NOT_CONST => "method not const",
)

function Base.showerror(io::IO, e::GodotCallError)
    print(io, "GodotCallError: ", get(CALL_ERROR_NAMES, e.error, "error $(e.error)"))
    if e.error == GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT
        print(io, " (argument ", e.argument + 1, " should be variant type ", e.expected, ")")
    elseif e.error in (GDEXTENSION_CALL_ERROR_TOO_MANY_ARGUMENTS, GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS)
        print(io, " (expected ", e.expected, ")")
    end
end

"""
    variant_call(method_bind, object, args::AbstractVector{RawVariant}) -> RawVariant

Call an engine method through `object_method_bind_call` (required for varargs methods). Arguments are borrowed;
the result is owned by the caller. Throws [`GodotCallError`](@ref) on failure.
"""
function variant_call(method_bind::Ptr{Cvoid}, object::Ptr{Cvoid}, args::AbstractVector{RawVariant})
    argv = Vector{RawVariant}(args)
    ptrs = Ptr{Cvoid}[pointer(argv, i) for i in eachindex(argv)]
    ret = Ref{RawVariant}()
    err = Ref(GDExtensionCallError(GDEXTENSION_CALL_OK, 0, 0))
    GC.@preserve argv ptrs object_method_bind_call(method_bind, object, ptrs, length(argv), ret, err)
    if err[].error != GDEXTENSION_CALL_OK
        destroy!(ret[])
        throw(GodotCallError(err[].error, err[].argument, err[].expected))
    end
    return ret[]
end
