# Main-thread scheduler and awaiting. parity: 6.4, 6.5
using Godot.Runtime: Runtime

struct NodeHolder
    count::Int
    node::GodotObject
end
(h::NodeHolder)() = h.count

@testset "Signals and async (no engine)" begin
    @testset "callable_target" begin
        n = Godot.Native.Node(Ptr{Cvoid}(1))
        @test callable_target(() -> n) === n
        @test callable_target(NodeHolder(1, n)) === n
        @test callable_target(n) === n
        @test callable_target(() -> 1) === nothing
        @test callable_target(sin) === nothing
        local m
        f = () -> m
        m = n                       # captured variable assigned later: stored in a Core.Box
        @test callable_target(f) === n
    end

    @testset "godot_task / post" begin
        trace = Int[]
        ev = Base.Event()
        t = godot_task() do
            push!(trace, 1)
            wait(ev)
            push!(trace, 3)
            42
        end
        push!(trace, 2)
        @test trace == [1, 2]                 # ran at once until its first wait
        notify(ev)
        @test trace == [1, 2]                 # continuations run in the frame pump
        Godot.pump_frame!()
        @test trace == [1, 2, 3] && istaskdone(t) && fetch(t) == 42
        @test Godot.live_task_count() == 0

        n = Ref(0)
        Godot.post(() -> n[] += 1)
        @test n[] == 0
        Godot.pump_frame!()
        @test n[] == 1

        t2 = @async_godot begin
            Godot.in_godot_task()
        end
        @test fetch(t2) === true
        @test !Godot.in_godot_task()
    end

    @testset "SignalAwaiter" begin
        a = SignalAwaiter(:hit, Base.Event(), nothing, false)
        got = Ref{Any}(nothing)
        t = godot_task(() -> (got[] = @await a))
        a(5, "x")                             # what the one-shot Callable does on emission
        Godot.pump_frame!()
        @test got[] == (5, "x") && istaskdone(t)
        @test wait(a) == (5, "x")             # already completed: no task needed

        b = SignalAwaiter(:gone, Base.Event(), nothing, false)
        t2 = godot_task(() -> wait(b))
        @test Godot.live_task_count() == 1
        Runtime.callable_freed(b)             # the emitting object was freed
        Godot.pump_frame!()
        @test istaskdone(t2) && fetch(t2) === nothing && Godot.live_task_count() == 0
        @test_throws SignalCancelled wait(b)

        c = SignalAwaiter(:never, Base.Event(), nothing, false)
        @test_throws ErrorException wait(c)   # would block the engine's main thread
    end
end
