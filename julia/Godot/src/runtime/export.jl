# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Exported games (ADR 0014). An export build evaluates every script into a module inside the process that writes the
# game's system image (`julia --output-o`), so scripts ship compiled and load by `res://` path without their sources,
# like C# ships assemblies (GodotTools/Export/ExportPlugin.cs).

"A script compiled into an exported game: its module, its class and the scripts it needs (base classes, `script_type`)."
struct PrecompiledScript
    mod::Module
    info::ScriptClassInfo
    deps::Vector{String}
end

const PRECOMPILED_SCRIPTS = Dict{String, PrecompiledScript}()

"State of an export build: script sources and global classes by name, the preset's feature tags."
struct ExportBuild
    sources::Dict{String, String}
    global_classes::Dict{String, String}
    features::Set{String}
    building::Set{String}
end

const EXPORT_BUILD = Ref{Union{Nothing, ExportBuild}}(nothing)
"`data_*` folder of an exported game (set by the native host); holds sources of scripts not compiled into the image."
const EXPORT_DIR = Ref("")

is_exported() = !isempty(EXPORT_DIR[])
is_precompiled(m::Module) = any(p -> p.mod === m, values(PRECOMPILED_SCRIPTS))

function exported_source(path::AbstractString)
    is_exported() && startswith(path, "res://") || return nothing
    f = joinpath(EXPORT_DIR[], "scripts", String(path)[7:end])
    return isfile(f) ? read(f, String) : nothing
end

"Evaluate the script at `path` for the export build (its dependencies first); throws on errors."
function build_script!(path::String)
    pre = get(PRECOMPILED_SCRIPTS, path, nothing)
    pre === nothing || return pre
    b = EXPORT_BUILD[]::ExportBuild
    source = get(b.sources, path, nothing)
    source === nothing && error("script $path is not part of the export")
    path in b.building && error("script $path depends on itself")
    push!(b.building, path)
    try
        @lock LOAD_LOCK begin
            _, ctx, _, _ = eval_script(path, source; report = false)
            info, _, msg = file_class_info(path, ctx.classes)
            info === nothing && error(msg)
            pre = PrecompiledScript(info.mod, info, unique(ctx.dep_paths))
            PRECOMPILED_SCRIPTS[path] = pre
            return pre
        end
    finally
        delete!(b.building, path)
    end
end

"""
    precompile_scripts!(sources, global_classes, features) -> Dict{String, String}

Export build step: compile every script (`res://` path => source) and its methods for the system image, with the
preset's feature tags as compile-time constants for `Godot.@feature`. Returns the scripts that failed (path =>
error); those are shipped as sources and evaluated at runtime.
"""
function precompile_scripts!(sources::AbstractDict, global_classes::AbstractDict, features)
    EXPORT_BUILD[] = ExportBuild(Dict{String, String}(sources), Dict{String, String}(global_classes),
                                 Set{String}(string.(features)), Set{String}())
    failed = Dict{String, String}()
    try
        for path in sort!(collect(keys(sources)))
            try
                build_script!(path)
            catch e
                failed[path] = sprint(showerror, e isa LoadError ? e.error : e)
            end
        end
    finally
        EXPORT_BUILD[] = nothing
    end
    precompile_script_methods!()
    return failed
end

"Compile the methods of compiled scripts for their instance types (the export's ReadyToRun workload)."
function precompile_script_methods!()
    concrete = IdDict{Any, Any}()
    mods = Set{Module}()
    for pre in values(PRECOMPILED_SCRIPTS)
        push!(mods, pre.mod)
        for ci in class_chain(pre.info)
            concrete[ci.type] = ci.instance_type
            concrete[ci.instance_type] = ci.instance_type
        end
        precompile(pre.info.defaults, ())
    end
    sigs = Any[]
    Base.visit(Core.methodtable) do m
        m isa Method && m.sig isa DataType || return
        params = m.sig.parameters
        m.module in mods || any(p -> haskey(concrete, p), params) || return
        ps = Any[get(concrete, p, p) for p in params]
        all(isconcretetype, ps) && push!(sigs, Tuple{ps...})
    end
    n = count(sig -> try precompile(sig) catch; false end, sigs)
    return n
end
