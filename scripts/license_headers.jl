#!/usr/bin/env julia
# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Adds the Apache-2.0 header to every source file git would publish; `--check` only lists files without it.
# Usage: julia scripts/license_headers.jl [--check]
# Skipped: native/godot-cpp (submodule, MIT) and the demo ports from godot-demo-projects (MIT, demos/LICENSE.md).

const ROOT = normpath(joinpath(@__DIR__, ".."))
const HEADER = ["Copyright 2026 Espen Harlinn", "SPDX-License-Identifier: Apache-2.0"]
const HASH_EXT = (".jl", ".gd", ".ps1", ".yml", ".yaml", ".py")
const SLASH_EXT = (".cpp", ".h", ".hpp", ".c")

function comment_prefix(path)
    ext = lowercase(splitext(path)[2])
    ext in SLASH_EXT && return "// "
    (ext in HASH_EXT || basename(path) == "SConstruct") && return "# "
    return nothing
end

published_files() = filter!(!isempty, split(read(Cmd(`git ls-files -z --cached --others --exclude-standard`; dir = ROOT), String), '\0'))

skipped(path, text) = startswith(path, "native/godot-cpp/") || startswith(text, "# Ported from godot-demo-projects")

has_header(text) = any(l -> occursin("SPDX-License-Identifier:", l), first(split(text, '\n'), 6))

function add_header(text, prefix)
    bom = startswith(text, "\ufeff") ? "\ufeff" : ""
    body = text[nextind(text, 0, length(bom) + 1):end]
    nl = occursin("\r\n", body) ? "\r\n" : "\n"
    header = join((prefix * h for h in HEADER), nl) * nl * nl
    if startswith(body, "#!")
        i = something(findfirst('\n', body), lastindex(body))
        return bom * body[1:i] * header * body[nextind(body, i):end]
    end
    return bom * header * body
end

function main(check::Bool)
    missing_ = String[]
    for rel in published_files()
        path = joinpath(ROOT, rel)
        prefix = comment_prefix(rel)
        (prefix === nothing || !isfile(path)) && continue
        text = read(path, String)
        (skipped(rel, text) || has_header(text)) && continue
        push!(missing_, rel)
        check || write(path, add_header(text, prefix))
    end
    if check
        isempty(missing_) || println("files without a license header:\n  ", join(missing_, "\n  "))
        return isempty(missing_)
    end
    println("added license headers to $(length(missing_)) files")
    return true
end

exit(main("--check" in ARGS) ? 0 : 1)
