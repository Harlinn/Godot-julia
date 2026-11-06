# Background jobs (builds and Pkg actions) run in a child Julia process polled every frame, so the editor never
# freezes (C#: GodotTools/Build/BuildManager.cs runs `dotnet build` and streams its output to the MSBuild panel).

struct Problem
    severity::Symbol
    file::String
    line::Int
    col::Int
    message::String
end

mutable struct Job
    title::String
    pid::Int
    pipes::Vector{Any}       # FileAccess: stdout, stderr
    partial::Vector{String}  # incomplete last line per pipe
    on_done::Any             # ok::Bool -> nothing
end

const MAX_LOG_LINES = 5000
const LOG = String[]
const PROBLEMS = Problem[]
const JOB = Ref{Union{Nothing, Job}}(nothing)
const QUEUE = Tuple{String, Vector{String}, Any}[]
const LAST_BUILD_OK = Ref{Union{Nothing, Bool}}(nothing)

problems() = copy(PROBLEMS)
busy() = JOB[] !== nothing || !isempty(QUEUE)
last_build_ok() = LAST_BUILD_OK[]

function log!(s::AbstractString)
    for line in split(s, '\n')
        push!(LOG, line)
        length(LOG) > MAX_LOG_LINES && popfirst!(LOG)
        panel_log!(line)
        ECHO[] && println(line)
    end
    return nothing
end

function clear_output!()
    empty!(LOG)
    empty!(PROBLEMS)
    panel_clear!()
    return nothing
end

"Parse a `GDJL_PROBLEM` record (see worker.jl)."
function parse_problem(line::AbstractString)
    parts = split(line, '\t'; limit = 6)
    length(parts) == 6 || return nothing
    return Problem(Symbol(parts[2]), parts[3], something(tryparse(Int, parts[4]), 0), something(tryparse(Int, parts[5]), 0), parts[6])
end

function handle_line!(line::AbstractString)
    line = rstrip(line, '\r')
    if startswith(line, "GDJL_PROBLEM\t")
        p = parse_problem(line)
        p === nothing && return log!(line)
        push!(PROBLEMS, p)
        panel_problem!(p)
        log!(isempty(p.file) ? "$(p.severity): $(p.message)" : "$(p.file):$(p.line):$(p.col): $(p.severity): $(p.message)")
    elseif startswith(line, "GDJL_STEP\t")
        log!("==> " * line[length("GDJL_STEP\t")+1:end])
    else
        log!(line)
    end
    return nothing
end

julia_exe() = joinpath(Sys.BINDIR, Base.julia_exename())
worker_script() = joinpath(@__DIR__, "worker.jl")
# Godot drops empty arguments when building a command line, so "no depot" is passed as "-".
depot_setting() = (d = string(something(Godot.get_setting(Godot.ProjectSettings, "julia/runtime/depot_path"), "")); isempty(d) ? "-" : d)

worker_args(command::Vector{String}) =
    String["--startup-file=no", "--history-file=no", worker_script(), packages_dir(), depot_setting(), project_dir(),
           string(Int(build_verbosity())), command...]

set_plugin_processing(on::Bool) = (s = PLUGIN[]; s === nothing || Godot.set_process(s.plugin, on); nothing)

"Run the worker with `command`; `on_done(ok)` runs on the main thread when it exits. Jobs run one at a time."
function start_job!(title::AbstractString, command::Vector{String}; on_done = nothing)
    if JOB[] !== nothing
        push!(QUEUE, (String(title), command, on_done))
        return nothing
    end
    log!("==> $title")
    d = Godot.execute_with_pipe(Godot.OS, julia_exe(), worker_args(command), false)
    if isempty(d)
        log!("$title: could not start $(julia_exe())")
        on_done === nothing || on_done(false)
        return nothing
    end
    JOB[] = Job(String(title), Int(d["pid"]), Any[d["stdio"], d["stderr"]], ["", ""], on_done)
    panel_status!("$title…")
    set_plugin_processing(true)
    return nothing
end

function read_pipe!(job::Job, i::Int)
    pipe = job.pipes[i]
    while true
        data = Godot.get_buffer(pipe, 65536)
        isempty(data) && break
        text = job.partial[i] * String(Vector{UInt8}(data))
        lines = split(text, '\n')
        job.partial[i] = String(pop!(lines))
        foreach(handle_line!, lines)
    end
    return nothing
end

"Stream new output of the running job; finish it when the process has exited (called every frame while busy)."
function poll_job!()
    job = JOB[]
    job === nothing && return nothing
    running = Godot.is_process_running(Godot.OS, job.pid)
    read_pipe!(job, 1)
    read_pipe!(job, 2)
    running && return nothing
    for i in 1:2
        isempty(job.partial[i]) || handle_line!(job.partial[i])
        Godot.close(job.pipes[i])
    end
    ok = Godot.get_process_exit_code(Godot.OS, job.pid) == 0
    JOB[] = nothing
    log!("$(job.title) $(ok ? "succeeded" : "failed")")
    panel_status!("$(job.title) $(ok ? "succeeded" : "failed")")
    if job.on_done !== nothing
        try
            job.on_done(ok)
        catch e
            Godot.Runtime.report_exception(e, catch_backtrace())
        end
    end
    if isempty(QUEUE)
        UI_PENDING[] || set_plugin_processing(false)
    else
        title, command, on_done = popfirst!(QUEUE)
        start_job!(title, command; on_done)
    end
    return nothing
end

"Block until every job finished (the Play button waits for its build, like C#)."
function wait_jobs!(timeout::Real = 600)
    t0 = time()
    while busy() && time() - t0 < timeout
        poll_job!()
        busy() && Libc.systemsleep(0.02)
    end
    return !busy()
end

reload_scripts!() = Base.invokelatest(Godot.Runtime.language_reload_all_scripts, C_NULL)

"""
    build!(; on_done = nothing)

Instantiate and precompile the project environment, validate every script, then hot-reload scripts on success.
"""
function build!(; on_done = nothing)
    empty!(PROBLEMS)
    panel_clear_problems!()
    start_job!("Build", ["build"]; on_done = ok -> begin
        LAST_BUILD_OK[] = ok
        ok && reload_scripts!()
        on_done === nothing || on_done(ok)
    end)
    return nothing
end

pkg_job!(sub::AbstractString, names::Vector{String} = String[]) =
    start_job!("Pkg $sub $(join(names, ' '))", vcat(["pkg", String(sub)], names))
