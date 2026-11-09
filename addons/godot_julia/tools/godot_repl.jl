#!/usr/bin/env julia
# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Godot-julia debug REPL client: connects to the Julia debug server of a running game (debug build started with
# GDJL_DEBUG_PORT=<port> or the `julia/debugger/port` project setting) and evaluates expressions in it.
# Usage: julia godot_repl.jl [port] [host]      (default 127.0.0.1:47100)
# While a `Godot.@breakpoint` is active, expressions see its local variables; `continue` (or `c`) resumes the game.
# See docs/debugging.md.

import Sockets

const END_MARK = "GDJL_END"

function read_replies(sock, done::Channel{Nothing}; out::IO = stdout)
    in_note = false   # breakpoint notices arrive unrequested; their end mark answers no request
    try
        while isopen(sock)
            line = readline(sock)
            if line == END_MARK
                in_note ? (in_note = false) : put!(done, nothing)
            elseif startswith(line, "GDJL_BREAK ")
                in_note = true
                printstyled(out, "\n[breakpoint] ", line[12:end], "\n"; color = :yellow, bold = true)
            elseif !(isempty(line) && eof(sock))
                println(out, line)
            else
                break
            end
        end
    catch
    end
    println(out, "\n(disconnected)")
    put!(done, nothing)
end

"Read a complete Julia input (more lines are read while the expression is incomplete)."
function read_input(prompt)
    buf = ""
    while true
        print(buf == "" ? prompt : "       ")
        line = readline(stdin; keep = true)
        isempty(line) && return nothing   # EOF
        buf *= line
        ex = Meta.parse(buf; raise = false)
        Meta.isexpr(ex, :incomplete) || return chomp(buf)
    end
end

function main(args)
    port = isempty(args) ? 47100 : parse(Int, args[1])
    host = length(args) >= 2 ? args[2] : "127.0.0.1"
    sock = try
        Sockets.connect(host, port)
    catch e
        println(stderr, "Cannot connect to the Godot game on $host:$port ($(sprint(showerror, e))).")
        println(stderr, "Run a debug build with GDJL_DEBUG_PORT=$port or set julia/debugger/port.")
        exit(1)
    end
    println("Connected to the Godot game on $host:$port. Ctrl-D exits; `continue` resumes a breakpoint.")
    done = Channel{Nothing}(Inf)
    errormonitor(@async read_replies(sock, done))
    while isopen(sock)
        code = read_input("godot> ")
        code === nothing && break
        isempty(strip(code)) && continue
        println(sock, escape_string(code))
        take!(done)
    end
    close(sock)
end

abspath(PROGRAM_FILE) == @__FILE__() && main(ARGS)
