#!/usr/bin/env julia
# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Runs tests/benchmarks/project headlessly and compares each GDJL_BENCH result with baseline.toml.
# Usage: julia tests/benchmarks/run.jl [--update]    (--update rewrites the baselines for this machine)
# A benchmark fails when it is slower than baseline × tolerance (default 3: shared CI machines are noisy).
# How the numbers are measured and the C# comparison: docs/perf.md, "Benchmarks".

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const PROJECT = joinpath(@__DIR__, "project")
const BASELINE = joinpath(@__DIR__, "baseline.toml")
const TOLERANCE = parse(Float64, get(ENV, "GDJL_BENCH_TOLERANCE", "3"))

import TOML

include(joinpath(ROOT, "tests", "integration", "godot_path.jl"))

function main()
    godot = find_godot(ROOT)
    dest = joinpath(PROJECT, "addons", "godot_julia")
    mkpath(dirname(dest))
    cp(joinpath(ROOT, "addons", "godot_julia"), dest; force = true)
    mkpath(joinpath(PROJECT, ".godot"))
    write(joinpath(PROJECT, ".godot", "extension_list.cfg"), "res://addons/godot_julia/godot_julia.gdextension\n")
    run(pipeline(`$godot --headless --path $PROJECT --import`; stdout = devnull, stderr = devnull))
    output = read(ignorestatus(`$godot --headless --path $PROJECT`), String)
    results = Dict{String, Float64}()
    for m in eachmatch(r"GDJL_BENCH \{\"name\":\"([^\"]+)\",\"ns\":([0-9.eE+-]+)\}", output)
        results[m[1]] = parse(Float64, m[2])
    end
    occursin("GDJL_BENCH_DONE", output) || (println(output); error("benchmarks did not finish"))
    if "--update" in ARGS
        open(BASELINE, "w") do io
            println(io, "# ns per operation; machine: ", get(ENV, "GDJL_BENCH_MACHINE", Sys.MACHINE), ", ", Sys.cpu_info()[1].model)
            TOML.print(io, Dict(k => round(v; digits = 1) for (k, v) in results); sorted = true)
        end
        println("Baselines written to ", BASELINE)
    end
    base = isfile(BASELINE) ? TOML.parsefile(BASELINE) : Dict{String, Any}()
    ok = true
    for name in sort!(collect(keys(results)))
        ns = results[name]
        b = get(base, name, nothing)
        status = b === nothing ? "new" : ns <= b * TOLERANCE ? "ok" : (ok = false; "SLOWER")
        println(rpad(name, 32), lpad(string(round(ns; digits = 1)), 10), " ns",
                b === nothing ? "" : "   baseline $(b) ns ($(round(ns / b; digits = 2))x)", "   ", status)
    end
    for name in keys(base)
        haskey(results, name) || (ok = false; println(rpad(name, 32), "   MISSING"))
    end
    exit(ok ? 0 : 1)
end

main()
