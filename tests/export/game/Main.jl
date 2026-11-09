# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot

# Checks run in the exported game (tests/export/run.jl passes mode/debug as user arguments).
# parity: 1.8, 9.4, 10.1, 10.2, 10.7, 10.8
@godot_class mutable struct Main <: Node
end

function Godot._ready(self::Main)
    godot_task(() -> run_checks(self))
    return nothing
end

function user_arg(name)
    for a in Godot.get_cmdline_user_args(Godot.OS)
        startswith(a, name * "=") && return a[length(name)+2:end]
    end
    return ""
end

platform_feature() = Godot.@feature(:windows) ? "windows" : Godot.@feature(:linux) ? "linux" :
                     Godot.@feature(:macos) ? "macos" : "other"

function run_checks(self::Main)
    passed, failed = Ref(0), Ref(0)
    check(ok, what) = ok ? (passed[] += 1) : (failed[] += 1; println("FAILED: ", what))
    mode, debug = user_arg("mode"), user_arg("debug") == "true"
    try
        check(Godot.has_feature(:template), "running an exported template")
        check(!Godot.@feature(:editor), "@feature(:editor) is false in exports")
        check(Godot.@feature(:debug) == debug && Godot.@feature(:release) == !debug, "debug/release feature")
        check(platform_feature() == (Sys.iswindows() ? "windows" : Sys.isapple() ? "macos" : "linux"), "platform feature")
        check(Godot.has_feature(:pc), "pc feature at runtime")

        R = Godot.Runtime
        check(R.is_exported(), "the runtime knows it runs exported")
        if mode == "sysimage"
            check(haskey(R.PRECOMPILED_SCRIPTS, "res://Main.jl"), "Main.jl compiled into the system image")
            check(haskey(R.PRECOMPILED_SCRIPTS, "res://Boss.jl") && haskey(R.PRECOMPILED_SCRIPTS, "res://Enemy.jl"),
                  "Boss.jl and Enemy.jl compiled into the system image")
            check(!haskey(R.PRECOMPILED_SCRIPTS, "res://Dynamic.jl"), "Dynamic.jl not compiled (needs the engine)")
            check(Base.in_sysimage(Base.PkgId(Godot)), "Godot is in the system image")
        end
        check(isempty(Godot.get_file_as_string(Godot.FileAccess, "res://Main.jl")) == (mode == "sysimage"),
              "script sources are stubs in sysimage exports")

        boss = Godot.load(Godot.ResourceLoader, "res://Boss.jl")
        check(boss !== nothing && Godot.can_instantiate(boss), "Boss.jl loads")
        B = Godot.script_type("res://Boss.jl")
        # In jit exports the script was just evaluated, so its methods are newer than this task's world.
        b = Base.invokelatest(B)
        add_child(self, b)
        check(b.readied && b.hp == 10 && b.armor == 3, "inherited _ready and fields")
        hit! = Base.invokelatest(getglobal, parentmodule(typeof(b)), :hit!)
        check(Base.invokelatest(hit!, b, 5) == 8, "script method of an exported class")
        check(Godot.get_base_script(boss) !== nothing, "base script of an exported script")

        # Evaluated just now, so its constructor is newer than this task's world.
        dyn = Base.invokelatest(Godot.script_type("res://Dynamic.jl"))
        add_child(self, dyn)
        check(dyn.frames >= 0, "script evaluated from source at runtime")

        t = godot_task(() -> (wait(next_frame(self)); 42))
        check(fetch(t) == 42, "tasks and signals")
    catch e
        failed[] += 1
        println("FAILED with exception: ", sprint(showerror, e, catch_backtrace()))
    end
    # GodotTestRunner is not a dependency of the exported game, so the result line is printed directly.
    println("GDJL_TEST_RESULT {\"name\":\"export\",\"passed\":$(passed[]),\"failed\":$(failed[]),\"errored\":0,\"broken\":0}")
    quit(get_tree(self), failed[] == 0 ? 0 : 1)
end
