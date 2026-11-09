#!/usr/bin/env julia
# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Extracts every ```julia block from docs/user/*.md and runs it inside a headless Godot project (the doc test).
# Usage: julia scripts/doctest_docs.jl [page.md...]
#
# Rules, per page (blocks of one page run in order and share one module, so later blocks see earlier names):
# - A block defining a `@godot_class` is a script: written to res://<page>/<Class>.jl and loaded as a script
#   resource (like a file in a project); other code in later blocks can use it via `Godot.script_type`.
# - Other blocks are evaluated in the page module, inside a running engine (a Godot task, so `@await` works).
#   `@test` from Test is available; each block must run without throwing.
# - ```julia {no-run} marks snippets that cannot run on their own (shell, editor-only or fragment); the reason
#   goes on the first line as a comment.
# parity: 9.6, 11.1

const ROOT = normpath(joinpath(@__DIR__, ".."))
const DOCS = joinpath(ROOT, "docs", "user")
const WORK = joinpath(ROOT, ".tools", "doctest")
const TIMEOUT = parse(Float64, get(ENV, "GDJL_TEST_TIMEOUT", "600"))
include(joinpath(ROOT, "tests", "integration", "godot_path.jl"))

struct Block
    page::String
    line::Int
    code::String
    norun::Bool
end

function extract(path)
    blocks = Block[]
    lines = readlines(path)
    i = 1
    while i <= length(lines)
        m = match(r"^```julia(.*)$", lines[i])
        if m === nothing
            i += 1
            continue
        end
        start = i
        i += 1
        body = String[]
        while i <= length(lines) && !startswith(lines[i], "```")
            push!(body, lines[i])
            i += 1
        end
        push!(blocks, Block(basename(path), start, join(body, "\n"), occursin("no-run", m[1])))
        i += 1
    end
    return blocks
end

script_class(code) = (m = match(r"@godot_class\s+(?:abstract\s+)?mutable\s+struct\s+(\w+)", code); m === nothing ? nothing : m[1])

function write_project(pages)
    rm(WORK; force = true, recursive = true)
    mkpath(WORK)
    write(joinpath(WORK, "project.godot"), """
        config_version=5

        [application]

        config/name="Godot-julia doc tests"
        run/main_scene="res://main.tscn"
        config/features=PackedStringArray("4.7")

        [julia]

        runtime/threads=2
        """)
    write(joinpath(WORK, "main.tscn"), """
        [gd_scene load_steps=2 format=3]

        [ext_resource type="Script" path="res://main.gd" id="1"]

        [node name="Main" type="Node"]
        script = ExtResource("1")
        """)
    write(joinpath(WORK, "main.gd"), """
        extends Node

        func _ready() -> void:
        \tJuliaRuntime.eval_string("include(raw\\"%s\\")" % ProjectSettings.globalize_path("res://doctest_runner.jl"))
        """)
    cases = String[]
    for (page, blocks) in pages
        dir = joinpath(WORK, splitext(page)[1])
        mkpath(dir)
        for (k, b) in enumerate(blocks)
            b.norun && continue
            cls = script_class(b.code)
            if cls !== nothing
                rel = "res://$(splitext(page)[1])/$cls.jl"
                write(joinpath(dir, "$cls.jl"), b.code)
                push!(cases, "(\"$page\", $(b.line), :script, $(repr(rel)))")
            else
                file = joinpath(dir, "block$k.jl")
                write(file, b.code)
                push!(cases, "(\"$page\", $(b.line), :code, $(repr(file)))")
            end
        end
    end
    write(joinpath(WORK, "doctest_runner.jl"), """
        using Test, Godot, GodotTestRunner

        const CASES = [$(join(cases, ",\n    "))]

        # Make a script's class and functions usable from later blocks of the page (run at the latest world age).
        function import_script!(mod, T)
            smod = parentmodule(T)
            Core.eval(mod, Expr(:const, Expr(:(=), nameof(T), T)))
            for n in names(smod; all = true)
                s = string(n)
                (startswith(s, "#") || n in (:eval, :include) || isdefined(mod, n)) && continue
                v = getglobal(smod, n)
                v isa Function && Core.eval(mod, Expr(:const, Expr(:(=), n, v)))
            end
        end

        root = Godot.get_root(Godot.get_main_loop(Godot.Engine))
        main = Godot.get_node(root, "Main")
        GodotTestRunner.run_tests(main, "doc tests") do
            modules = Dict{String, Module}()
            for (page, line, kind, target) in CASES
                mod = get!(modules, page) do
                    m = Module(Symbol(replace(page, "." => "_")))
                    Core.eval(m, :(using Godot, Test))
                    Core.eval(m, :(const DOC_ROOT = \$main))   # a Node in the running scene for examples
                    m
                end
                @testset "\$page:\$line" begin
                    if kind === :script
                        res = Base.invokelatest(Godot.load, Godot.ResourceLoader, target)
                        @test res !== nothing && (Base.invokelatest(Godot.can_instantiate, res) ||
                                                  Base.invokelatest(Godot.is_abstract, res))
                        T = Base.invokelatest(Godot.script_type, target)
                        Base.invokelatest(import_script!, mod, T)
                    else
                        Base.invokelatest(Base.include, mod, target)
                    end
                end
            end
        end
        """)
end

function main()
    # Pages are paths or bare names of docs/user pages (`julia_signals.md`).
    page_file(a) = isfile(a) ? abspath(a) : joinpath(DOCS, a)
    files = isempty(ARGS) ? filter(f -> endswith(f, ".md"), readdir(DOCS; join = true)) : page_file.(ARGS)
    pages = [(basename(f), extract(f)) for f in files]
    nblocks = sum(length(b) for (_, b) in pages)
    norun = sum(count(x -> x.norun, b) for (_, b) in pages)
    write_project(pages)
    dest = joinpath(WORK, "addons", "godot_julia")
    mkpath(dirname(dest))
    cp(joinpath(ROOT, "addons", "godot_julia"), dest; force = true)
    mkpath(joinpath(WORK, ".godot"))
    write(joinpath(WORK, ".godot", "extension_list.cfg"), "res://addons/godot_julia/godot_julia.gdextension\n")
    godot = find_godot(ROOT)
    ENV["JULIA_PKG_OFFLINE"] = "true"
    run(pipeline(ignorestatus(`$godot --headless --path $WORK --import`); stdout = devnull, stderr = devnull))
    log = joinpath(WORK, "doctest.log")
    p = open(log, "w") do io
        p = run(pipeline(ignorestatus(`$godot --headless --path $WORK`); stdout = io, stderr = io); wait = false)
        t = Timer(_ -> process_running(p) && kill(p), TIMEOUT)
        wait(p)
        close(t)
        p
    end
    output = read(log, String)
    for line in eachline(IOBuffer(output))
        (startswith(line, "FAILED") || startswith(line, "SCRIPT ERROR") || startswith(line, "ERROR:")) && println(line)
    end
    m = match(r"GDJL_TEST_RESULT \{[^\n]*\"passed\":(\d+),\"failed\":(\d+),\"errored\":(\d+)", output)
    println("$(length(pages)) pages, $nblocks julia blocks ($norun marked no-run)")
    if m === nothing
        println("doc tests did not report a result (log: $log)")
        exit(1)
    end
    println("doc tests: passed=$(m[1]) failed=$(m[2]) errored=$(m[3])")
    exit(p.exitcode == 0 && m[2] == "0" && m[3] == "0" ? 0 : 1)
end

main()
