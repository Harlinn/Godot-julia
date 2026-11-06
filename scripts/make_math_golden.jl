#!/usr/bin/env julia
# Regenerates julia/Godot/test/fixtures/math_golden.txt by evaluating math_cases.txt in Godot (GDScript).
# Usage: julia scripts/make_math_golden.jl   (Godot from GODOT, .tools/godot/, or PATH)

const ROOT = normpath(joinpath(@__DIR__, ".."))
const FIXTURES = joinpath(ROOT, "julia", "Godot", "test", "fixtures")

function find_godot()
    godot = get(ENV, "GODOT", "")
    isempty(godot) || return godot
    tools = joinpath(ROOT, ".tools", "godot")
    if isdir(tools)
        for f in readdir(tools; join = true)
            occursin(r"^Godot_v.*(_console\.exe|\.x86_64|\.arm64|\.universal)$", basename(f)) && return f
        end
    end
    path = Sys.which("godot")
    path === nothing && error("Godot not found: set GODOT or put the editor binary in .tools/godot/")
    return path
end

cases = joinpath(FIXTURES, "math_cases.txt")
golden = joinpath(FIXTURES, "math_golden.txt")
run(`$(find_godot()) --headless --path $(joinpath(ROOT, "tests", "golden")) --script res://make_golden.gd -- $cases $golden`)
lines = filter(l -> !startswith(l, "#"), readlines(golden))
bad = filter(l -> endswith(l, "!COMPILE_ERROR"), lines)
isempty(bad) || error("cases that GDScript could not compile:\n" * join(bad, "\n"))
println("Wrote ", length(lines), " golden values to ", relpath(golden, ROOT))
