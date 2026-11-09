# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

"""
    GodotBindgen

Generates the `Godot` package's engine bindings from `extension_api.json` and `gdextension_interface.json`
(analog of `modules/mono/editor/bindings_generator.cpp`).
"""
module GodotBindgen

using JSON

const REPO_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))

"Second line of every generated file: the API data and docs come from Godot."
const SOURCE_NOTICE = "# Derived from the Godot Engine API and class reference (MIT License, Godot Engine contributors)."

"Directory where `scripts/fetch_api.jl` stores the dumped API files."
api_dir() = joinpath(REPO_ROOT, "native", "api")

"Directory that receives generated code (gitignored)."
output_dir() = joinpath(REPO_ROOT, "julia", "Godot", "src", "generated")

"Directory that receives the generated editor-only API of package `GodotEditor` (gitignored)."
editor_output_dir() = joinpath(REPO_ROOT, "julia", "GodotEditor", "src", "generated")

include("ctypes.jl")
include("interface.jl")
include("layout.jl")
include("bbcode.jl")
include("context.jl")
include("structs.jl")
include("classes.jl")
include("builtin_methods.jl")
include("globals.jl")

"""
    generate(; api_dir, out_dir, editor_out_dir, precision = "single")

Write the generated sources (`interface.jl`, `layout.jl`, `method_hashes.tsv`, `builtin_structs.jl`, `global_enums.jl`,
`classes.jl`, `globals.jl`) and `binding_report.txt` into `out_dir`, and the editor-only `classes.jl` into
`editor_out_dir`. `precision` must match the Godot build (`"single"` or `"double"`).
"""
function generate(; api_dir::AbstractString = api_dir(), out_dir::AbstractString = output_dir(),
                  editor_out_dir::AbstractString = editor_output_dir(), precision::AbstractString = "single")
    precision in ("single", "double") || throw(ArgumentError("precision must be \"single\" or \"double\""))
    api = JSON.parsefile(joinpath(api_dir, "extension_api.json"); dicttype = Dict{String, Any})
    project_api = joinpath(api_dir, "project_extension_api.json")
    isfile(project_api) && merge_extension_classes!(api, JSON.parsefile(project_api; dicttype = Dict{String, Any}))
    iface = JSON.parsefile(joinpath(api_dir, "gdextension_interface.json"); dicttype = Dict{String, Any})
    mkpath(out_dir)
    write_atomically(io -> generate_interface(io, iface), joinpath(out_dir, "interface.jl"))
    write_atomically(io -> generate_layout(io, api, iface; precision), joinpath(out_dir, "layout.jl"))
    write_atomically(io -> generate_hashes(io, api), joinpath(out_dir, "method_hashes.tsv"))
    write_atomically(io -> generate_builtin_structs(io, api, iface; precision), joinpath(out_dir, "builtin_structs.jl"))
    write_atomically(io -> generate_global_enums(io, api), joinpath(out_dir, "global_enums.jl"))
    ctx = nothing
    write_atomically(joinpath(out_dir, "classes.jl")) do io
        ctx = generate_classes(io, api; precision)
    end
    write_atomically(io -> generate_globals(io, api, ctx; precision), joinpath(out_dir, "globals.jl"))
    builtin_ctx = nothing
    write_atomically(joinpath(out_dir, "builtin_methods.jl")) do io
        builtin_ctx = generate_builtin_methods(io, api; precision)
    end
    mkpath(editor_out_dir)
    editor_ctx = nothing
    write_atomically(joinpath(editor_out_dir, "classes.jl")) do io
        editor_ctx = generate_editor_classes(io, api; precision)
    end
    write_atomically(io -> generate_report(io, ctx, editor_ctx, builtin_ctx), joinpath(out_dir, "binding_report.txt"))
    return out_dir
end

function write_atomically(f, path)
    tmp = path * ".tmp"
    open(f, tmp, "w")
    mv(tmp, path; force = true)
    return path
end

"""
    merge_extension_classes!(api, project_api) -> api

Add the classes and singletons that other GDExtensions registered (`api_type` `"extension"`/`"editor_extension"`)
from `project_api`, a dump made with a project's extensions loaded (`scripts/fetch_api.jl --project=...`).
"""
function merge_extension_classes!(api, project_api)
    known = Set(c["name"] for c in api["classes"])
    added = Set{String}()
    for c in project_api["classes"]
        if c["api_type"] in ("extension", "editor_extension") && !(c["name"] in known)
            push!(api["classes"], c)
            push!(added, c["name"])
        end
    end
    append!(api["singletons"], [s for s in project_api["singletons"] if s["type"] in added])
    return api
end

end # module GodotBindgen
