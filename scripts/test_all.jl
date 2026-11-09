#!/usr/bin/env julia
# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Runs the whole test suite locally (what CI runs). Usage, from the repository root:
#   julia scripts/test_all.jl [--no-build] [--precision=single|double] [--exports] [--benchmarks] [--no-leaks]
# Steps: build native/ (editor target; plus templates with --exports), generate bindings, Julia unit tests of every
# package, the parity-test check, headless integration tests with leak checks, doc tests, demos, then optionally export
# tests and
# benchmarks. Needs Julia, SCons + a C++ toolchain and a Godot editor binary (GODOT, .tools/godot/ or PATH;
# `julia scripts/fetch_godot.jl` downloads the pinned one). Extra SCons arguments: GDJL_SCONS_ARGS.

const ROOT = normpath(joinpath(@__DIR__, ".."))
const JULIA = Base.julia_cmd()
flag(name) = name in ARGS
const PRECISION = something(match(r"^--precision=(single|double)$", join(filter(startswith("--precision="), ARGS))), (; captures = ["single"])).captures[1]

const RESULTS = Pair{String, Bool}[]

function step(name, cmd; env = Dict{String, String}())
    println("\n==> ", name)
    ok = success(pipeline(setenv(ignorestatus(cmd), merge(copy(ENV), env)); stdout, stderr))
    push!(RESULTS, name => ok)
    ok || println("FAILED: ", name)
    return ok
end

function main()
    cd(ROOT)
    include(joinpath(ROOT, "tests", "integration", "godot_path.jl"))
    # fetch_api.jl needs the editor binary for class docs.
    haskey(ENV, "GODOT") || (ENV["GODOT"] = Base.invokelatest(find_godot, ROOT))
    load_path = join([joinpath(ROOT, "julia"), "@stdlib"], Sys.iswindows() ? ";" : ":")
    scons_extra = split(get(ENV, "GDJL_SCONS_ARGS", ""))
    if !flag("--no-build")
        targets = flag("--exports") ? ["editor", "template_debug", "template_release"] : ["editor"]
        for t in targets
            step("native build ($t, $PRECISION)", `scons -C native target=$t precision=$PRECISION -j$(Sys.CPU_THREADS) $scons_extra`) || return false
        end
    end
    step("generate bindings ($PRECISION)", `$JULIA --startup-file=no scripts/generate_bindings.jl --precision=$PRECISION`) || return false
    step("precompile Godot", `$JULIA --startup-file=no --project=julia/Godot -e "using Pkg; Pkg.instantiate(); using Godot"`)
    step("unit tests: Godot", `$JULIA --startup-file=no --project=julia/Godot -e "using Pkg; Pkg.test()"`)
    step("unit tests: GodotBindgen", `$JULIA --startup-file=no --project=julia/GodotBindgen -e "using Pkg; Pkg.test()"`)
    for pkg in ("GodotEditor", "GodotTestRunner")
        step("unit tests: $pkg", `$JULIA --startup-file=no julia/$pkg/test/runtests.jl`; env = Dict("JULIA_LOAD_PATH" => load_path))
    end
    step("parity-test check", `$JULIA --startup-file=no scripts/check_parity_tests.jl`)
    step("license headers", `$JULIA --startup-file=no scripts/license_headers.jl --check`)
    leaks = flag("--no-leaks") ? String[] : ["--leaks"]
    step("integration tests" * (isempty(leaks) ? "" : " (with leak checks)"), `$JULIA --startup-file=no tests/integration/run.jl $leaks`)
    step("doc tests", `$JULIA --startup-file=no scripts/doctest_docs.jl`)
    step("demos", `$JULIA --startup-file=no demos/run.jl`)
    flag("--exports") && step("export tests", `$JULIA --startup-file=no tests/export/run.jl`)
    flag("--benchmarks") && step("benchmarks", `$JULIA --startup-file=no tests/benchmarks/run.jl`)
    return all(last, RESULTS)
end

ok = main()
println("\nSummary:")
foreach(((name, r),) -> println(r ? "  PASS  " : "  FAIL  ", name), RESULTS)
exit(ok ? 0 : 1)
