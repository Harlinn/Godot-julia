# Worker command `export <config.toml>`: build the Julia payload of an export (included by worker.jl).
# sysimage mode: compile Godot, the project's packages and every script into a system image (`julia --output-o`,
# linked with Julia's bundled lld), like C#'s ReadyToRun publish. jit mode: ship package sources and compiled caches.
# Both ship the Julia runtime libraries. Layout: docs/adr/0014-export.md.

using TOML

const EXPORT_CONFIG_FILE = "godot_julia_export.cfg"
const DEFAULT_CPU_TARGET = Sys.ARCH === :x86_64 ? "generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)" : "generic"

julia_home() = dirname(Sys.BINDIR)
image_ext() = Sys.iswindows() ? "dll" : Sys.isapple() ? "dylib" : "so"

function copy_tree(src, dst; keep = (rel, name) -> true)
    for (dir, _, names) in walkdir(src)
        rel = relpath(dir, src)
        for n in names
            keep(rel, n) || continue
            target = joinpath(dst, rel, n)
            mkpath(dirname(target))
            cp(joinpath(dir, n), target; force = true)
        end
    end
end

"The Julia runtime the game needs: shared libraries, stdlib and Base sources (for JIT fallbacks and stack traces)."
function copy_runtime(data::String, mode::String)
    home, dst = julia_home(), joinpath(data, "julia")
    dll(n) = endswith(n, ".dll") || occursin(r"\.so(\.|$)", n) || endswith(n, ".dylib")
    default_image(n) = startswith(n, "sys.") || startswith(n, "sys-")
    mkpath(joinpath(dst, "bin"))
    Sys.iswindows() && copy_tree(joinpath(home, "bin"), joinpath(dst, "bin"); keep = (rel, n) -> rel == "." && dll(n))
    copy_tree(joinpath(home, "lib"), joinpath(dst, "lib");
              keep = (rel, n) -> dll(n) && (mode == "jit" || !default_image(n)))
    shipped(rel) = !any(in(("test", "docs")), splitpath(rel))
    for sub in ("base", "stdlib")
        copy_tree(joinpath(home, "share", "julia", sub), joinpath(dst, "share", "julia", sub); keep = (rel, n) -> shipped(rel))
    end
    cert = joinpath(home, "share", "julia", "cert.pem")
    isfile(cert) && cp(cert, joinpath(dst, "share", "julia", "cert.pem"); force = true)
    return nothing
end

project_deps() = isfile(TOML_PATH) ? Dict{String, String}(get(TOML.parsefile(TOML_PATH), "deps", Dict())) : Dict{String, String}()

"""
Dependencies of the exported game. sysimage mode writes them as the game's environment (the packages are in the
image); jit mode resolves packages from the shipped package directory instead, so it writes none.
"""
function write_env(data::String, mode::String)
    deps = project_deps()
    deps["Godot"] = string(GODOT.uuid)
    mode == "sysimage" || return deps
    env = joinpath(data, "env")
    mkpath(env)
    open(joinpath(env, "Project.toml"), "w") do io
        TOML.print(io, Dict("deps" => deps))
    end
    return deps
end

ospathsep() = Sys.iswindows() ? ";" : ":"

function run_logged(cmd::Cmd)
    VERBOSITY >= 2 && println(cmd)
    p = run(pipeline(ignorestatus(cmd); stdout, stderr = stdout))
    return p.exitcode == 0
end

"Julia code run by the image-building process: load the packages, compile the scripts, report failures."
function image_build_script(cfg, scripts::Dict{String, String}, deps::Dict{String, String}, failures_file::String)
    loads = join(("Base.require(Base.PkgId(Base.UUID($(repr(u))), $(repr(n))))" for (n, u) in deps if n != "Godot"), "\n    ")
    classes = repr(Dict{String, String}(get(cfg, "global_classes", Dict())))
    return """
    empty!(LOAD_PATH); append!(LOAD_PATH, ["@", $(repr(PACKAGES)), "@stdlib"])
    $(DEPOT == "-" ? "" : "pushfirst!(DEPOT_PATH, $(repr(DEPOT)))")
    using Godot
    let
        $loads
        scripts = $(repr(scripts))
        sources = Dict{String, String}(path => read(file, String) for (path, file) in scripts)
        failed = Godot.Runtime.precompile_scripts!(sources, $classes, $(repr(String.(cfg["features"]))))
        open($(repr(failures_file)), "w") do io
            for (path, msg) in sort!(collect(failed))
                println(io, path, "\\t", replace(msg, r"[\\r\\n\\t]+" => " "))
            end
        end
        println("Compiled \$(length(scripts) - length(failed)) of \$(length(scripts)) script(s) into the system image.")
    end
    """
