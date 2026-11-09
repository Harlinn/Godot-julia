#!/usr/bin/env julia
# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Assembles the distributable addon zip: addons/godot_julia with the native libraries found in its bin/ (all
# platforms in a release build), the Godot and GodotEditor packages including generated bindings, icons, script
# templates and tools. Usage: julia scripts/package_addon.jl [output_dir] [--precision=single|double]
#   -> Godot-julia-v<ver>-godot<tag>.zip (double: ...-double.zip, holding only the double-precision libraries).
# The bindings must have been generated for the same precision (scripts/generate_bindings.jl --precision=...).

import p7zip_jll
import TOML

const ROOT = normpath(joinpath(@__DIR__, ".."))
const ADDON = joinpath(ROOT, "addons", "godot_julia")
const PACKAGES = ("Godot", "GodotEditor")

function copy_filtered(src, dst; skip_dirs = ("test", ".git"))
    for (dir, subdirs, names) in walkdir(src)
        filter!(d -> !(d in skip_dirs), subdirs)
        rel = relpath(dir, src)
        for n in names
            (n == "Manifest.toml" || endswith(n, ".cov") || endswith(n, ".mem")) && continue
            target = joinpath(dst, rel, n)
            mkpath(dirname(target))
            cp(joinpath(dir, n), target; force = true)
        end
    end
end

is_double_lib(name) = occursin(".double.", name)

function generated_precision()
    layout = read(joinpath(ROOT, "julia", "Godot", "src", "generated", "layout.jl"), String)
    return occursin("const real_t = Float64", layout) ? "double" : "single"
end

function main(out = joinpath(ROOT, "dist"); precision = "single")
    isfile(joinpath(ROOT, "julia", "Godot", "src", "generated", "classes.jl")) ||
        error("generate the bindings first: julia scripts/generate_bindings.jl --precision=$precision")
    generated_precision() == precision ||
        error("bindings are $(generated_precision())-precision; run scripts/generate_bindings.jl --precision=$precision")
    double = precision == "double"
    libs = filter(n -> occursin(r"^libgodot_julia\.", n) && is_double_lib(n) == double, readdir(joinpath(ADDON, "bin")))
    isempty(libs) && error("no $precision-precision native libraries in $(joinpath(ADDON, "bin")); build native/ first")
    version = TOML.parsefile(joinpath(ROOT, "julia", "Godot", "Project.toml"))["version"]
    tag = strip(read(joinpath(ROOT, "GODOT_VERSION"), String))
    stage = mktempdir()
    dst = joinpath(stage, "addons", "godot_julia")
    copy_filtered(ADDON, dst; skip_dirs = ("julia",))
    for f in readdir(joinpath(dst, "bin"); join = true)
        any(ext -> endswith(f, ext), (".exp", ".lib", ".pdb", ".ilk")) && rm(f; force = true)
        startswith(basename(f), "libgodot_julia.") && is_double_lib(basename(f)) != double &&
            rm(f; force = true, recursive = true)
    end
    for pkg in PACKAGES
        copy_filtered(joinpath(ROOT, "julia", pkg), joinpath(dst, "julia", pkg))
    end
    for name in ("LICENSE", "NOTICE")
        cp(joinpath(ROOT, name), joinpath(dst, name); force = true)
    end
    out = abspath(out)
    mkpath(out)
    zip = joinpath(out, "Godot-julia-v$(version)-godot$(tag)$(double ? "-double" : "").zip")
    rm(zip; force = true)
    cd(stage) do
        run(pipeline(`$(p7zip_jll.p7zip()) a -tzip -mx=7 $zip addons`; stdout = devnull))
    end
    rm(stage; recursive = true, force = true)
    println("Addon: ", zip, " (", round(filesize(zip) / 2^20; digits = 1), " MiB; libraries: ", join(libs, ", "), ")")
    return zip
end

let precision = "single", out = joinpath(ROOT, "dist")
    for arg in ARGS
        m = match(r"^--precision=(single|double)$", arg)
        if m !== nothing
            precision = m[1]
        elseif startswith(arg, "--")
            error("unknown argument: $arg")
        else
            out = arg
        end
    end
    main(out; precision)
end
