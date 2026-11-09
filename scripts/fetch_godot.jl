#!/usr/bin/env julia
# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Downloads the pinned Godot editor (GODOT_VERSION) for this OS into .tools/godot/, verified against the release's
# SHA512-SUMS.txt. With --templates also the export templates archive (used by tests/export/run.jl).
# Usage: julia scripts/fetch_godot.jl [--templates]

using Downloads, SHA
import p7zip_jll

const ROOT = normpath(joinpath(@__DIR__, ".."))
const TAG = strip(read(joinpath(ROOT, "GODOT_VERSION"), String))
const DIR = joinpath(ROOT, ".tools", "godot")
const BASE_URL = "https://github.com/godotengine/godot/releases/download/$TAG/"

function editor_archive()
    Sys.iswindows() && return "Godot_v$(TAG)_win64.exe.zip"
    Sys.isapple() && return "Godot_v$(TAG)_macos.universal.zip"
    arch = Sys.ARCH === :aarch64 ? "arm64" : "x86_64"
    return "Godot_v$(TAG)_linux.$arch.zip"
end

function sums()
    file = joinpath(DIR, "SHA512-SUMS.txt")
    isfile(file) || Downloads.download(BASE_URL * "SHA512-SUMS.txt", file)
    return Dict(last(split(l)) => first(split(l)) for l in eachline(file) if !isempty(strip(l)))
end

function fetch(name)
    path = joinpath(DIR, name)
    expected = sums()[name]
    if !(isfile(path) && bytes2hex(open(sha512, path)) == expected)
        println("Downloading ", name)
        Downloads.download(BASE_URL * name, path)
        bytes2hex(open(sha512, path)) == expected || error("checksum mismatch for $name")
    end
    return path
end

function main()
    mkpath(DIR)
    zip = fetch(editor_archive())
    if Sys.isapple()
        # ditto keeps the .app bundle intact (symlinks, permissions, code signature).
        run(`ditto -x -k $zip $DIR`)
    else
        run(pipeline(`$(p7zip_jll.p7zip()) x $zip -o$DIR -y`; stdout = devnull))
    end
    if !Sys.iswindows()
        for f in readdir(DIR; join = true)
            occursin(r"^Godot_v.*\.(x86_64|arm64)$", basename(f)) && chmod(f, 0o755)
        end
        app = joinpath(DIR, "Godot.app", "Contents", "MacOS", "Godot")
        isfile(app) && chmod(app, 0o755)
    end
    "--templates" in ARGS && fetch("Godot_v$(TAG)_export_templates.tpz")
    println("Godot $TAG in ", DIR)
end

main()
