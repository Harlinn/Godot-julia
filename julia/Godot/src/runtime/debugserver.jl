# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Debug REPL server (docs/debugging.md): a localhost TCP REPL into the running game, used by the debug client
# (addons/godot_julia/tools/godot_repl.jl), VS Code's "Connect external REPL" snippet and `Godot.@breakpoint` sessions.
# Protocol: each request is one line (a Julia string with escaped newlines); each response is text followed by a
# `GDJL_END` line. Requests are evaluated on the main thread once per frame, so the game state is consistent.

import Sockets

const DEBUG_SERVER = Ref{Any}(nothing)
const DEBUG_CLIENTS = Any[]
const DEBUG_REQUESTS = Channel{Tuple{Any, String}}(Inf)
const END_MARK = "GDJL_END"
const IN_BREAK = Ref(false)

debug_server_running() = DEBUG_SERVER[] !== nothing
has_debug_client() = any(isopen, DEBUG_CLIENTS)
debug_server_port() = (s = DEBUG_SERVER[]; s === nothing ? 0 : Int(Sockets.getsockname(s)[2]))

"Listen on 127.0.0.1:`port` (0 picks a free port); returns the port."
function start_debug_server!(port::Integer)
    debug_server_running() && return debug_server_port()
    srv = Sockets.listen(Sockets.IPv4("127.0.0.1"), port)
    DEBUG_SERVER[] = srv
    errormonitor(@async accept_loop(srv))
    return debug_server_port()
end

function accept_loop(srv)
    while isopen(srv)
        sock = try
            Sockets.accept(srv)
        catch
            break
        end
        push!(DEBUG_CLIENTS, sock)
        errormonitor(@async read_loop(sock))
    end
    return nothing
end

function read_loop(sock)
    try
        while isopen(sock)
            line = readline(sock)
            if isempty(line)
                eof(sock) && break
                continue
            end
            put!(DEBUG_REQUESTS, (sock, unescape_string(line)))
        end
    catch
    end
    filter!(s -> s !== sock, DEBUG_CLIENTS)
    return nothing
end

function stop_debug_server!()
    srv = DEBUG_SERVER[]
    srv === nothing && return nothing
    DEBUG_SERVER[] = nothing
    foreach(s -> try close(s) catch end, DEBUG_CLIENTS)
    empty!(DEBUG_CLIENTS)
    try close(srv) catch end
    return nothing
end

function respond(sock, text::AbstractString)
    try
        write(sock, text, isempty(text) || endswith(text, '\n') ? "" : "\n", END_MARK, "\n")
    catch
    end
    return nothing
end

"Evaluate a request (in `Main`, or with the locals of a breakpoint) capturing its output; returns the reply text."
function eval_request(code::AbstractString; state::Union{Nothing, DebugState} = nothing)
    buf = IOBuffer()
    out, err = stdout, stderr
    setglobal!(Base, :stdout, buf)
    setglobal!(Base, :stderr, buf)
    result = try
        v = Base.invokelatest(eval_in_state, state, code)
        v === nothing ? "" : sprint(show, MIME"text/plain"(), v; context = :limit => true)
    catch e
        sprint(showerror, e, catch_backtrace())
    finally
        setglobal!(Base, :stdout, out)
        setglobal!(Base, :stderr, err)
    end
    printed = String(take!(buf))
    return isempty(printed) || isempty(result) ? printed * result : printed * (endswith(printed, '\n') ? "" : "\n") * result
end

"Answer pending requests (called every frame by the scheduler while the server runs)."
function process_debug_requests!()
    IN_BREAK[] && return nothing   # a @breakpoint session owns the requests
    while isready(DEBUG_REQUESTS)
        sock, code = take!(DEBUG_REQUESTS)
        respond(sock, eval_request(code))
    end
    return nothing
end

"A `@breakpoint` session on the debug clients: evaluate with the locals until a client sends `continue`."
function debug_server_break(state::DebugState)
    clients = filter(isopen, DEBUG_CLIENTS)
    (isempty(clients) || IN_BREAK[]) && return false
    IN_BREAK[] = true
    try
        loc = isempty(state.frames) ? "" : " at $(res_path(string(state.frames[1].file))):$(state.frames[1].line)"
        names_ = join((string(k) for (k, _) in state.locals), ", ")
        foreach(s -> respond(s, "GDJL_BREAK $(state.error)$loc; locals: $names_\nEvaluate expressions; `continue` resumes the game."), clients)
        while true
            sock, code = take!(DEBUG_REQUESTS)   # the game is paused here
            if strip(code) in ("continue", "c")
                respond(sock, "continuing")
                break
            end
            respond(sock, eval_request(code; state))
        end
    finally
        IN_BREAK[] = false
    end
    return true
end

"Block until a debug client connects (`julia/debugger/wait_for_attach`)."
function wait_for_debug_client!(; timeout::Real = Inf)
    t0 = time()
    while !has_debug_client() && time() - t0 < timeout
        sleep(0.05)
    end
    return has_debug_client()
end

"Start the debug server in debug builds of a running game when `julia/debugger/port` (or `GDJL_DEBUG_PORT`) is set."
function start_debugging!()
    FFI.INITIALIZED[] || return nothing
    (editor_hint() || debug_server_running() || !Godot.is_debug_build(Godot.OS)) && return nothing
    port = something(tryparse(Int, get(ENV, "GDJL_DEBUG_PORT", "")), Int(setting("julia/debugger/port", 0)))
    port > 0 || return nothing
    p = try
        start_debug_server!(port)
    catch e
        report_exception(e, catch_backtrace())
        return nothing
    end
    host_print(PRINT_STDOUT, "Godot-julia: Julia debug server listening on 127.0.0.1:$p")
    if setting("julia/debugger/wait_for_attach", false) === true || get(ENV, "GDJL_DEBUG_WAIT", "") == "1"
        host_print(PRINT_STDOUT, "Godot-julia: waiting for a debugger to attach on port $p...")
        wait_for_debug_client!()
    end
    return nothing
end
