using Godot
using Sockets
import GodotTestRunner

# In-engine tests for debugging: Julia errors reported as script errors at res:// lines with Julia backtraces,
# Julia frames in engine-error backtraces and Engine.capture_script_backtraces, and the debug REPL server with a
# @breakpoint session. parity: 9.2, 9.3, 9.5
@godot_class mutable struct DebugTest <: Node
    logger::Any = nothing
end

const ERROR_TYPE_SCRIPT = 2   # Logger.ERROR_TYPE_SCRIPT

function Godot._ready(self::DebugTest)
    self.logger = Godot.call(Godot.load(Godot.ResourceLoader, "res://error_logger.gd"), "new")
    add_logger(Godot.OS, self.logger)
    godot_task(() -> run_tests(self))
    return nothing
end

take_errors(self) = Any[e for e in Godot.call(self.logger, "take")]
julia_frames(e) = Any[f for f in e["frames"] if string(f["language"]) == "Julia"]
has_frame(e, file, line) = any(f -> string(f["file"]) == file && Int(f["line"]) == line, julia_frames(e))

function paused(x)
    y = x + 1
    Godot.@breakpoint "paused here"
    return y
end

send_request(sock, code) = println(sock, escape_string(code))
function read_reply(sock)
    lines = String[]
    while true
        l = readline(sock)
        (l == "GDJL_END" || (isempty(l) && eof(sock))) && break
        push!(lines, l)
    end
    return join(lines, "\n")
end

function run_tests(self::DebugTest)
    passed, failed = Ref(0), Ref(0)
    check(ok, what) = ok ? (passed[] += 1) : (failed[] += 1; println("FAILED: ", what))
    try
        # Errors in engine callbacks: one script error per frame at the throwing line; the game keeps running.
        faulty = get_node(self, "Faulty")
        for _ in 1:20
            faulty.count >= 3 && break
            wait(next_frame(self))
        end
        errs = filter(e -> occursin("faulty frame", string(e["rationale"])), take_errors(self))
        check(length(errs) == 3, "three faulty-frame errors (got $(length(errs)))")
        check(all(e -> string(e["file"]) == "res://Faulty.jl" && Int(e["line"]) == 11 && Int(e["type"]) == ERROR_TYPE_SCRIPT,
                  errs), "errors are script errors at res://Faulty.jl:11: $(isempty(errs) ? "" : errs[1])")
        check(!isempty(errs) && string(errs[1]["code"]) == "faulty frame 1", "description is the error message")
        check(!isempty(errs) && occursin("Stacktrace", string(errs[1]["rationale"])) &&
              occursin("@ res://Faulty.jl:11", string(errs[1]["rationale"])), "message has the Julia stack trace")
        check(!isempty(errs) && has_frame(errs[1], "res://Faulty.jl", 11), "Julia frames in the script backtrace")
        wait(next_frame(self))
        check(is_instance_valid(faulty) && faulty.count == 3, "the game keeps running after errors")

        # Engine errors raised by calls from Julia carry the Julia frames.
        line = @__LINE__() + 1
        missing_node = get_node(self, "Missing")
        errs = filter(e -> occursin("Missing", string(e["code"]) * string(e["rationale"])), take_errors(self))
        check(missing_node === nothing && length(errs) == 1, "engine error recorded")
        check(!isempty(errs) && has_frame(errs[1], "res://DebugTest.jl", line),
              "engine error backtrace has res://DebugTest.jl:$line: $(isempty(errs) ? "" : julia_frames(errs[1]))")

        # Engine.capture_script_backtraces from Julia.
        line = @__LINE__() + 1
        bts = capture_script_backtraces(Godot.Engine)
        jl = [bt for bt in bts if get_language_name(bt) == "Julia"]
        check(length(jl) == 1 && get_frame_count(jl[1]) >= 1, "a Julia ScriptBacktrace")
        check(!isempty(jl) && get_frame_file(jl[1], 0) == "res://DebugTest.jl" && get_frame_line(jl[1], 0) == line,
              "capture_script_backtraces frame 0 is this line")

        # Unhandled errors in Godot tasks.
        line = @__LINE__() + 1
        t = godot_task(() -> error("task failure"))
        wait(next_frame(self))
        errs = filter(e -> occursin("task failure", string(e["rationale"])), take_errors(self))
        check(length(errs) == 1 && string(errs[1]["file"]) == "res://DebugTest.jl" && Int(errs[1]["line"]) == line,
              "task error at res://DebugTest.jl:$line: $(isempty(errs) ? "" : errs[1]["line"])")

        # Debug REPL server (julia/debugger/port = 47123 in project.godot).
        sock = Sockets.connect(ip"127.0.0.1", 47123)
        try
            send_request(sock, "1 + 1")
            check(read_reply(sock) == "2", "debug server evaluates requests")
            send_request(sock, "a = Godot.get_process_frames(Godot.Engine) > 0\nprintln(\"live \", a)\n6 * 7")
            r = read_reply(sock)
            check(r == "live true\n42", "multi-line request with captured output: $r")
            # Break in an engine callback (a posted job runs in the frame callback, not in a task): the whole game
            # stops while the client evaluates; in a godot_task only that task would pause.
            client = @async begin
                note = read_reply(sock)
                f1 = get_process_frames(Godot.Engine)
                sleep(0.3)
                f2 = get_process_frames(Godot.Engine)
                send_request(sock, "x * 10 + y")
                r1 = read_reply(sock)
                send_request(sock, "continue")
                (note, r1, read_reply(sock), f1 == f2)
            end
            result = Ref(0)
            Godot.post(() -> (result[] = paused(4); nothing))
            note, r1, r2, frozen = fetch(client)
            wait(next_frame(self))
            check(result[] == 5, "@breakpoint returns after continue")
            check(frozen, "the game is paused during the session")
            check(occursin("GDJL_BREAK paused here at res://DebugTest.jl:", note), "break notice: $note")
            check(r1 == "45", "evaluate with the breakpoint's locals: $r1")
            check(r2 == "continuing", "continue")
        finally
            close(sock)
        end
    catch e
        failed[] += 1
        println("FAILED with exception: ", sprint(showerror, e, catch_backtrace()))
    end
    GodotTestRunner.report("debugging"; passed = passed[], failed = failed[])
    quit(get_tree(self), failed[] == 0 ? 0 : 1)
end
