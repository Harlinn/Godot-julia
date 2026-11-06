# Error reporting, debugger queries, debug server. parity: 9.2, 9.5
using Godot.Runtime: Runtime, HostAPI, ABI_VERSION, DebugState
import Sockets

const SCRIPT_ERRORS = Tuple{Bool, String, String, Int32, String, String}[]
const STACK_DURING_REPORT = Ref{Any}(nothing)

function mock_script_error(warn::Int32, func::Cstring, file::Cstring, line::Int32, desc::Cstring, msg::Cstring)
    push!(SCRIPT_ERRORS, (warn != 0, unsafe_string(func), unsafe_string(file), line, unsafe_string(desc), unsafe_string(msg)))
    STACK_DURING_REPORT[] = Runtime.debug_get_current_stack_info(C_NULL)   # Godot asks for the frames while reporting
    return nothing
end

debug_host() = HostAPI(ABI_VERSION, sizeof(HostAPI), 4, 0,
                       @cfunction(mock_print, Cvoid, (Int32, Ptr{UInt8}, Int64)),
                       @cfunction(mock_report, Cvoid, (Int32, Cstring, Cstring, Int32, Ptr{UInt8}, Int64)),
                       @cfunction(mock_string_out, Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Int64)), C_NULL,
                       @cfunction(mock_script_error, Cvoid, (Int32, Cstring, Cstring, Int32, Cstring, Cstring)))

# A stand-in for a script module: code evaluated with a `res://` file name, as the script loader does.
const DBG = Module(:DbgScript)
Core.eval(DBG, :(using Godot))
include_string(DBG, """
const SPEED = 3
function fails(x)
    y = x + 1
    error("bad value \$y")
end
function stop_here(x)
    z = x * 2
    Godot.@breakpoint "stop"
end
stack() = Godot.Runtime.debug_get_current_stack_info(C_NULL)
mutable struct FakeInstance
    __ptr::Ptr{Cvoid}
    hp::Int
end
""", "res://Faulty.jl")

function caught(f)
    try
        f()
    catch e
        return e, catch_backtrace()
    end
    error("no exception")
end

send_request(sock, code) = println(sock, escape_string(code))
function read_reply(sock)
    lines = String[]
    while true
        l = readline(sock)
        l == Runtime.END_MARK && break
        push!(lines, l)
    end
    return join(lines, "\n")
end
function wait_until(f; timeout = 10)
    t0 = time()
    while !f() && time() - t0 < timeout
        sleep(0.01)
    end
    return f()
end

