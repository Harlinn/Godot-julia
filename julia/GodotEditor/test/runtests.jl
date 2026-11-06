using Test
using TOML
using Godot
using GodotEditor
const T = GodotEditor.Tools

@testset "GodotEditor tools" begin
    @testset "export decisions and config" begin
        hp, ha = T.host_platform(), T.host_arch()
        @test T.export_blocker(hp, ha, "sysimage", false) === nothing
        @test T.export_blocker(hp, ha, "jit", true) === nothing
        @test occursin("debug exports only", T.export_blocker(hp, ha, "jit", false))
        @test occursin("Windows, Linux and macOS", T.export_blocker(nothing, ha, "sysimage", true))
        other = hp == "linux" ? "windows" : "linux"
        @test occursin("must be made on a $other", T.export_blocker(other, ha, "sysimage", true))
        @test occursin("unknown", T.export_blocker(hp, ha, "trimmed", true))
        @test T.export_data_dir_name("MyGame", "windows", "x86_64") == "data_MyGame_windows_x86_64"
        text = T.export_config_text(; mode = "sysimage", debug = true, platform = "windows", arch = "x86_64",
                                    features = ["pc", "debug"], data_dir = "C:\\g\\data \"x\"",
                                    global_classes = Dict("Enemy" => "res://Enemy.jl"))
        cfg = TOML.parse(text)
        @test cfg["mode"] == "sysimage" && cfg["debug"] === true && cfg["features"] == ["pc", "debug"]
        @test cfg["data_dir"] == "C:\\g\\data \"x\"" && cfg["global_classes"] == Dict("Enemy" => "res://Enemy.jl")
    end
    @testset "external editor commands" begin
        unix(n) = "/usr/bin/$n"
        none(n) = nothing
        cmd(kind; kw...) = T.external_editor_command(kind, "/p/A.jl", 3, 4, "/p"; windows = false, which = unix, kw...)
        @test cmd(T.EDITOR_NONE) === nothing
        @test cmd(T.EDITOR_VSCODE) == T.EditorCommand("/usr/bin/code", ["/p", "--goto", "/p/A.jl:3:4"])
        @test cmd(T.EDITOR_VSCODIUM) == T.EditorCommand("/usr/bin/codium", ["/p", "--goto", "/p/A.jl:3:4"])
        @test cmd(T.EDITOR_EMACS) == T.EditorCommand("/usr/bin/emacsclient", ["-n", "+3:4", "/p/A.jl"])
        @test cmd(T.EDITOR_EMACS; which = n -> n == "emacs" ? "/usr/bin/emacs" : nothing) ==
              T.EditorCommand("/usr/bin/emacs", ["+3:4", "/p/A.jl"])
        @test cmd(T.EDITOR_VIM) == T.EditorCommand("/usr/bin/nvim-qt", ["--", "+call cursor(3, 4)", "/p/A.jl"])
        @test cmd(T.EDITOR_VIM; which = n -> n == "gvim" ? "/usr/bin/gvim" : nothing) ==
              T.EditorCommand("/usr/bin/gvim", ["+call cursor(3, 4)", "/p/A.jl"])
        @test cmd(T.EDITOR_VSCODE; which = none) === nothing
        @test cmd(T.EDITOR_VSCODE; exec_path = "/opt/code/bin/code").exec == "/opt/code/bin/code"
        @test cmd(T.EDITOR_CUSTOM) === nothing   # needs an executable
        @test cmd(T.EDITOR_CUSTOM; exec_path = "/bin/ed", args_template = "--line {line} \"{file}:{col}\" -C {project}") ==
              T.EditorCommand("/bin/ed", ["--line", "3", "/p/A.jl:4", "-C", "/p"])
        # Windows: VS Code's code.cmd shim is replaced by Code.exe next to it.
        win = T.external_editor_command(T.EDITOR_VSCODE, "C:/p/A.jl", 1, 1, "C:/p"; windows = true,
                                        which = n -> "C:/VSCode/bin/code.cmd", exists = f -> endswith(f, "Code.exe"))
        @test win == T.EditorCommand(joinpath("C:/VSCode", "Code.exe"), ["C:/p", "--goto", "C:/p/A.jl:1:1"])
        win2 = T.external_editor_command(T.EDITOR_VSCODE, "C:/p/A.jl", 1, 1, "C:/p"; windows = true,
                                         which = n -> "C:/VSCode/bin/code.cmd", exists = f -> false)
        @test win2.exec == "C:/VSCode/bin/code.cmd"
    end

    @testset "argument templates" begin
        @test T.split_args("a b  \"c d\" e") == ["a", "b", "c d", "e"]
        @test T.split_args("") == String[]
        @test T.expand_placeholders("{file}:{line}:{col}@{project}", "f", 1, 2, "p") == "f:1:2@p"
    end

    @testset "project bootstrap" begin
        @test T.sanitize_package_name("my game 2") == "MyGame2"
        @test T.sanitize_package_name("2d-shooter") == "Project2dShooter"
        @test T.sanitize_package_name("!!") == "GodotProject"
        u = T.uuid4()
        @test string(u)[15] == '4' && string(u)[20] in "89ab"
        text = T.project_toml_text("MyGame", u, "addons/godot_julia/julia/Godot", v"0.1.0")
        p = mktempdir() do d
            f = joinpath(d, "Project.toml")
            write(f, text)
            Base.parsed_toml(f)
        end
        @test p["name"] == "MyGame" && p["deps"]["Godot"] == T.GODOT_PKG_UUID
        @test p["sources"]["Godot"]["path"] == "addons/godot_julia/julia/Godot" && p["compat"]["Godot"] == "0.1.0"
        mktempdir() do dir
            @test T.godot_source(dir) == replace(joinpath(T.packages_dir(), "Godot"), '\\' => '/')
            mkpath(joinpath(dir, "addons", "godot_julia", "julia", "Godot"))
            @test T.godot_source(dir) == "addons/godot_julia/julia/Godot"
        end
    end

    @testset "build output protocol" begin
        p = T.parse_problem("GDJL_PROBLEM\terror\tres://A.jl\t7\t3\tsyntax error: oops")
        @test p == T.Problem(:error, "res://A.jl", 7, 3, "syntax error: oops")
        @test T.parse_problem("GDJL_PROBLEM\terror") === nothing
        empty!(T.PROBLEMS); empty!(T.LOG)
        T.handle_line!("GDJL_PROBLEM\terror\tres://B.jl\t2\t1\tbad\r")
        T.handle_line!("GDJL_STEP\tValidating scripts")
        T.handle_line!("plain output")
        @test T.problems() == [T.Problem(:error, "res://B.jl", 2, 1, "bad")]
        @test T.LOG == ["res://B.jl:2:1: error: bad", "==> Validating scripts", "plain output"]
        T.clear_output!()
        @test isempty(T.LOG) && isempty(T.PROBLEMS)
    end

    @testset "VS Code workspace settings" begin
        mktempdir() do dir
            T.write_vscode_settings!(dir)
            s = read(joinpath(dir, ".vscode", "settings.json"), String)
            @test occursin("julia.environmentPath", s)
            @test occursin("julialang.language-julia", read(joinpath(dir, ".vscode", "extensions.json"), String))
            write(joinpath(dir, ".vscode", "settings.json"), "{}")
            T.write_vscode_settings!(dir)
            @test read(joinpath(dir, ".vscode", "settings.json"), String) == "{}"   # never overwritten
            @test !isfile(joinpath(dir, ".vscode", "launch.json"))
            T.write_vscode_settings!(dir; godot = "C:\\Godot\\godot.exe")
            launch = read(joinpath(dir, ".vscode", "launch.json"), String)
            tasks = read(joinpath(dir, ".vscode", "tasks.json"), String)
            @test occursin("\"type\": \"julia\"", launch) && occursin("addons/godot_julia/tools/godot_repl.jl", launch)
            @test occursin("\"$(T.DEBUG_PORT)\"", launch)
            @test occursin("\"C:/Godot/godot.exe\"", tasks) && occursin("\"GDJL_DEBUG_PORT\": \"$(T.DEBUG_PORT)\"", tasks)
            @test occursin("\${workspaceFolder}", tasks)
        end
    end

    @testset "worker script" begin
        mktempdir() do dir
            write(joinpath(dir, "Good.jl"), "using Godot\n@godot_class mutable struct Good <: Node\nend\n")
            write(joinpath(dir, "Bad.jl"), "using Godot\nf(x) = (1, 2]\ng() = 3\n")
            mkpath(joinpath(dir, "addons", "godot_julia", "julia"))
            write(joinpath(dir, "addons", "godot_julia", "julia", "Skip.jl"), "(")
            out = IOBuffer()
            proc = run(pipeline(ignorestatus(`$(T.julia_exe()) --startup-file=no $(T.worker_script()) $(T.packages_dir()) - $dir 1 build`);
                                stdout = out, stderr = out))
            text = String(take!(out))
            @test proc.exitcode == 1
            @test occursin("GDJL_PROBLEM\terror\tres://Bad.jl\t2\t", text)
            @test !occursin("Skip.jl", text) && !occursin("Good.jl\t", text)
            @test occursin(r"Validated 2 script\(s\): [1-9]\d* error\(s\)\.", text)
        end
    end

    @testset "package actions" begin
        worker(dir, args...) = withenv("JULIA_PKG_OFFLINE" => "true") do
            out = IOBuffer()
            p = run(pipeline(ignorestatus(`$(T.julia_exe()) --startup-file=no $(T.worker_script()) $(T.packages_dir()) - $dir 1 $args`);
                             stdout = out, stderr = out))
            p.exitcode, String(take!(out))
        end
        mktempdir() do dir
            code, text = worker(dir, "pkg", "status")
            @test code == 1 && occursin("No Project.toml", text)
            write(joinpath(dir, "Project.toml"), T.project_toml_text("PkgTest", T.uuid4(), T.godot_source(dir), v"0.1.0"))
            code, _ = worker(dir, "pkg", "add", "Printf")
            @test code == 0 && haskey(Base.parsed_toml(joinpath(dir, "Project.toml"))["deps"], "Printf")
            code, text = worker(dir, "pkg", "status")
            @test code == 0 && occursin("Printf", text)
            code, _ = worker(dir, "pkg", "rm", "Printf")
            @test code == 0 && !haskey(Base.parsed_toml(joinpath(dir, "Project.toml"))["deps"], "Printf")
        end
    end

    @testset "bridge handlers installed" begin
        for k in (:editor_plugin_enter_tree, :editor_plugin_exit_tree, :editor_plugin_process, :editor_plugin_build,
                  :overrides_external_editor, :open_in_external_editor)
            @test haskey(Godot.Runtime.BRIDGE, k)
        end
    end
end
