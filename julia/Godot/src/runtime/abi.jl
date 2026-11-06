# Mirrors native/src/gdjl_abi.h; keep both in sync.

const ABI_VERSION = UInt32(5)

const PRINT_STDOUT = Int32(0)
const PRINT_STDERR = Int32(1)

"Callbacks provided by the native host."
struct HostAPI
    abi_version::UInt32
    size::UInt32
    real_t_size::UInt32       # sizeof(real_t) of the Godot build the host was compiled for
    reserved::UInt32
    print::Ptr{Cvoid}         # void (int32 kind, const char *utf8, int64 len)
    report_error::Ptr{Cvoid}  # void (int32 is_warning, const char *func, const char *file, int32 line, const char *utf8, int64 len)
    string_out::Ptr{Cvoid}    # void (void *ctx, const char *utf8, int64 len)
    guard_callback::Ptr{Cvoid}  # void *(int32 id, void *julia_fn): thread-guarded trampoline for a callback
    report_script_error::Ptr{Cvoid}  # void (int32 is_warning, const char *func, const char *file, int32 line, const char *description, const char *message)
end

HostAPI() = HostAPI(0, 0, 0, 0, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL)

"Callbacks Godot may call from any thread, in the order of `GDJL_CALLBACKS` in gdjl_abi.h."
const CALLBACK_IDS = (:CALLABLE_CALL, :CALLABLE_FREE, :CALLABLE_HASH, :CALLABLE_EQUAL, :CALLABLE_LESS,
                      :CALLABLE_TO_STRING, :CALLABLE_ARGCOUNT, :BINDING_CREATE, :BINDING_FREE, :BINDING_REFERENCE,
                      :INST_SET, :INST_GET, :INST_GET_PROPERTY_LIST, :INST_FREE_PROPERTY_LIST,
                      :INST_PROPERTY_CAN_REVERT, :INST_PROPERTY_GET_REVERT, :INST_GET_OWNER, :INST_GET_PROPERTY_STATE,
                      :INST_GET_METHOD_LIST, :INST_FREE_METHOD_LIST, :INST_GET_PROPERTY_TYPE, :INST_VALIDATE_PROPERTY,
                      :INST_HAS_METHOD, :INST_GET_METHOD_ARGUMENT_COUNT, :INST_CALL, :INST_NOTIFICATION,
                      :INST_TO_STRING, :INST_REFCOUNT_INCREMENTED, :INST_REFCOUNT_DECREMENTED, :INST_GET_SCRIPT,
                      :INST_IS_PLACEHOLDER, :INST_GET_LANGUAGE, :INST_FREE)

"""
    guarded(name, fptr) -> Ptr{Cvoid}

Native trampoline for the `@cfunction` pointer `fptr` that adopts foreign threads and parks them GC-safe on return
(Julia's own wrappers would leave a newly adopted engine worker thread GC-unsafe, stalling every later collection).
Returns `fptr` itself when no native host is present (unit tests).
"""
function guarded(name::Symbol, fptr::Ptr{Cvoid})
    h = HOST[]
    h.guard_callback == C_NULL && return fptr
    id = findfirst(==(name), CALLBACK_IDS)
    id === nothing && error("unknown callback $name")
    return ccall(h.guard_callback, Ptr{Cvoid}, (Int32, Ptr{Cvoid}), Int32(id - 1), fptr)
end

"Entry points `Godot.Runtime` hands back to the native host."
struct JuliaAPI
    abi_version::UInt32
    size::UInt32
    eval_string::Ptr{Cvoid}   # int32 (const char *utf8, int64 len, void *ctx)
    shutdown::Ptr{Cvoid}      # void ()
    script_call::Ptr{Cvoid}   # void (const char *method, void *self, const Variant *const *args, int64 argc, Variant *r_ret)
end

const HOST = Ref(HostAPI())
const GET_PROC_ADDRESS = Ref{Ptr{Cvoid}}(C_NULL)
const LIBRARY = Ref{Ptr{Cvoid}}(C_NULL)

host_available() = HOST[].print != C_NULL

function host_print(kind::Int32, msg::AbstractString)
    s = String(msg)
    if host_available()
        GC.@preserve s ccall(HOST[].print, Cvoid, (Int32, Ptr{UInt8}, Int64), kind, pointer(s), sizeof(s))
    else
        Core.print(kind == PRINT_STDERR ? Core.stderr : Core.stdout, s, "\n")
    end
    return nothing
end

function host_report_error(is_warning::Bool, func::AbstractString, file::AbstractString, line::Integer, msg::AbstractString)
    f, p, s = String(func), String(file), String(msg)
    if host_available()
        GC.@preserve f p s ccall(HOST[].report_error, Cvoid, (Int32, Cstring, Cstring, Int32, Ptr{UInt8}, Int64),
                                 is_warning, f, p, line, pointer(s), sizeof(s))
    else
        Core.print(Core.stderr, is_warning ? "WARNING: " : "ERROR: ", s, "\n")
    end
    return nothing
end

"Report a script error or warning (a script error in Godot's debugger, with clickable source)."
function host_report_script_error(is_warning::Bool, func::AbstractString, file::AbstractString, line::Integer,
                                  description::AbstractString, msg::AbstractString)
    h = HOST[]
    h.report_script_error == C_NULL && return host_report_error(is_warning, func, file, line, msg)
    f, p = String(func), String(file)
    d, s = replace(String(description), '\0' => ' '), replace(String(msg), '\0' => ' ')
    ccall(h.report_script_error, Cvoid, (Int32, Cstring, Cstring, Int32, Cstring, Cstring), is_warning, f, p, line, d, s)
    return nothing
end

function host_string_out(ctx::Ptr{Cvoid}, msg::AbstractString)
    s = String(msg)
    GC.@preserve s ccall(HOST[].string_out, Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Int64), ctx, pointer(s), sizeof(s))
    return nothing
end
