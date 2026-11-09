#!/usr/bin/env julia
# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Regenerates julia/Godot/src/generated/ from native/api/ (fetching the API files first if needed).
# Usage: julia scripts/generate_bindings.jl [--precision=single|double]

const ROOT = normpath(joinpath(@__DIR__, ".."))

if !isfile(joinpath(ROOT, "native", "api", "extension_api.json"))
    run(`$(Base.julia_cmd()) --startup-file=no $(joinpath(@__DIR__, "fetch_api.jl"))`)
end

using Pkg
Pkg.activate(joinpath(ROOT, "julia", "GodotBindgen"); io = devnull)
Pkg.instantiate(; io = devnull)
using GodotBindgen

precision = "single"
for arg in ARGS
    m = match(r"^--precision=(single|double)$", arg)
    m === nothing && error("unknown argument: $arg")
    global precision = m[1]
end
println("Generated ", precision, "-precision bindings in ", GodotBindgen.generate(; precision))
