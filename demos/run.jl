#!/usr/bin/env julia
# Runs every demo headlessly and fails on Godot errors, script errors or leaks.
# Usage: julia demos/run.jl [demo...]   (Godot from GODOT, .tools/godot/, or PATH; native editor library built)
# Games are played by demos/driver.gd, injected as an autoload through override.cfg (removed afterwards); it must
# print GDJL_DEMO_OK. multiplayer_pong runs a host and a client process that connect over ENet on localhost.
# editor_plugin runs in the headless editor with demos/editor_driver.gd added as a second plugin, which presses the
# Julia dock's button and checks the @tool node.
# A demo may list allowed ERROR/WARNING substrings in expect_errors.txt.
# parity: 11.2

const ROOT = normpath(joinpath(@__DIR__, ".."))
const TIMEOUT = parse(Float64, get(ENV, "GDJL_TEST_TIMEOUT", "300"))
include(joinpath(ROOT, "tests", "integration", "godot_path.jl"))

read_lines(path) = isfile(path) ? filter(!isempty, strip.(readlines(path))) : String[]

function start_godot(godot, args, log)
    io = open(log, "w")
    p = run(pipeline(ignorestatus(`$godot $args`); stdout = io, stderr = io); wait = false)
    timer = Timer(_ -> process_running(p) && kill(p), TIMEOUT)
    return (; p, io, timer, log)
end

function finish(h)
    wait(h.p)
    close(h.timer)
    close(h.io)
    return h.p.exitcode, read(h.log, String)
end

function output_failures(output, allowed)
    failures = String[]
    for line in eachline(IOBuffer(output))
        bad = occursin(r"leaked at exit|still in use at exit|Leaked instance", line) ||
              startswith(line, "ERROR:") || startswith(line, "SCRIPT ERROR:") || startswith(line, "WARNING:")
        bad && !any(a -> occursin(a, line), allowed) && push!(failures, "unexpected: $line")
    end
    occursin("GodotJL: Julia", output) || push!(failures, "Julia runtime did not start")
    return failures
end

function check_demo(godot, dir)
    name = basename(dir)
    dest = joinpath(dir, "addons", "godot_julia")
    mkpath(dirname(dest))
    cp(joinpath(ROOT, "addons", "godot_julia"), dest; force = true)
    mkpath(joinpath(dir, ".godot"))
    write(joinpath(dir, ".godot", "extension_list.cfg"), "res://addons/godot_julia/godot_julia.gdextension\n")
    failures = String[]
    code, _ = finish(start_godot(godot, ["--headless", "--path", dir, "--import"], joinpath(dir, ".godot", "gdjl_import.log")))
    code == 0 || push!(failures, "import failed")
    allowed = read_lines(joinpath(dir, "expect_errors.txt"))
    logdir = joinpath(dir, ".godot")
    override = joinpath(dir, "override.cfg")
    try
        if name == "editor_plugin"
            drv = joinpath(dir, "addons", "gdjl_demo_driver")
            mkpath(drv)
            cp(joinpath(@__DIR__, "editor_driver.gd"), joinpath(drv, "driver.gd"); force = true)
            write(joinpath(drv, "plugin.cfg"), "[plugin]\n\nname=\"GDJL demo driver\"\ndescription=\"\"\nauthor=\"\"\nversion=\"1\"\nscript=\"driver.gd\"\n")
            # The editor reads enabled plugins from project.godot only (not override.cfg); restored below.
            project = joinpath(dir, "project.godot")
            original = read(project, String)
            write(project, replace(original, "\"res://addons/julia_spinner/plugin.cfg\")" =>
                                             "\"res://addons/julia_spinner/plugin.cfg\", \"res://addons/gdjl_demo_driver/plugin.cfg\")"))
            h = start_godot(godot, ["--headless", "--editor", "--verbose", "--path", dir], joinpath(logdir, "gdjl_demo.log"))
            code, out = try
                finish(h)
            finally
                write(project, original)
                rm(drv; recursive = true, force = true)
            end
            code == 0 || push!(failures, "exited with $code")
            m = match(r"GDJL_DEMO_FAILED: [^\n]*", out)
            occursin("GDJL_DEMO_OK", out) || push!(failures, m === nothing ? "no GDJL_DEMO_OK" : m.match)
            append!(failures, output_failures(out, allowed))
        else
            cp(joinpath(@__DIR__, "driver.gd"), joinpath(logdir, "gdjl_driver.gd"); force = true)
            write(override, "[autoload]\n\nGdjlDemoDriver=\"*res://.godot/gdjl_driver.gd\"\n")
            roles = name == "multiplayer_pong" ? ["host", "client"] : ["play"]
            handles = map(roles) do role
                role == "client" && sleep(3)   # let the host start listening
                start_godot(godot, ["--headless", "--verbose", "--path", dir, "--", role], joinpath(logdir, "gdjl_demo_$role.log"))
            end
            for (role, h) in zip(roles, handles)
                code, out = finish(h)
                code == 0 || push!(failures, "$role exited with $code")
                m = match(r"GDJL_DEMO_FAILED: [^\n]*", out)
                occursin("GDJL_DEMO_OK", out) || push!(failures, "$role: " * (m === nothing ? "no GDJL_DEMO_OK" : m.match))
                append!(failures, ("$role: $f" for f in output_failures(out, allowed)))
            end
        end
    finally
        rm(override; force = true)
    end
    println(isempty(failures) ? "PASS  " : "FAIL  ", name)
    foreach(f -> println("      ", f), first(failures, 15))
    isempty(failures) || println("      logs: ", logdir)
    return isempty(failures)
end

function main()
    ENV["JULIA_PKG_OFFLINE"] = "true"
    godot = find_godot(ROOT)
    demos = filter(d -> isfile(joinpath(d, "project.godot")), readdir(@__DIR__; join = true))
    isempty(ARGS) || filter!(d -> basename(d) in ARGS, demos)
    results = [check_demo(godot, d) for d in demos]
    println(count(results), "/", length(results), " demos passed")
    exit(all(results) ? 0 : 1)
end

main()
