#!/usr/bin/env julia
# Assembles the distributable addon zip: addons/godot_julia with the native libraries found in its bin/ (all
# platforms in a release build), the Godot and GodotEditor packages including generated bindings, icons, script
# templates and tools. Usage: julia scripts/package_addon.jl [output_dir]   -> godot_julia-v<ver>-godot<tag>.zip

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

function main(out = joinpath(ROOT, "dist"))
    isfile(joinpath(ROOT, "julia", "Godot", "src", "generated", "classes.jl")) ||
        error("generate the bindings first: julia scripts/generate_bindings.jl")
    libs = filter(n -> occursin(r"^libgodot_julia\.", n), readdir(joinpath(ADDON, "bin")))
    isempty(libs) && error("no native libraries in $(joinpath(ADDON, "bin")); build native/ first")
    version = TOML.parsefile(joinpath(ROOT, "julia", "Godot", "Project.toml"))["version"]
    tag = strip(read(joinpath(ROOT, "GODOT_VERSION"), String))
    stage = mktempdir()
    dst = joinpath(stage, "addons", "godot_julia")
    copy_filtered(ADDON, dst; skip_dirs = ("julia",))
    for f in readdir(joinpath(dst, "bin"); join = true)
        any(ext -> endswith(f, ext), (".exp", ".lib", ".pdb", ".ilk")) && rm(f; force = true)
    end
    for pkg in PACKAGES
        copy_filtered(joinpath(ROOT, "julia", pkg), joinpath(dst, "julia", pkg))
    end
    license = joinpath(ROOT, "LICENSE")
    isfile(license) && cp(license, joinpath(dst, "LICENSE"); force = true)
    out = abspath(out)
    mkpath(out)
    zip = joinpath(out, "godot_julia-v$(version)-godot$(tag).zip")
    rm(zip; force = true)
    cd(stage) do
        run(pipeline(`$(p7zip_jll.p7zip()) a -tzip -mx=7 $zip addons`; stdout = devnull))
    end
    rm(stage; recursive = true, force = true)
    println("Addon: ", zip, " (", round(filesize(zip) / 2^20; digits = 1), " MiB; libraries: ", join(libs, ", "), ")")
    return zip
end

main(isempty(ARGS) ? joinpath(ROOT, "dist") : ARGS[1])
