#!/usr/bin/env julia
# Runs every Godot project under tests/integration/ headlessly and checks it.
# Usage: julia tests/integration/run.jl [--leaks] [project_name...]   (Godot from GODOT, .tools/godot/, or PATH)
#
# A project passes when Godot exits with 0, prints `GDJL_TEST_RESULT {json}` (GodotTestRunner) with no failures,
# prints every line of `expect_output.txt` (substring match), every ERROR:/SCRIPT ERROR:/WARNING: line matches a
# substring in `expect_errors.txt`, and nothing reports leaked objects or resources (`--leaks` adds `--verbose`).
# The `--import` run is the editor: its output must contain every line of `expect_import_output.txt`.
# `run_args.txt` adds Godot arguments to the test run (e.g. `--editor` for headless editor tests).

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const TESTS = @__DIR__
const TIMEOUT = parse(Float64, get(ENV, "GDJL_TEST_TIMEOUT", "300"))

include(joinpath(@__DIR__, "godot_path.jl"))
find_godot() = find_godot(ROOT)

function run_godot(godot, args, log)
    open(log, "w") do io
        proc = run(pipeline(ignorestatus(`$godot $args`); stdout = io, stderr = io); wait = false)
        timed_out = Ref(false)
        timer = Timer(TIMEOUT) do _
            process_running(proc) || return
            timed_out[] = true
            kill(proc)
        end
        wait(proc)
        close(timer)
        return proc.exitcode, timed_out[]
    end
end

read_lines(path) = isfile(path) ? filter(!isempty, strip.(readlines(path))) : String[]

const LEAKS = Ref(false)
# The stock editor itself leaves an orphan StringName ("Node") at exit, so StringName reports are not checked.
const LEAK_PATTERN = r"leaked at exit|still in use at exit|Leaked instance"

"Counts from the `GDJL_TEST_RESULT {json}` line (GodotTestRunner), or `nothing`."
function parse_result(output::AbstractString)
    m = match(r"GDJL_TEST_RESULT (\{[^\n]*\})", output)
    m === nothing && return nothing
    field(k) = (f = match(Regex("\"$k\":(\\d+)"), m[1]); f === nothing ? 0 : parse(Int, f[1]))
    return (passed = field("passed"), failed = field("failed"), errored = field("errored"), broken = field("broken"))
end

function check_project(godot, dir)
    name = basename(dir)
    failures = String[]
    log = joinpath(dir, ".godot", "gdjl_test.log")
    mkpath(dirname(log))

    import_log = joinpath(dir, ".godot", "gdjl_import.log")
    code, timed_out = run_godot(godot, ["--headless", "--path", dir, "--import"], import_log)
    code == 0 || push!(failures, "import exited with $code" * (timed_out ? " (timeout)" : ""))
    import_output = read(import_log, String)
    for expected in read_lines(joinpath(dir, "expect_import_output.txt"))
        occursin(expected, import_output) || push!(failures, "missing import output: $expected")
    end

    run_args = read_lines(joinpath(dir, "run_args.txt"))
    LEAKS[] && push!(run_args, "--verbose")
    code, timed_out = run_godot(godot, ["--headless", run_args..., "--path", dir], log)
    output = read(log, String)
    timed_out && push!(failures, "timed out after $(TIMEOUT)s")
    code == 0 || push!(failures, "exited with $code")

    r = parse_result(output)
    if r === nothing
        push!(failures, "no GDJL_TEST_RESULT {json} line")
    elseif r.failed + r.errored > 0 || r.passed == 0
        push!(failures, "in-engine checks: passed=$(r.passed) failed=$(r.failed) errored=$(r.errored)")
    end
    for expected in read_lines(joinpath(dir, "expect_output.txt"))
        occursin(expected, output) || push!(failures, "missing output: $expected")
    end
    allowed = read_lines(joinpath(dir, "expect_errors.txt"))
    for line in eachline(IOBuffer(output))
        if occursin(LEAK_PATTERN, line)
            push!(failures, "leak: $line")
        elseif startswith(line, "ERROR:") || startswith(line, "WARNING:") || startswith(line, "SCRIPT ERROR:")
            any(a -> occursin(a, line), allowed) || push!(failures, "unexpected: $line")
        end
    end

    if isempty(failures)
        println("PASS  ", name)
    else
        println("FAIL  ", name)
        foreach(f -> println("      ", f), failures)
        println("      log: ", log)
    end
    return isempty(failures)
end

function main()
    # Editor builds run Pkg in child processes; tests must not touch the network.
    ENV["JULIA_PKG_OFFLINE"] = "true"
    if !isfile(joinpath(ROOT, "julia", "Godot", "src", "generated", "interface.jl"))
        run(`$(Base.julia_cmd()) --startup-file=no $(joinpath(ROOT, "scripts", "generate_bindings.jl"))`)
    end
    include(joinpath(ROOT, "scripts", "prepare_test_projects.jl"))
    godot = find_godot()
    println("Using ", godot)
    projects = filter(d -> isfile(joinpath(d, "project.godot")), readdir(TESTS; join = true))
    LEAKS[] = "--leaks" in ARGS
    names = filter(a -> !startswith(a, "--"), ARGS)
    isempty(names) || filter!(d -> basename(d) in names, projects)
    results = [check_project(godot, dir) for dir in projects]
    println(count(results), "/", length(results), " projects passed")
    exit(all(results) ? 0 : 1)
end

main()
