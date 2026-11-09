# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot.Runtime: Runtime, HostAPI, JuliaAPI, ABI_VERSION, PRINT_STDOUT, PRINT_STDERR

const PRINTED = Tuple{Int32, String}[]
const REPORTED = Tuple{Bool, String, String, Int32, String}[]
const STRING_OUT = Ref("")

mock_print(kind::Int32, p::Ptr{UInt8}, n::Int64) = (push!(PRINTED, (kind, unsafe_string(p, n))); nothing)
function mock_report(warn::Int32, func::Cstring, file::Cstring, line::Int32, p::Ptr{UInt8}, n::Int64)
    push!(REPORTED, (warn != 0, unsafe_string(func), unsafe_string(file), line, unsafe_string(p, n)))
    return nothing
end
mock_string_out(::Ptr{Cvoid}, p::Ptr{UInt8}, n::Int64) = (STRING_OUT[] = unsafe_string(p, n); nothing)

mock_host() = HostAPI(ABI_VERSION, sizeof(HostAPI), 4, 0,
                      @cfunction(mock_print, Cvoid, (Int32, Ptr{UInt8}, Int64)),
                      @cfunction(mock_report, Cvoid, (Int32, Cstring, Cstring, Int32, Ptr{UInt8}, Int64)),
                      @cfunction(mock_string_out, Cvoid, (Ptr{Cvoid}, Ptr{UInt8}, Int64)), C_NULL, C_NULL)

function reset_mocks!()
    empty!(PRINTED)
    empty!(REPORTED)
    STRING_OUT[] = ""
end

function call_eval(api::JuliaAPI, code::String)
    return GC.@preserve code ccall(api.eval_string, Int32, (Ptr{UInt8}, Int64, Ptr{Cvoid}), pointer(code), sizeof(code), C_NULL)
end

@testset "Runtime" begin
    @testset "pins" begin
        before = Runtime.pin_count()
        obj = Ref(42)
        id = Runtime.pin(obj)
        @test id != 0
        @test Runtime.deref(id) === obj
        @test Runtime.pin_count() == before + 1
        Runtime.unpin(id)
        @test Runtime.pin_count() == before
        @test_throws KeyError Runtime.deref(id)
        Runtime.unpin(id)
    end

    @testset "GodotStream line buffering" begin
        Runtime.HOST[] = mock_host()
        reset_mocks!()
        io = Runtime.GodotStream(PRINT_STDERR)
        print(io, "partial")
        @test isempty(PRINTED)
        print(io, " line\r\nsecond\nthi")
        @test PRINTED == [(PRINT_STDERR, "partial line"), (PRINT_STDERR, "second")]
        flush(io)
        @test last(PRINTED) == (PRINT_STDERR, "thi")
        Runtime.HOST[] = HostAPI()
    end

    @testset "@godot_entry" begin
        Runtime.HOST[] = mock_host()
        reset_mocks!()
        f() = Runtime.@godot_entry Int32(-1) error("boom")
        @test f() == Int32(-1)
        @test length(REPORTED) == 1
        warn, _, _, _, msg = only(REPORTED)
        @test !warn
        @test occursin("boom", msg)
        @test occursin("Stacktrace", msg)
        g() = Runtime.@godot_entry Int32(-1) Int32(7)
        @test g() == Int32(7)
        Runtime.HOST[] = HostAPI()
    end

    @testset "@gcsafe_ccall" begin
        h() = Runtime.@gcsafe_ccall jl_cpu_pause()::Cvoid
        @test h() === nothing
    end

    @testset "__init_runtime__ / eval / shutdown" begin
        reset_mocks!()
        host = Ref(mock_host())
        out = Ref(JuliaAPI(ABI_VERSION, sizeof(JuliaAPI), C_NULL, C_NULL, C_NULL))
        original_stdout = stdout

        # Keep the redirection window free of @test calls: Test itself prints to stdout.
        ok = GC.@preserve host out Runtime.__init_runtime__(C_NULL, Ptr{Cvoid}(2), Base.unsafe_convert(Ptr{HostAPI}, host),
                                                            Base.unsafe_convert(Ptr{JuliaAPI}, out))
        api = out[]
        println("hello from julia")
        @warn "careful"
        rc_ok = call_eval(api, "1 + 2")
        value = STRING_OUT[]
        rc_err = call_eval(api, "error(\"boom\")")
        ccall(api.shutdown, Cvoid, ())

        @test ok
        @test api.script_call != C_NULL
        @test stdout === original_stdout
        @test Runtime.LIBRARY[] == Ptr{Cvoid}(2)
        @test (PRINT_STDOUT, "hello from julia") in PRINTED
        @test any(r -> r[1] && occursin("careful", r[5]), REPORTED)
        @test rc_ok == 0
        @test value == "3"
        @test rc_err == 1
        @test any(r -> !r[1] && occursin("boom", r[5]), REPORTED)
        @test !Runtime.host_available()
    end

    @testset "ABI mismatch is rejected" begin
        host = Ref(HostAPI(ABI_VERSION + 1, sizeof(HostAPI), 4, 0, C_NULL, C_NULL, C_NULL, C_NULL, C_NULL))
        out = Ref(JuliaAPI(ABI_VERSION, sizeof(JuliaAPI), C_NULL, C_NULL, C_NULL))
        @test_throws ErrorException GC.@preserve host out Runtime.__init_runtime__(C_NULL, C_NULL,
                                                                                  Base.unsafe_convert(Ptr{HostAPI}, host),
                                                                                  Base.unsafe_convert(Ptr{JuliaAPI}, out))
    end
end