@testset "Debugging" begin
    @testset "res_path" begin
        Runtime.PROJECT_DIR[] = "C:/Games/proj/"
        @test Runtime.res_path("C:\\Games\\proj\\scenes\\Player.jl") == "res://scenes/Player.jl"
        @test Runtime.res_path("c:/games/PROJ/a.jl") == "res://a.jl"
        @test Runtime.res_path("res://Faulty.jl") == "res://Faulty.jl"
        @test Runtime.res_path(".res:\\scenes\\Faulty.jl") == "res://scenes/Faulty.jl"   # Julia's debug info on Windows
        @test Runtime.res_path("D:/other/x.jl") == "D:/other/x.jl"
        Runtime.PROJECT_DIR[] = ""
    end

    @testset "user frames" begin
        e, bt = caught(() -> DBG.fails(1))
        frames = Runtime.user_frames(bt)
        @test !isempty(frames)
        @test all(Runtime.is_script_frame, frames)    # Base, stdlibs, Godot.jl and this test file are skipped
        @test Runtime.res_path(string(frames[1].file)) == "res://Faulty.jl" && frames[1].line == 4 && frames[1].func === :fails
        info = Runtime.stack_info(frames)
        @test info[1] == Dict{String, Any}("file" => "res://Faulty.jl", "func" => "fails", "line" => 4)
        @test Runtime.user_frames(nothing) == []
        st = DBG.stack()
        @test !isempty(st) && st[1]["file"] == "res://Faulty.jl" && st[1]["line"] == 10
    end

    @testset "report_exception" begin
        Runtime.HOST[] = debug_host()
        empty!(SCRIPT_ERRORS)
        e, bt = caught(() -> DBG.fails(1))
        Runtime.report_exception(e, bt)
        warn, func, file, line, desc, msg = only(SCRIPT_ERRORS)
        @test !warn && func == "fails" && file == "res://Faulty.jl" && line == 4
        @test desc == "bad value 2"
        @test occursin("bad value 2", msg) && occursin("Stacktrace", msg) && !occursin(".res:", msg)
        st = STACK_DURING_REPORT[]
        @test st[1]["file"] == "res://Faulty.jl" && st[1]["line"] == 4   # the error's frames, not the reporter's
        @test !haskey(task_local_storage(), :gdjl_pending_bt) || task_local_storage(:gdjl_pending_bt) === nothing
        Runtime.report_exception(e, bt; warning = true)
        @test SCRIPT_ERRORS[end][1]
        # Errors without user frames still reach Godot.
        e2, bt2 = caught(() -> error("plain"))
        Runtime.report_exception(e2, bt2)
        @test SCRIPT_ERRORS[end][5] == "plain"

        # Host without report_script_error (older native library) falls back to report_error.
        Runtime.HOST[] = mock_host()
        reset_mocks!()
        Runtime.report_exception(e, bt)
        @test only(REPORTED)[3] == "res://Faulty.jl" && only(REPORTED)[4] == 4
        # Entry points report and do not unwind.
        reset_mocks!()
        h() = Runtime.@godot_entry Int32(-1) DBG.fails(2)
        @test h() == Int32(-1)
        @test occursin("bad value 3", only(REPORTED)[5])
        Runtime.HOST[] = HostAPI()
    end

    @testset "script debugger queries" begin
        @test Runtime.debug_get_stack_level_count(C_NULL) == 0
        @test Runtime.debug_get_error(C_NULL) == ""
        e, bt = caught(() -> DBG.fails(1))
        inst = DBG.FakeInstance(C_NULL, 10)
        Runtime.DEBUG_STATE[] = DebugState("bad value 2", Runtime.user_frames(bt), Pair{Symbol, Any}[:a => 1, :v => Some(1)], inst)
        try
            @test Runtime.debug_get_error(C_NULL) == "bad value 2"
            @test Runtime.debug_get_stack_level_count(C_NULL) >= 1
            @test Runtime.debug_get_stack_level_line(C_NULL, 0) == 4
            @test Runtime.debug_get_stack_level_function(C_NULL, 0) == "fails"
            @test Runtime.debug_get_stack_level_source(C_NULL, 0) == "res://Faulty.jl"
            @test Runtime.debug_get_stack_level_line(C_NULL, 99) == -1
            @test Runtime.debug_get_stack_level_locals(C_NULL, 0, -1, -1) ==
                  Dict{String, Any}("locals" => ["a", "v"], "values" => Any[1, "Some(1)"])
            @test Runtime.debug_get_stack_level_locals(C_NULL, 1, -1, -1)["locals"] == String[]
            @test Runtime.debug_get_stack_level_members(C_NULL, 0, -1, -1) ==
                  Dict{String, Any}("members" => ["hp"], "values" => Any[10])
            g = Runtime.debug_get_globals(C_NULL, -1, -1)
            @test "SPEED" in g["globals"] && !("fails" in g["globals"])
            @test Runtime.debug_parse_stack_level_expression(C_NULL, 0, "a + SPEED", -1, -1) == "4"
            @test Runtime.debug_parse_stack_level_expression(C_NULL, 0, "a = 5\na * 2", -1, -1) == "10"
            @test occursin("UndefVarError", Runtime.debug_parse_stack_level_expression(C_NULL, 0, "nope_x", -1, -1))
        finally
            Runtime.DEBUG_STATE[] = nothing
        end
        # Without a Godot debugger or debug client, @breakpoint does nothing (like GDScript's `breakpoint`).
        @test DBG.stop_here(1) === false
        @test Runtime.break_on_error(ErrorException("x"), backtrace()) === false
    end

    @testset "debug server" begin
        port = Runtime.start_debug_server!(0)
        @test port > 0 && Runtime.debug_server_running()
        @test Runtime.start_debug_server!(0) == port
        @test !Runtime.has_debug_client()
        sock = Sockets.connect(Sockets.IPv4("127.0.0.1"), port)
        try
            @test Runtime.wait_for_debug_client!(timeout = 10)

            ask(code) = (send_request(sock, code);
                         wait_until(() -> isready(Runtime.DEBUG_REQUESTS));
                         Runtime.process_debug_requests!();
                         read_reply(sock))
            @test ask("gdjl_dbg_x = 20\ngdjl_dbg_x + 1") == "21"     # multi-line request
            @test ask("println(\"hi\"); 5") == "hi\n5"                 # output is captured
            @test ask("nothing") == ""
            @test occursin("nope", ask("error(\"nope\")"))

            # A @breakpoint session: the game pauses until the client sends `continue`.
            client = @async begin
                note = read_reply(sock)
                send_request(sock, "z + x")
                r1 = read_reply(sock)
                send_request(sock, "continue")
                (note, r1, read_reply(sock))
            end
            @test DBG.stop_here(4) === true
            note, r1, r2 = fetch(client)
            @test startswith(note, "GDJL_BREAK stop at res://Faulty.jl:8")
            @test occursin(r"locals: (x, z|z, x)", note)
            @test r1 == "12"
            @test r2 == "continuing"
        finally
            close(sock)
            Runtime.stop_debug_server!()
        end
        @test !Runtime.debug_server_running()
        @test !Runtime.has_debug_client()
        @test Runtime.wait_for_debug_client!(timeout = 0.1) == false
    end

    @testset "REPL client (addons/godot_julia/tools/godot_repl.jl)" begin
        client = Module(:ReplClient)
        Base.include(client, joinpath(REPO_ROOT, "addons", "godot_julia", "tools", "godot_repl.jl"))
        port = Runtime.start_debug_server!(0)
        sock = Sockets.connect(Sockets.IPv4("127.0.0.1"), port)
        out = IOBuffer()
        printed() = String(out.data[1:out.size])
        done = Channel{Nothing}(Inf)
        try
            @test Runtime.wait_for_debug_client!(timeout = 10)
            reader = @async client.read_replies(sock, done; out)
            println(sock, escape_string("2 + 3"))
            wait_until(() -> isready(Runtime.DEBUG_REQUESTS))
            Runtime.process_debug_requests!()
            take!(done)
            @test occursin("5", printed())
            # A breakpoint notice is shown but does not count as the reply to a request.
            resumer = @async begin
                wait_until(() -> occursin("[breakpoint]", printed()))
                println(sock, "continue")
                take!(done)
                isready(done)
            end
            @test DBG.stop_here(1) === true
            @test fetch(resumer) === false
            @test occursin("[breakpoint] stop at res://Faulty.jl:8", printed()) && occursin("continuing", printed())
        finally
            close(sock)
            Runtime.stop_debug_server!()
        end
    end
end
