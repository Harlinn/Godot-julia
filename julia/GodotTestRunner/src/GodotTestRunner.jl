# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

"""
    GodotTestRunner

Run `Test` test sets inside the engine and report one machine-readable line for the integration harness
(`tests/integration/run.jl`):

    GDJL_TEST_RESULT {"name":"...","passed":N,"failed":F,"errored":E,"broken":B}

```julia
using Test, Godot, GodotTestRunner
GodotTestRunner.run_tests(self, "signals") do     # in a godot_task; quits the game with the result
    @testset "connect" begin
        @test ...
    end
end
```
"""
module GodotTestRunner

using Test
using Godot

export EngineTestSet, run_tests, report, Checks, check!

"Test set that counts results (nested sets add to their parent) and prints failures as they happen."
mutable struct EngineTestSet <: Test.AbstractTestSet
    description::String
    passed::Int
    failed::Int
    errored::Int
    broken::Int
    failures::Vector{String}
end

EngineTestSet(desc::AbstractString; kw...) = EngineTestSet(String(desc), 0, 0, 0, 0, String[])

Test.record(ts::EngineTestSet, t::Test.Pass) = (ts.passed += 1; t)
Test.record(ts::EngineTestSet, t::Test.Broken) = (ts.broken += 1; t)
function Test.record(ts::EngineTestSet, t::Union{Test.Fail, Test.Error})
    t isa Test.Fail ? (ts.failed += 1) : (ts.errored += 1)
    msg = ts.description * ": " * sprint(show, t; context = :color => false)
    push!(ts.failures, msg)
    println("FAILED: ", msg)
    return t
end
function Test.record(ts::EngineTestSet, child::EngineTestSet)
    ts.passed += child.passed
    ts.failed += child.failed
    ts.errored += child.errored
    ts.broken += child.broken
    append!(ts.failures, child.failures)
    return ts
end
function Test.finish(ts::EngineTestSet)
    Test.get_testset_depth() > 0 && Test.record(Test.get_testset(), ts)
    return ts
end

json_string(s) = "\"" * replace(String(s), '\\' => "\\\\", '"' => "\\\"", '\n' => "\\n", '\r' => "\\r", '\t' => "\\t") * "\""

"""
    report(name; passed, failed = 0, errored = 0, broken = 0) -> Bool

Print the `GDJL_TEST_RESULT` line; `true` when nothing failed and at least one check passed.
"""
function report(name::AbstractString; passed::Integer, failed::Integer = 0, errored::Integer = 0, broken::Integer = 0,
                io::IO = stdout)
    println(io, "GDJL_TEST_RESULT {\"name\":", json_string(name), ",\"passed\":", passed, ",\"failed\":", failed,
            ",\"errored\":", errored, ",\"broken\":", broken, "}")
    flush(io)
    return failed == 0 && errored == 0 && passed > 0
end

report(ts::EngineTestSet) = report(ts.description; passed = ts.passed, failed = ts.failed, errored = ts.errored, broken = ts.broken)

"""
    run_tests(f, name) -> Bool

Run `f()` inside a top-level `EngineTestSet` (exceptions count as errors), flush pending engine releases and report.
"""
function run_tests(f, name::AbstractString)
    ts = @testset EngineTestSet "$name" begin
        f()
    end
    GC.gc()
    Godot.Internals.flush_releases!()
    return report(ts)
end

"""
    run_tests(f, node::Node, name)

Run the tests in a Godot task (so they can wait for frames and signals), then quit the game with exit code 0 on
success, 1 otherwise.
"""
function run_tests(f, node::Godot.Node, name::AbstractString)
    godot_task() do
        ok = run_tests(f, name)
        Godot.quit(Godot.get_tree(node), ok ? 0 : 1)
    end
    return nothing
end

"Plain counters for checks written as `check!(c, condition, description)`."
mutable struct Checks
    name::String
    passed::Int
    failed::Int
end
Checks(name::AbstractString) = Checks(String(name), 0, 0)

function check!(c::Checks, ok::Bool, what::AbstractString)
    ok ? (c.passed += 1) : (c.failed += 1; println("FAILED: ", what))
    return ok
end

report(c::Checks) = report(c.name; passed = c.passed, failed = c.failed)

end # module GodotTestRunner
