# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Child process for editor builds and package actions (C#: the `dotnet build` process GodotTools runs).
# Usage: julia worker.jl <packages_dir> <depot or -> <project_dir> <verbosity> <command> [args...]
# Output protocol (one record per line): `GDJL_STEP\t<text>`, `GDJL_PROBLEM\t<severity>\t<file>\t<line>\t<col>\t<message>`;
# anything else is log text. Exit code 0 means success.

const PACKAGES, DEPOT, PROJECT = ARGS[1], ARGS[2], ARGS[3]
const VERBOSITY = parse(Int, ARGS[4])
const COMMAND = ARGS[5]
const REST = ARGS[6:end]
const GODOT = Base.PkgId(Base.UUID("f37c0048-e111-4823-9dfb-7d6ad2e3f4cb"), "Godot")

redirect_stderr(stdout)
empty!(LOAD_PATH)
append!(LOAD_PATH, ["@", PACKAGES, "@stdlib"])
DEPOT == "-" || pushfirst!(DEPOT_PATH, DEPOT)
const TOML_PATH = joinpath(PROJECT, "Project.toml")
isfile(TOML_PATH) && (Base.ACTIVE_PROJECT[] = TOML_PATH)

one_line(s) = replace(String(s), r"[\r\n\t]+" => " ")
step(s) = (println("GDJL_STEP\t", s); flush(stdout))
problem(severity, file, line, col, msg) =
    (println("GDJL_PROBLEM\t", severity, "\t", file, "\t", line, "\t", col, "\t", one_line(msg)); flush(stdout))

using Pkg

function pkg_step(f, what)
    step(what)
    try
        f()
        return true
    catch e
        problem("error", isfile(TOML_PATH) ? "res://Project.toml" : "", 1, 1, "$what failed: " * sprint(showerror, e))
        return false
    end
end

"Every user .jl file (the addon's own Julia packages and hidden folders are not scripts)."
function script_files(root)
    files = String[]
    for (dir, dirs, names) in walkdir(root)
        filter!(d -> !startswith(d, "."), dirs)
        rel = relpath(dir, root)
        rel == "." || (rel = replace(rel, '\\' => '/'))
        rel == "addons" && filter!(d -> d != "godot_julia", dirs)
        for n in names
            endswith(n, ".jl") && push!(files, joinpath(dir, n))
        end
    end
    return sort!(files)
end

res_path(file) = "res://" * replace(relpath(file, PROJECT), '\\' => '/')

function build()
    ok = true
    if isfile(TOML_PATH)
        ok &= pkg_step(Pkg.instantiate, "Pkg.instantiate")
        ok &= pkg_step(Pkg.precompile, "Pkg.precompile")
    end
    step("Validating scripts")
    Godot = Base.require(GODOT)
    validate = Godot.Runtime.language_validate
    files = script_files(PROJECT)
    errors = 0
    for f in files
        path = res_path(f)
        VERBOSITY >= 2 && println("  ", path)
        r = Base.invokelatest(validate, C_NULL, read(f, String), path, false, true, false, false)
        for e in r["errors"]
            problem("error", e["path"], e["line"], e["column"], e["message"])
            errors += 1
        end
    end
    VERBOSITY >= 1 && println("Validated $(length(files)) script(s): $(errors) error(s).")
    return ok && errors == 0
end

function pkg(cmd, names)
    isfile(TOML_PATH) || (problem("error", "", 0, 0, "No Project.toml: create the Julia project first."); return false)
    cmd == "add" && return pkg_step(() -> Pkg.add(names), "Pkg.add $(join(names, ' '))")
    cmd == "rm" && return pkg_step(() -> Pkg.rm(names), "Pkg.rm $(join(names, ' '))")
    cmd == "update" && return pkg_step(() -> Pkg.update(), "Pkg.update")
    cmd == "status" && return pkg_step(() -> Pkg.status(), "Pkg.status")
    problem("error", "", 0, 0, "unknown package command $cmd")
    return false
end

ok = try
    if COMMAND == "build"
        build()
    elseif COMMAND == "pkg"
        pkg(REST[1], REST[2:end])
    elseif COMMAND == "export"
        include(joinpath(@__DIR__, "export_build.jl"))
        @invokelatest export_game(REST[1])
    else
        problem("error", "", 0, 0, "unknown command $COMMAND")
        false
    end
catch e
    problem("error", "", 0, 0, sprint(showerror, e, catch_backtrace()))
    false
end
flush(stdout)
exit(ok ? 0 : 1)
