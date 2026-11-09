# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Test
using GodotTestRunner

# parity: harness for every tests/integration project (no matrix row of its own)
@testset "GodotTestRunner" begin
    ts = @testset EngineTestSet "outer" begin
        @testset "inner" begin
            @test 1 + 1 == 2
            @test_broken false
            @test 1 == 2
        end
        @test true
    end
    @test ts isa EngineTestSet
    @test (ts.passed, ts.failed, ts.errored, ts.broken) == (2, 1, 0, 1)
    @test length(ts.failures) == 1 && occursin("inner", ts.failures[1])

    io = IOBuffer()
    @test report("a \"b\""; passed = 3, failed = 0, io) === true
    @test strip(String(take!(io))) == "GDJL_TEST_RESULT {\"name\":\"a \\\"b\\\"\",\"passed\":3,\"failed\":0,\"errored\":0,\"broken\":0}"
    @test report("x"; passed = 0, io) === false

    ok = redirect_stdout(devnull) do
        run_tests("errors") do
            @test true
            error("boom")
        end
    end
    @test ok === false

    c = Checks("c")
    redirect_stdout(devnull) do
        check!(c, true, "a")
        check!(c, false, "b")
    end
    @test (c.passed, c.failed) == (1, 1)
end
