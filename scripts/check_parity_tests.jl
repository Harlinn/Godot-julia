#!/usr/bin/env julia
# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Checks that every DONE row of docs/csharp-parity-matrix.md is covered by a test that tags it, e.g.
#   # parity: 5.6, 5.7, 6.1–6.6
# in julia/*/test/, tests/integration/, tests/export/, demos/run.jl and scripts/doctest_docs.jl (ranges use - or –
# within one section).
# Usage: julia scripts/check_parity_tests.jl   (exit code 1 when a DONE row has no test or a tag names no row)

const ROOT = normpath(joinpath(@__DIR__, ".."))
const MATRIX = joinpath(ROOT, "docs", "csharp-parity-matrix.md")

"Rows of the matrix: id => status word (DONE, PARTIAL, TODO, GAP)."
function matrix_rows(path = MATRIX)
    rows = Dict{String, String}()
    for line in eachline(path)
        m = match(r"^\|\s*(\d+\.\d+)\s*\|.*\|\s*(DONE|PARTIAL|TODO|GAP)\b[^|]*\|\s*$", line)
        m === nothing || (rows[m[1]] = m[2])
    end
    return rows
end

"Row ids named by a tag list such as `2.1, 2.3, 4.4–4.8`."
function expand_tags(list::AbstractString)
    ids = String[]
    for m in eachmatch(r"(\d+)\.(\d+)(?:\s*[-–]\s*(?:(\d+)\.)?(\d+))?", list)
        major, lo = m[1], parse(Int, m[2])
        hi = m[4] === nothing ? lo : parse(Int, m[4])
        m[3] === nothing || m[3] == major || error("range across sections: $(m.match)")
        append!(ids, ["$major.$i" for i in lo:hi])
    end
    return ids
end

function test_files(root = ROOT)
    files = String[]
    dirs = [joinpath(root, "tests", "integration"), joinpath(root, "tests", "export")]
    for pkg in readdir(joinpath(root, "julia"); join = true)
        isdir(joinpath(pkg, "test")) && push!(dirs, joinpath(pkg, "test"))
    end
    for d in dirs, (dir, subdirs, names) in walkdir(d)
        filter!(s -> !(s in (".godot", "godot_julia", "out")), subdirs)
        append!(files, joinpath(dir, n) for n in names if endswith(n, ".jl") || endswith(n, ".gd"))
    end
    for f in (joinpath(root, "demos", "run.jl"), joinpath(root, "scripts", "doctest_docs.jl"))
        isfile(f) && push!(files, f)
    end
    return files
end

"Tagged row id => files tagging it."
function tagged_rows(files)
    tags = Dict{String, Vector{String}}()
    for f in files, line in eachline(f)
        m = match(r"parity:\s*([0-9][0-9.,\s\-–]*)", line)
        m === nothing && continue
        for id in expand_tags(m[1])
            push!(get!(tags, id, String[]), relpath(f, ROOT))
        end
    end
    return tags
end

function main()
    rows = matrix_rows()
    tags = tagged_rows(test_files())
    done = sort!([id for (id, s) in rows if s == "DONE"]; by = id -> parse.(Int, split(id, '.')))
    missing_ = filter(id -> !haskey(tags, id), done)
    unknown = sort!(filter(id -> !haskey(rows, id), collect(keys(tags))))
    println("$(length(done)) DONE rows, $(length(done) - length(missing_)) tagged by tests")
    isempty(missing_) || println("DONE rows without a tagged test: ", join(missing_, ", "))
    isempty(unknown) || println("tags naming no matrix row: ", join(("$id ($(join(unique(tags[id]), ", ")))" for id in unknown), "; "))
    return isempty(missing_) && isempty(unknown)
end

abspath(PROGRAM_FILE) == @__FILE__() && exit(main() ? 0 : 1)
