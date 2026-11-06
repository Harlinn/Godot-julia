# @cfunction targets must be defined before the function that takes their address.
function _eval_string(code::Ptr{UInt8}, len::Int64, ctx::Ptr{Cvoid})::Int32
    @godot_entry Int32(1) begin
        result = include_string(Main, unsafe_string(code, len), "JuliaRuntime.eval_string")
        host_string_out(ctx, repr(result))
        Internals.flush_releases!()
        Int32(0)
    end
end

function _shutdown()::Cvoid
    @godot_entry nothing begin
        Base._atexit(Int32(0))   # user `atexit` hooks; the host never calls jl_atexit_hook (see julia_host.cpp)
        stop_debug_server!()
        GC.gc()
        Internals.flush_releases!()
        release_scripts!()
        Godot.release_bindings!()
        destroy_script_strings!()
        FFI.shutdown!()
        restore_output!()
        HOST[] = HostAPI()
        nothing
    end
end

"""
    __init_runtime__(get_proc_address, library, host, out) -> Bool

Called once by the native host after Julia starts. Stores the GDExtension interface pointers and host callbacks,
redirects output to Godot, and writes the runtime's entry points into `out`.
"""
function __init_runtime__(get_proc_address::Ptr{Cvoid}, library::Ptr{Cvoid}, host::Ptr{HostAPI}, out::Ptr{JuliaAPI})
    api = unsafe_load(host)
    api.abi_version == ABI_VERSION || error("native host ABI v$(api.abi_version) does not match Godot.Runtime ABI v$(ABI_VERSION)")
    api.size >= sizeof(HostAPI) || error("native host API table is too small")
    unsafe_load(out).size >= sizeof(JuliaAPI) || error("native Julia API table is too small")

    HOST[] = api
    GET_PROC_ADDRESS[] = get_proc_address
    LIBRARY[] = library
    get_proc_address == C_NULL || (FFI.init!(get_proc_address, library, api.real_t_size); Godot.init_bindings!())
    install_output!()

    unsafe_store!(out, JuliaAPI(ABI_VERSION, sizeof(JuliaAPI),
                                @cfunction(_eval_string, Int32, (Ptr{UInt8}, Int64, Ptr{Cvoid})),
                                @cfunction(_shutdown, Cvoid, ()),
                                @cfunction(_script_call, Cvoid, (Ptr{UInt8}, Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Int64, Ptr{Cvoid}))))
    init_instance_info!()
    init_callable_fns!()
    return true
end

const GODOT_EDITOR = Base.PkgId(Base.UUID("5b0e7c3a-1d64-4c8e-9f2b-6a7d3e9c41f0"), "GodotEditor")

"""
    load_editor_api!() -> Module

Load the editor-only engine API (package `GodotEditor`, analog of GodotSharpEditor) and bind it as `Godot.Editor`.
The native host calls this only when the Godot editor runs.
"""
function load_editor_api!()
    isdefined(Godot, :Editor) && return getglobal(Godot, :Editor)
    mod = Base.require(GODOT_EDITOR)
    Core.eval(Godot, :(const Editor = $mod))
    return mod
end
