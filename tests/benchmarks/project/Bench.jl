# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot

# Micro-benchmarks of the hot paths (tests/benchmarks/run.jl compares them with baselines). Each prints
#   GDJL_BENCH {"name":"...","ns":N}
# GDScript equivalents run in the same process as the reference (no .NET editor here for C# numbers).
@godot_class mutable struct Bench <: Node
end

noop(self::Bench, x::Int) = x

function Godot._ready(self::Bench)
    godot_task(() -> run_benchmarks(self))
    return nothing
end

bench_line(name, ns) = (println("GDJL_BENCH {\"name\":\"", name, "\",\"ns\":", round(ns; digits = 1), "}"); flush(stdout))

"Best of 5 runs, in ns per iteration."
function per_call(f, n)
    f(100)
    best = Inf
    for _ in 1:5
        t = time_ns()
        f(n)
        best = min(best, (time_ns() - t) / n)
    end
    return best
end

function engine_calls(node, n)
    s = 0
    for _ in 1:n
        s += get_child_count(node)
    end
    return s
end

function property_gets(node, n)
    s = 0.0f0
    for _ in 1:n
        s += node.position.x
    end
    return s
end

function signal_emits(node, n)
    for i in 1:n
        emit_signal(node, :ping, i)
    end
end

function variant_round_trips(n)
    s = 0.0f0
    for i in 1:n
        s += Vector2(Variant(Vector2(i, 1))).x
    end
    return s
end

function script_calls(node, n)
    s = 0
    for i in 1:n
        s += Godot.call(node, :noop, i)
    end
    return s
end

"Cost of one `_process` callback: NOTIFICATION_PROCESS propagated to `count` script nodes minus plain nodes, per node."
function process_cost(self, make, count; reps = 50)
    function per_round(factory)
        parent = Node()
        add_child(self, parent)
        for _ in 1:count
            c = factory()
            set_process(c, false)          # only the propagated notification runs it
            add_child(parent, c)
        end
        propagate_notification(parent, Node_NOTIFICATION_PROCESS)
        best = Inf
        for _ in 1:reps
            t = time_ns()
            propagate_notification(parent, Node_NOTIFICATION_PROCESS)
            best = min(best, (time_ns() - t) / count)
        end
        queue_free(parent)
        return best
    end
    return max(per_round(make) - per_round(Node), 0.0)
end

function run_benchmarks(self::Bench)
    n = 200_000
    node2d = Node2D()
    add_child(self, node2d)
    add_user_signal(self, "ping", GDArray([GDDictionary(Dict("name" => "x", "type" => 2))]))
    hits = Ref(0)
    connect(self, :ping, x -> (hits[] += 1; nothing))
    gd = Godot.load(Godot.ResourceLoader, "res://ticker.gd")

    bench_line("engine_call", per_call(k -> engine_calls(self, k), n))
    bench_line("property_get", per_call(k -> property_gets(node2d, k), n))
    bench_line("signal_emit_to_julia", per_call(k -> signal_emits(self, k), n ÷ 4))
    bench_line("variant_round_trip", per_call(variant_round_trips, n))
    bench_line("engine_to_julia_script_call", per_call(k -> script_calls(self, k), n ÷ 4))
    gd_node = Godot.call(gd, :new)
    bench_line("engine_to_gdscript_call", per_call(k -> script_calls(gd_node, k), n ÷ 4))
    T = Godot.script_type("res://Ticker.jl")
    bench_line("julia_process_dispatch", process_cost(self, () -> Base.invokelatest(T), 2000))
    bench_line("gdscript_process_dispatch", process_cost(self, () -> Godot.call(gd, :new), 2000))
    free(gd_node)
    println("GDJL_BENCH_DONE")
    quit(get_tree(self), 0)
end
