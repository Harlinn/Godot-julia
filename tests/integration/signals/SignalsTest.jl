using Godot
import GodotTestRunner

# In-engine tests for signals, Callables from Julia functions, the main-thread task scheduler, awaiting signals,
# deferred calls and WorkerThreadPool tasks. parity: 3.11, 4.10, 5.11, 6.1–6.6
@godot_class mutable struct SignalsTest <: Node
    @signal ping(x::Int)
    @signal tick
end

Godot._ready(self::SignalsTest) = (godot_task(() -> run_tests(self)); nothing)

function run_tests(self::SignalsTest)
    passed, failed = Ref(0), Ref(0)
    check(ok, what) = ok ? (passed[] += 1) : (failed[] += 1; println("FAILED: ", what))
    try
        # Closures connected to signals; disconnect by the returned Callable or by the function.
        total = Ref(0)
        c = connect(self, :ping, x -> (total[] += x; nothing))
        emit_ping(self, 2)
        check(total[] == 2 && c isa Callable, "closure connected to a script signal fires")
        disconnect(self, :ping, c)
        emit_ping(self, 3)
        check(total[] == 2, "disconnect")
        handler = x -> (total[] += 10x; nothing)
        connect(self, :ping, handler)
        check(is_connected(self, :ping, handler), "is_connected with the same function")
        disconnect(self, :ping, handler)
        check(!is_connected(self, :ping, handler), "disconnect with the same function")
        once = Ref(0)
        connect(self, :ping, x -> (once[] += 1; nothing); flags = GodotObject_CONNECT_ONE_SHOT)
        emit_ping(self, 1)
        emit_ping(self, 1)
        check(once[] == 1, "CONNECT_ONE_SHOT")
        check(try
                  emit_ping(self, "x")
                  false
              catch e
                  e isa MethodError
              end, "typed emit helper checks argument types")

        # Freed targets are disconnected automatically (closure captures an engine object).
        target = Node()
        hits = Ref(0)
        connect(self, :tick, () -> (hits[] += 1; target))
        emit_tick(self)
        free(target)
        check(isempty(get_signal_connection_list(self, :tick)), "freed target auto-disconnects")
        emit_tick(self)
        check(hits[] == 1, "no call after the target was freed")

        # Signal values.
        s = Signal(self, :ping)
        seen = Ref(0)
        f = x -> (seen[] = x; nothing)
        connect(s, f)
        emit(s, 7)
        check(seen[] == 7 && is_connected(s, f) && length(get_connections(s)) == 1, "Signal connect/emit/get_connections")
        disconnect(s, f)
        check(!is_connected(s, f), "Signal disconnect")
        godot_task(() -> (wait(next_frame(self)); emit_ping(self, 9)))
        check(wait(s) == (9,), "wait(signal) returns the signal arguments")

        # Engine signals: per-signal helpers (C# events) and awaiting timers.
        timer = Godot.Timer()
        add_child(self, timer)
        fired = Ref(false)
        connect_timeout(timer, () -> (fired[] = true; nothing))
        timer.wait_time = 0.05
        timer.one_shot = true
        start(timer)
        args = @await to_signal(timer, :timeout)
        check(args == () && fired[], "await a Timer's timeout; connect_timeout helper")
        check(Threads.threadid() == 1, "continuations resume on the main thread")
        frames = get_process_frames(Engine)
        wait(next_frame(self))
        check(get_process_frames(Engine) > frames, "await the next process frame")
        t0 = get_ticks_msec(Godot.Time)
        wait(delay(self, 0.1))
        check(get_ticks_msec(Godot.Time) - t0 >= 90, "delay(node, seconds)")

        # Awaiting a signal of an object that is freed cancels the waiting task without leaking.
        victim = Node()
        add_child(self, victim)
        pins = Godot.Runtime.pin_count()
        tasks = Godot.live_task_count()
        waiter = godot_task(() -> wait(to_signal(victim, :renamed)))
        check(!istaskdone(waiter), "task waits for the signal")
        free(victim)
        wait(next_frame(self))
        check(istaskdone(waiter) && fetch(waiter) === nothing, "freed source cancels the waiting task")
        # Counts may drop meanwhile (earlier callables being released) but must not grow.
        check(Godot.live_task_count() <= tasks && Godot.Runtime.pin_count() <= pins,
              "no leaked tasks or pins (tasks $tasks -> $(Godot.live_task_count()), pins $pins -> $(Godot.Runtime.pin_count()))")

        # Unhandled exceptions in tasks are reported (expect_errors.txt), and do not stop other tasks.
        bad = godot_task(() -> error("boom in task"))
        check(istaskdone(bad), "failing task finished")

        # Deferred calls.
        deferred = Ref(false)
        call_deferred(() -> (deferred[] = true; nothing))
        check(!deferred[], "call_deferred does not run immediately")
        wait(next_frame(self))
        wait(next_frame(self))
        check(deferred[], "call_deferred runs later")

        # Worker threads: WorkerThreadPool tasks running Julia closures, results posted to the main thread.
        posted = Ref(0)
        id = add_task(WorkerThreadPool, () -> (r = sum(1:1000); Godot.post(() -> (posted[] = r; nothing)); nothing))
        wait_for_task_completion(WorkerThreadPool, id)
        wait(next_frame(self))
        check(posted[] == 500500, "WorkerThreadPool task posts its result to the main thread")
        acc = Threads.Atomic{Int}(0)
        gid = add_group_task(WorkerThreadPool, i -> (Threads.atomic_add!(acc, Int(i)); nothing), 100)
        wait_for_group_task_completion(WorkerThreadPool, gid)
        check(acc[] == 4950, "WorkerThreadPool group task")
        spawned = Threads.@spawn sum(1:10)
        check(fetch(spawned) == 55 && Threads.threadid() == 1, "await a Threads.@spawn task")
        main_tid = Ref(0)
        Threads.@spawn Godot.post(() -> (main_tid[] = Threads.threadid(); nothing))
        for _ in 1:10
            main_tid[] == 0 || break
            wait(next_frame(self))
        end
        check(main_tid[] == 1, "post from a Julia worker thread runs on the main thread")
    catch e
        failed[] += 1
        Godot.Runtime.report_exception(e, catch_backtrace())
    end
    GodotTestRunner.report("signals"; passed = passed[], failed = failed[])
    quit(get_tree(self), failed[] == 0 ? 0 : 1)
end
