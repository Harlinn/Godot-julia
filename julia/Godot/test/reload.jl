# Hot reload: generations, migration, retries. parity: 7.1, 7.2, 7.4, 7.5
using Test
using Godot
const R = Godot.Runtime

const GEN_SRC = """
@enum Mode Idle Run
struct Stats
    hits::Int
end
mutable struct Thing
    x::Int
end
handler(t) = t.x
make_closure(t) = () -> handler(t)
make_boxed(t) = (b = t; f = () -> b.x; b = t; f)
"""

function generation_pair()
    old, new = Module(:ReloadTestGen1), Module(:ReloadTestGen2)
    include_string(old, GEN_SRC)
    include_string(new, GEN_SRC)
    st = R.ScriptState(Ptr{Cvoid}(UInt(0xdead0)))
    st.mod = new
    st.valid = true
    R.GENERATIONS[old] = st
    R.GENERATIONS[new] = st
    return old, new, st
end

@testset "reload" begin
    old, new, st = generation_pair()
    try
        @testset "migrate_value" begin
            replaced = IdDict{Any, Any}()
            @test R.migrate_value(3, Float64, replaced) === 3.0
            @test R.migrate_value("x", Int, replaced) === R.NO_TRANSFER
            @test R.migrate_value(3.5, Int, replaced) === R.NO_TRANSFER
            @test R.migrate_value(old.Run, new.Mode, replaced) === new.Run
            s = R.migrate_value(old.Stats(4), new.Stats, replaced)
            @test s isa new.Stats && s.hits == 4
            a, b = old.Thing(1), new.Thing(2)
            replaced[a] = b
            @test R.migrate_value(a, new.Thing, replaced) === b
            v = R.migrate_value(Any[a, a], Vector{new.Thing}, replaced)
            @test v isa Vector{new.Thing} && all(x -> x === b, v)
            @test R.migrate_value(nothing, Union{Nothing, Int}, replaced) === nothing
        end

        @testset "retarget callables" begin
            a, b = old.Thing(1), new.Thing(2)
            replaced = IdDict{Any, Any}(a => b)
            c = old.make_closure(a)
            nc = R.retarget(c, replaced)
            @test parentmodule(typeof(nc)) === new && nc() == 2
            @test R.retarget(old.handler, replaced) === new.handler
            boxed = old.make_boxed(a)
            nb = R.retarget(boxed, replaced)
            @test nb() == 2
            # Closures outside script generations keep their code; captured instances are replaced.
            outside = let t = a
                () -> t.x
            end
            no = R.retarget(outside, replaced)
            @test typeof(no).name === typeof(outside).name && no() == 2
            @test R.retarget(outside, IdDict{Any, Any}()) === outside
            # A function the new generation no longer defines is retired.
            Core.eval(old, :(gone() = 1))
            r = R.retarget(getglobal(old, :gone), replaced)
            @test r isa R.RetiredCallable && r(1, 2) === nothing
        end

        @testset "JuliaCallable box keeps its hash" begin
            box = R.JuliaCallable(sin, hash(sin) % UInt32)
            h = box.hash
            box.f = cos
            @test box.hash == h
        end

        @testset "reload_order" begin
            p(i) = Ptr{Cvoid}(UInt(0xbeef00 + i))
            a, b, c, d = (R.ScriptState(p(i)) for i in 1:4)
            a.path, b.path, c.path, d.path = "res://a.jl", "res://b.jl", "res://c.jl", "res://d.jl"
            push!(b.deps, a.ptr)        # b inherits a
            push!(c.deps, b.ptr)        # c refers to b
            @lock R.SCRIPTS_LOCK for s in (a, b, c, d)
                R.SCRIPTS[s.ptr] = s
            end
            try
                @test R.reload_order([a]) == [a, b, c]
                @test R.reload_order([b]) == [b, c]
                @test R.reload_order([d]) == [d]
                @test R.reload_order([c, a]) == [a, b, c]
            finally
                @lock R.SCRIPTS_LOCK foreach(s -> delete!(R.SCRIPTS, s.ptr), (a, b, c, d))
            end
        end

        @testset "retire generations" begin
            st.valid = false   # neither module is referenced by a loaded script or instance
            n = R.retire_generations!()
            @test n >= 2 && !haskey(R.GENERATIONS, old) && !haskey(R.GENERATIONS, new)
            @test isempty(methods(new.handler))
        end
    finally
        delete!(R.GENERATIONS, old)
        delete!(R.GENERATIONS, new)
    end
end
