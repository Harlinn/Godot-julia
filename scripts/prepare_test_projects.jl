#!/usr/bin/env julia
# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Copies addons/godot_julia into every project under tests/integration/ so they can load the built extension.

const ROOT = normpath(joinpath(@__DIR__, ".."))
const ADDON = joinpath(ROOT, "addons", "godot_julia")
const TESTS = joinpath(ROOT, "tests", "integration")

for name in readdir(TESTS)
    project = joinpath(TESTS, name)
    isfile(joinpath(project, "project.godot")) || continue
    dest = joinpath(project, "addons", "godot_julia")
    mkpath(dirname(dest))
    cp(ADDON, dest; force = true)
    # Pre-register the extension: a headless editor that discovers a .gdextension during its first scan
    # crashes at exit (godotengine/godot#111048, #123511).
    mkpath(joinpath(project, ".godot"))
    write(joinpath(project, ".godot", "extension_list.cfg"), "res://addons/godot_julia/godot_julia.gdextension\n")
    println("Synced addon into ", relpath(dest, ROOT))
end
