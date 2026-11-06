using Godot
import GodotTestRunner

# Headless editor checks for the Julia editor tools (parity: 1.4-1.6, 5.4, 7.3, 8.1-8.8). Being a Julia @tool EditorPlugin
# enabled in project.godot, it also checks that editor plugins can be written in Julia.
@tool @godot_class mutable struct EditorTest <: Godot.Editor.EditorPlugin
end

Godot._enter_tree(self::EditorTest) = (godot_task(() -> run_tests(self)); nothing)

function wait_frames(self, n)
    for _ in 1:n
        wait(next_frame(self))
    end
end

function run_tests(self::EditorTest)
    Tools = Godot.Editor.Tools
    R = Godot.Runtime
    EI = Godot.Editor.EditorInterface
    passed, failed = Ref(0), Ref(0)
    check(ok, what) = ok ? (passed[] += 1) : (failed[] += 1; println("FAILED: ", what))
    dir = Tools.project_dir()
    cleanup() = (foreach(f -> rm(joinpath(dir, f); force = true), ("Project.toml", "Manifest.toml"));
                 rm(joinpath(dir, ".vscode"); force = true, recursive = true))
    try
        cleanup()
        wait_frames(self, 2)

        # The Julia panel, Build button and settings.
        s = Tools.PLUGIN[]
        check(s !== nothing && Godot.is_inside_tree(s.panel.root), "Julia bottom panel added")
        check(s !== nothing && Godot.is_inside_tree(s.toolbar_button), "Build toolbar button added")
        es = Tools.editor_settings()
        for n in (Tools.S_EXTERNAL_EDITOR, Tools.S_EXEC_PATH, Tools.S_EXEC_ARGS, Tools.S_VERBOSITY, Tools.S_BUILD_ON_PLAY)
            check(Godot.has_setting(es, n), "editor setting $n")
        end
        for n in ("julia/project/package_name", "julia/project/reload_attempts", "julia/runtime/threads",
                  "julia/runtime/path", "julia/runtime/optimize")
            check(Godot.has_setting(Godot.ProjectSettings, n), "project setting $n")
        end

        # External editor selection.
        check(!R.BRIDGE[:overrides_external_editor](C_NULL), "built-in script editor by default")
        Godot.set_setting(es, Tools.S_EXTERNAL_EDITOR, Int(Tools.EDITOR_CUSTOM))
        check(R.BRIDGE[:overrides_external_editor](C_NULL), "external editor setting overrides the built-in editor")
        Godot.set_setting(es, Tools.S_EXTERNAL_EDITOR, Int(Tools.EDITOR_NONE))

        # Create Script dialog: templates, class-name validation, project bootstrap on the first script.
        toml = joinpath(dir, "Project.toml")
        check(!isfile(toml), "no Project.toml before the first script")
        for base in ("Object", "Node", "Resource", "EditorPlugin", "EditorScript")
            for t in R.language_get_built_in_templates(C_NULL, Symbol(base))
                src = R.language_make_template(C_NULL, t["content"], "MyScript", base)
                r = R.language_validate(C_NULL, src, "res://MyScript.jl", false, true, false, false)
                check(r["valid"], "template $base/$(t["name"]) validates")
            end
        end
        check(occursin("<: Godot.Editor.EditorPlugin", R.language_make_template(C_NULL, "", "P", "EditorPlugin")),
              "editor base classes are qualified")
        check(R.language_validate_path(C_NULL, "res://My Thing.jl") != "" && R.language_validate_path(C_NULL, "res://MyThing.jl") == "",
              "Create Script dialog validates the class name")
        check(isfile(toml), "creating a script bootstraps Project.toml")
        p = isfile(toml) ? Base.parsed_toml(toml) : Dict{String, Any}()
        check(get(p, "name", "") == "EditorTestGame" && haskey(get(p, "deps", Dict()), "Godot") &&
              haskey(get(p, "sources", Dict()), "Godot"), "Project.toml names the package and depends on Godot")

        # Global classes for the Create Node/Resource dialogs and typed export pickers.
        thing = [d for d in Godot.get_global_class_list(Godot.ProjectSettings) if String(d["class"]) == "Thing"]
        check(length(thing) == 1 && String(thing[1]["language"]) == "Julia" && String(thing[1]["base"]) == "Resource" &&
              endswith(String(thing[1]["icon"]), "JuliaScript.svg"), "global class listed with base type and icon")

        # Non-tool scripts get placeholder instances in the editor: exported values, no Julia code.
        plain = Godot.Node()
        Godot.set_script(plain, Godot.load(Godot.ResourceLoader, "res://Plain.jl"))
        Godot.add_child(self, plain)
        check(Godot.get(plain, "size") == 3 && !Godot.can_instantiate(Godot.get_script(plain)) &&
              !R.script_instance_has(Godot.Internals.native_ptr(Godot.get_script(plain)),
                                     Int64(UInt(Godot.Internals.native_ptr(plain)))),
              "placeholder instance with exported defaults for a non-tool script")
        Godot.set(plain, "size", 9)
        check(Godot.get(plain, "size") == 9, "placeholder stores edited values")

        # @tool scripts run in the editor and reload in place on save, keeping their state.
        spinner_path = joinpath(dir, "Spinner.jl")
        spinner_src = read(spinner_path, String)
        try
            sp = Godot.Node()
            id = Godot.get_instance_id(sp)
            scr = Godot.load(Godot.ResourceLoader, "res://Spinner.jl")
            Godot.set_script(sp, scr)
            sp = Godot.GD.instance_from_id(id)   # like C#, the object gets a new wrapper: the script instance
            Godot.add_child(self, sp)
            Godot.call(sp, "spin")
            Godot.set(sp, "speed", 2.5)
            check(Godot.call(sp, "spin") == 2, "tool script runs in the editor")
            Godot.set_source_code(scr, replace(spinner_src, "self.turns += 1" => "self.turns += 10") *
                                       "\nlabel_of(self::Spinner) = \"v2\"\n")
            Godot.save(Godot.ResourceSaver, scr, "res://Spinner.jl")
            sp = Godot.GD.instance_from_id(id)   # the reload migrated the instance to a new struct (ADR 0011)
            check(Godot.call(sp, "spin") == 12 && Godot.get(sp, "speed") == 2.5 && Godot.call(sp, "label_of") == "v2",
                  "saving a tool script reloads it in place with its state")
            Godot.queue_free(sp)
        finally
            write(spinner_path, spinner_src)
        end
        Godot.queue_free(plain)

        # Build: instantiate, precompile, validate; the deliberate error is reported with file:line.
        Tools.build!()
        t0 = time()
        while Tools.busy() && time() - t0 < 240
            wait(next_frame(self))
        end
        check(!Tools.busy(), "build finished")
        probs = Tools.problems()
        check(any(q -> q.file == "res://Bad.jl" && q.line == 7, probs), "build reports res://Bad.jl:7 ($probs)")
        check(Tools.last_build_ok() === false, "build fails on a script error")
        check(isfile(joinpath(dir, "Manifest.toml")), "build instantiated the project environment")
        check(any(l -> occursin("res://Bad.jl:7", l), Tools.LOG),
              "build output streamed to the Julia panel ($(join(Tools.LOG[max(1, end - 12):end], " | ")))")

        # Built-in script editor: Julia highlighting (Thing.jl) and validation errors (Bad.jl).
        current_code() = Godot.get_base_editor(Godot.get_current_editor(Godot.get_script_editor(EI)))
        Godot.edit_script(EI, Godot.load(Godot.ResourceLoader, "res://Thing.jl"), 1, 0)
        wait_frames(self, 10)
        code = current_code()
        highlighter = Godot.get_syntax_highlighter(code)
        Godot.update_cache(highlighter)   # headless editors never draw, so refresh the cache explicitly
        hl = Godot.get_line_syntax_highlighting(highlighter, 0)
        color(col) = haskey(hl, col) ? hl[col]["color"] : nothing
        check(Godot.get_class(highlighter) == "JuliaSyntaxHighlighter" && color(0) !== nothing && color(6) !== nothing &&
              color(0) != color(6), "Julia highlighter colors keywords ($hl; $(Godot.get_class(highlighter)))")
        hl2 = Godot.get_line_syntax_highlighting(highlighter, 2)   # @global_class @icon "res://..." @godot_class mutable
        check(haskey(hl2, 0) && haskey(hl2, 20) && hl2[20]["color"] != hl2[0]["color"], "macros and strings highlighted ($hl2)")
        Godot.edit_script(EI, Godot.load(Godot.ResourceLoader, "res://Bad.jl"), 1, 0)
        wait_frames(self, 30)
        check(Godot.get_class(Godot.get_syntax_highlighter(current_code())) == "JuliaSyntaxHighlighter",
              "Julia highlighter on script tabs restored from the previous session")
        check(Godot.get_line_background_color(current_code(), 6).a > 0, "validation error marked on line 7")
    catch e
        failed[] += 1
        R.report_exception(e, catch_backtrace())
    finally
        cleanup()
    end
    GodotTestRunner.report("editor"; passed = passed[], failed = failed[])
    Godot.quit(Godot.get_tree(self), failed[] == 0 ? 0 : 1)
end