end

function build_image(cfg, data::String, scripts::Dict{String, String}, deps::Dict{String, String})
    debug = cfg["debug"] === true
    work = data * ".build"
    rm(work; force = true, recursive = true)
    mkpath(work)
    failures_file = joinpath(work, "failures.txt")
    script = joinpath(work, "build_image.jl")
    write(script, image_build_script(cfg, scripts, deps, failures_file))
    obj = joinpath(work, "sys.o")
    image = joinpath(data, "sys." * image_ext())
    project = isfile(TOML_PATH) ? PROJECT : joinpath(data, "env")
    cpu_target = get(ENV, "GDJL_EXPORT_CPU_TARGET", DEFAULT_CPU_TARGET)
    flags = debug ? ["-O2", "-g1"] : ["-O3", "-g0"]
    step("Compiling the system image ($(debug ? "debug" : "release"), cpu target $cpu_target)")
    t = time()
    default_image = unsafe_string(Base.JLOptions().image_file)
    ok = run_logged(`$(joinpath(Sys.BINDIR, Base.julia_exename())) --startup-file=no --history-file=no
                     --sysimage=$default_image --project=$project --output-o=$obj --cpu-target=$cpu_target $flags $script`)
    ok || (problem("error", "", 0, 0, "building the system image failed"); return false)
    for line in (isfile(failures_file) ? readlines(failures_file) : String[])
        path, msg = split(line, '\t'; limit = 2)
        problem("warning", path, 1, 1, "not compiled into the system image (shipped as source and evaluated at runtime): $msg")
        dst = joinpath(data, "scripts", path[7:end])
        mkpath(dirname(dst))
        cp(scripts[path], dst; force = true)
    end
    step("Linking the system image")
    Base.Linking.link_image(obj, image)
    rm(work; force = true, recursive = true)
    println("System image: $(round(filesize(image) / 2^20; digits = 1)) MiB in $(round(time() - t; digits = 1)) s")
    return true
end

"jit mode: package sources inside the game's depot (so compiled caches relocate) and their compiled caches."
function stage_jit(data::String, deps::Dict{String, String})
    depot = joinpath(data, "depot")
    pkgdir = joinpath(depot, "packages")
    step("Copying packages")
    for (name, uuid) in deps
        id = Base.PkgId(Base.UUID(uuid), name)
        src = Base.locate_package(id)
        src === nothing && (Base.is_stdlib(id) || problem("error", "", 0, 0, "package $name not found"); continue)
        root = dirname(dirname(src))
        copy_tree(root, joinpath(pkgdir, name); keep = (rel, n) -> !startswith(rel, "test") && !startswith(rel, ".git"))
    end
    step("Precompiling packages")
    env = copy(ENV)
    env["JULIA_DEPOT_PATH"] = depot
    env["JULIA_LOAD_PATH"] = join([pkgdir, "@stdlib"], ospathsep())
    delete!(env, "JULIA_PROJECT")
    code = join(("using $n" for n in keys(deps)), "; ")
    return run_logged(setenv(`$(joinpath(Sys.BINDIR, Base.julia_exename())) --startup-file=no -e $code`, env))
end

function export_game(config_file::AbstractString)
    cfg = TOML.parsefile(config_file)
    data, mode, debug = cfg["data_dir"], cfg["mode"], cfg["debug"] === true
    step("Building the Julia payload ($mode, $(debug ? "debug" : "release")) in $data")
    mkpath(data)
    deps = write_env(data, mode)
    scripts = Dict{String, String}(res_path(f) => f for f in script_files(PROJECT))
    ok = mode == "sysimage" ? build_image(cfg, data, scripts, deps) :
         mode == "jit" ? stage_jit(data, deps) : (problem("error", "", 0, 0, "unknown export mode $mode"); false)
    ok || return false
    step("Copying the Julia runtime")
    copy_runtime(data, mode)
    open(joinpath(data, EXPORT_CONFIG_FILE), "w") do io
        println(io, "[julia]")
        println(io, "mode=\"", mode, "\"")
        mode == "sysimage" && println(io, "sysimage=\"sys.", image_ext(), "\"")
        println(io, "optimize=", debug ? 2 : 3)
    end
    size = sum(filesize(joinpath(d, f)) for (d, _, fs) in walkdir(data) for f in fs; init = 0)
    println("Julia payload: $(round(size / 2^20; digits = 1)) MiB")
    return true
end
