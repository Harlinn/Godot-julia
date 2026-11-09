#!/usr/bin/env julia
# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Dumps extension_api.json (with docs) and gdextension_interface.json from the pinned Godot into native/api/.
# Usage: julia scripts/fetch_api.jl [--project=path/to/project] [path/to/godot]   (or set GODOT)
# With --project, also writes project_extension_api.json: a dump made with that project's GDExtensions loaded. The
# bindings generator adds its extension classes (api_type "extension"/"editor_extension") to the engine API.
# Without a Godot binary, falls back to the docless copies bundled with godot-cpp.

const ROOT = normpath(joinpath(@__DIR__, ".."))
const API_DIR = joinpath(ROOT, "native", "api")
const PINNED = strip(read(joinpath(ROOT, "GODOT_VERSION"), String))
const API_FILES = ("extension_api.json", "gdextension_interface.json")
const PROJECT_API = joinpath(API_DIR, "project_extension_api.json")

const PROJECT = let i = findfirst(startswith("--project="), ARGS)
    i === nothing ? nothing : abspath(split(popat!(ARGS, i), "="; limit = 2)[2])
end

function find_godot()
    candidate = isempty(ARGS) ? get(ENV, "GODOT", "") : ARGS[1]
    isempty(candidate) || return abspath(candidate)
    for name in ("godot", "godot4", "Godot")
        path = Sys.which(name)
        path === nothing || return path
    end
    return nothing
end

function check_version(godot)
    version = strip(read(`$godot --version`, String))
    # `--version` prints e.g. "4.7.2.stable.official.abcdef"; the pin is "4.7.2-stable".
    expected = replace(PINNED, "-" => ".")
    startswith(version, expected) ||
        @warn "Godot version does not match GODOT_VERSION" found = version expected = PINNED
end

function dump_from_godot(godot)
    check_version(godot)
    cd(() -> run(`$godot --headless --dump-extension-api-with-docs --dump-gdextension-interface-json`), API_DIR)
    if PROJECT === nothing
        rm(PROJECT_API; force = true)
    else
        isfile(joinpath(PROJECT, "project.godot")) || error("not a Godot project: $PROJECT")
        # Godot 4.7 exits with an error for --dump-extension-api-with-docs once extensions are loaded, so this dump
        # has no docs. With --path, Godot writes it into the project directory.
        run(`$godot --headless --path $PROJECT --dump-extension-api`)
        mv(joinpath(PROJECT, "extension_api.json"), PROJECT_API; force = true)
    end
end

function copy_from_godot_cpp()
    m = match(r"^(\d+)\.(\d+)", PINNED)
    src = joinpath(ROOT, "native", "godot-cpp", "gdextension")
    api = joinpath(src, "extension_api-$(m[1])-$(m[2]).json")
    isfile(api) || error("No bundled API for $(PINNED) in $(src); install Godot and pass its path.")
    cp(api, joinpath(API_DIR, "extension_api.json"); force = true)
    cp(joinpath(src, "gdextension_interface.json"), joinpath(API_DIR, "gdextension_interface.json"); force = true)
end

function main()
    mkpath(API_DIR)
    godot = find_godot()
    if godot === nothing
        PROJECT === nothing || error("--project needs a Godot executable")
        @warn "Godot executable not found; using godot-cpp's bundled API files (no class docs)."
        copy_from_godot_cpp()
    else
        dump_from_godot(godot)
    end
    for f in API_FILES
        isfile(joinpath(API_DIR, f)) || error("Missing $(f) in $(API_DIR)")
    end
    println("API files written to ", API_DIR)
end

main()
