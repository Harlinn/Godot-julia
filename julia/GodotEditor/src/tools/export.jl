# Exporting games with Julia scripts (C#: GodotTools/Export/ExportPlugin.cs). The native `JuliaExportPlugin`
# forwards here; the payload (runtime, system image, environment) is built by the worker in a child process and
# shipped as the `data_<package>_<platform>_<arch>/` folder next to the executable. Design: ADR 0014.

const S_EXPORT_MODE = "julia/export/mode"
const S_EXPORT_SOURCES = "julia/export/include_sources"
const EXPORT_PLATFORMS = ("windows", "linux", "macos")
const EXPORT_ARCHES = ("x86_64", "x86_32", "arm64", "arm32", "universal")
const EXPORT_TIMEOUT = 4 * 3600

mutable struct ExportState
    plugin::Any
    mode::String
    keep_sources::Bool
end

const EXPORT = Ref{Union{Nothing, ExportState}}(nothing)
const ECHO = Ref(false)   # also print the job log (headless exports have no panel)

host_platform() = Sys.iswindows() ? "windows" : Sys.isapple() ? "macos" : Sys.islinux() ? "linux" : string(Sys.KERNEL)
host_arch() = Sys.ARCH === :aarch64 ? "arm64" : Sys.ARCH === :i686 ? "x86_32" : string(Sys.ARCH)
export_data_dir_name(package::AbstractString, platform::AbstractString, arch::AbstractString) =
    "data_$(package)_$(platform)_$(arch)"

"Why the preset cannot be exported with Julia from this editor, or `nothing`."
function export_blocker(platform, arch, mode::AbstractString, debug::Bool)
    platform === nothing && return "Julia scripting supports Windows, Linux and macOS exports only."
    platform == host_platform() && (arch == host_arch() || (platform == "macos" && arch == "universal")) ||
        return "Julia exports for $platform/$arch must be made on a $platform/$arch machine (this editor runs on " *
               "$(host_platform())/$(host_arch()); the system image is compiled for the host)."
    mode in ("sysimage", "jit") || return "unknown $(S_EXPORT_MODE) \"$mode\"."
    mode == "jit" && !debug && return "$(S_EXPORT_MODE) = jit is for debug exports only; use sysimage for release."
    return nothing
end

toml_string(s) = "\"" * escape_string(String(s)) * "\""

function export_config_text(; mode, debug, platform, arch, features, data_dir, global_classes)
    io = IOBuffer()
    println(io, "mode = ", toml_string(mode))
    println(io, "debug = ", debug)
    println(io, "platform = ", toml_string(platform))
    println(io, "arch = ", toml_string(arch))
    println(io, "features = [", join(toml_string.(features), ", "), "]")
    println(io, "data_dir = ", toml_string(data_dir))
    println(io, "[global_classes]")
    for (name, path) in sort!(collect(global_classes))
        println(io, toml_string(name), " = ", toml_string(path))
    end
    return String(take!(io))
end

function julia_global_classes()
    classes = Dict{String, String}()
    for d in Godot.get_global_class_list(Godot.ProjectSettings)
        String(d["language"]) == "Julia" && (classes[String(d["class"])] = String(d["path"]))
    end
    return classes
end

function export_error!(plugin, msg::AbstractString)
    log!("Julia export: $msg")
    Godot.Runtime.host_report_error(false, "export", "", 0, "Julia export: " * msg)
    platform = Godot.get_export_platform(plugin)
    platform === nothing || Godot.add_message(platform, EXPORT_MESSAGE_ERROR, "Julia", msg)
    return nothing
end

"Bridge handler for `JuliaExportPlugin::_export_begin`: build the Julia payload and add it to the export."
function export_begin(p::Ptr{Cvoid}, args)
    plugin = Godot.wrap_object(p, false)
    features = String[string(f) for f in args["features"]]
    debug = args["is_debug"] === true
    mode = string(something(Godot.get_option(plugin, S_EXPORT_MODE), "sysimage"))
    keep = mode == "jit" || Godot.get_option(plugin, S_EXPORT_SOURCES) === true
    EXPORT[] = ExportState(plugin, mode, keep)
    i = findfirst(in(features), EXPORT_PLATFORMS)
    platform = i === nothing ? nothing : EXPORT_PLATFORMS[i]
    j = findfirst(in(features), EXPORT_ARCHES)
    arch = j === nothing ? host_arch() : EXPORT_ARCHES[j]
    blocker = export_blocker(platform, arch, mode, debug)
    blocker === nothing || return export_error!(plugin, blocker)

    name = export_data_dir_name(package_name(), platform, arch)
    root = joinpath(project_dir(), ".godot", "julia_export")
    data = joinpath(root, name)
    rm(data; force = true, recursive = true)
    mkpath(data)
    config = joinpath(root, name * ".toml")
    write(config, export_config_text(; mode, debug, platform, arch, features, data_dir = data,
                                     global_classes = julia_global_classes()))
    ok = Ref(false)
    ECHO[] = true
    try
        start_job!("Julia export ($mode, $(debug ? "debug" : "release"))", ["export", config]; on_done = r -> (ok[] = r))
        wait_jobs!(EXPORT_TIMEOUT) || return export_error!(plugin, "the export build timed out")
    finally
        ECHO[] = false
    end
    ok[] || return export_error!(plugin, "building the Julia payload failed; see the Julia panel")
    Godot.add_shared_object(plugin, data, Godot.PackedStringArray(), "")
    return nothing
end

"""
Bridge handler for `JuliaExportPlugin::_export_file` (`.jl` files): ship an empty stub instead of the source; the
addon's own tool scripts are left out.
"""
function export_file(p::Ptr{Cvoid}, path)
    st = EXPORT[]
    st === nothing && return nothing
    plugin = Godot.wrap_object(p, false)
    path = String(path)
    startswith(path, "res://addons/godot_julia/") && return Godot.skip(plugin)
    st.keep_sources && return nothing
    Godot.add_file(plugin, path, Godot.PackedByteArray(), false)
    Godot.skip(plugin)
    return nothing
end

export_end(::Ptr{Cvoid}) = (EXPORT[] = nothing; nothing)
