#!/usr/bin/env julia
# Exports test projects with the headless editor and runs the exported games (phase 14, ADR 0014).
# Usage: julia tests/export/run.jl [config...]   configs: sysimage-debug sysimage-release jit-debug (default: all)
# Needs the native template libraries (scons target=template_debug / template_release) and the official export
# templates archive in .tools/godot/ (Godot_v<version>_export_templates.tpz) or installed templates.
# Exports are made for the host platform: Julia payloads cannot be cross-compiled.

import p7zip_jll

const ROOT = normpath(joinpath(@__DIR__, "..", ".."))
const WORK = joinpath(ROOT, ".tools", "export_work")
const TIMEOUT = parse(Float64, get(ENV, "GDJL_TEST_TIMEOUT", "7200"))
const PROJECTS = [("game", joinpath(@__DIR__, "game")), ("smoke", joinpath(ROOT, "tests", "integration", "smoke"))]
const VERSION_TAG = strip(read(joinpath(ROOT, "GODOT_VERSION"), String))

include(joinpath(ROOT, "tests", "integration", "godot_path.jl"))
find_godot() = find_godot(ROOT)

host_arch() = Sys.ARCH === :aarch64 ? "arm64" : string(Sys.ARCH)
platform_name() = Sys.iswindows() ? "Windows Desktop" : Sys.isapple() ? "macOS" : "Linux"
template_name(debug) = Sys.iswindows() ? "windows_$(debug ? "debug" : "release")_$(host_arch()).exe" :
                       Sys.isapple() ? "macos.zip" : "linux_$(debug ? "debug" : "release").$(host_arch())"
exe_name() = Sys.iswindows() ? "game.exe" : Sys.isapple() ? "game.app" : "game.$(host_arch())"

"Executable to run: the Windows console wrapper (forwards output to the pipe), the binary inside the macOS bundle."
function run_path(out)
    Sys.iswindows() && return joinpath(out, "game.console.exe")
    if Sys.isapple()
        macos = joinpath(out, "game.app", "Contents", "MacOS")
        return joinpath(macos, first(readdir(macos)))
    end
    return joinpath(out, exe_name())
end

"Folder that receives the export's shared objects (and so the Julia `data_*` folder)."
shared_dir(out) = Sys.isapple() ? joinpath(out, "game.app", "Contents", "Frameworks") : out

"Template file from the archive in .tools/godot (extracted once), else Godot's installed templates (empty string)."
function template(debug)
    dir = joinpath(ROOT, ".tools", "godot", "templates")
    file = joinpath(dir, template_name(debug))
    isfile(file) && return file
    tpz = joinpath(ROOT, ".tools", "godot", "Godot_v$(VERSION_TAG)_export_templates.tpz")
    isfile(tpz) || return ""
    mkpath(dir)
    names = [template_name(true), template_name(false)]
    Sys.iswindows() && append!(names, replace.(names, ".exe" => "_console.exe"))
    for n in names
        run(pipeline(`$(p7zip_jll.p7zip()) e $tpz -o$dir templates/$n -y`; stdout = devnull))
    end
    return file
end

function presets_text(mode, debug)
    q(s) = "\"" * replace(s, '\\' => '/') * "\""
    win = Sys.iswindows() ? "\ndebug/export_console_wrapper=2\napplication/modify_resources=false" : ""
    mac = Sys.isapple() ? "\napplication/bundle_identifier=\"org.godotjl.exporttest\"\ncodesign/codesign=1\nnotarization/notarization=0" : ""
    return """
    [preset.0]

    name="Desktop"
    platform=$(q(platform_name()))
    runnable=true
    dedicated_server=false
    custom_features=""
    export_filter="all_resources"
    include_filter=""
    exclude_filter=""
    export_path=""
    script_export_mode=2

    [preset.0.options]

    custom_template/debug=$(q(template(true)))
    custom_template/release=$(q(template(false)))
    binary_format/embed_pck=false
    binary_format/architecture=$(q(host_arch()))
    texture_format/s3tc_bptc=true
    texture_format/etc2_astc=false
    julia/export/mode=$(q(mode))
    julia/export/include_sources=false$win$mac
    """
end

function run_logged(cmd, log)
    t = time()
    code = open(log, "w") do io
        p = run(pipeline(ignorestatus(cmd); stdout = io, stderr = io); wait = false)
        timer = Timer(_ -> process_running(p) && kill(p), TIMEOUT)
        wait(p)
        close(timer)
        p.exitcode
    end
    return code, time() - t, read(log, String)
end

dir_size(d) = sum((filesize(joinpath(r, f)) for (r, _, fs) in walkdir(d) for f in fs); init = 0)
mib(n) = round(n / 2^20; digits = 1)

function export_and_run(godot, name, src, config)
    mode, kind = split(config, '-')
    debug = kind == "debug"
    work = joinpath(WORK, "$name-$config")
    rm(work; force = true, recursive = true)
    mkpath(WORK)
    cp(src, work)
    rm(joinpath(work, ".godot"); force = true, recursive = true)
    mkpath(joinpath(work, "addons"))
    cp(joinpath(ROOT, "addons", "godot_julia"), joinpath(work, "addons", "godot_julia"); force = true)
    mkpath(joinpath(work, ".godot"))
    write(joinpath(work, ".godot", "extension_list.cfg"), "res://addons/godot_julia/godot_julia.gdextension\n")
    write(joinpath(work, "export_presets.cfg"), presets_text(mode, debug))
    out = joinpath(work, "out")
    mkpath(out)
    failures = String[]

    code, _, _ = run_logged(`$godot --headless --path $work --import`, joinpath(work, "import.log"))
    code == 0 || push!(failures, "import exited with $code")
    flag = debug ? "--export-debug" : "--export-release"
    code, export_s, export_log = run_logged(`$godot --headless --path $work $flag Desktop $(joinpath(out, exe_name()))`,
                                            joinpath(work, "export.log"))
    code == 0 || push!(failures, "export exited with $code")
    shared = shared_dir(out)
    data = isdir(shared) ? filter(d -> startswith(d, "data_") && isdir(joinpath(shared, d)), readdir(shared)) : String[]
    length(data) == 1 || push!(failures, "expected one data_* folder in $shared, found $(data)")
    occursin("Julia export:", export_log) && push!(failures, "export reported Julia errors (see export.log)")

    size = isdir(out) ? dir_size(out) : 0
    run_s, startup_ms = NaN, ""
    if isempty(failures)
        code, run_s, output = run_logged(`$(run_path(out)) --headless -- mode=$mode debug=$debug`,
                                         joinpath(work, "run.log"))
        code == 0 || push!(failures, "game exited with $code")
        m = match(r"GDJL_TEST_RESULT \{[^\n]*\"passed\":(\d+),\"failed\":(\d+)", output)
        m === nothing ? push!(failures, "no GDJL_TEST_RESULT {json} line") :
            (m[2] == "0" && m[1] != "0") || push!(failures, "in-game checks: passed=$(m[1]) failed=$(m[2])")
        s = match(r"startup (\d+) ms", output)
        s === nothing ? push!(failures, "no GodotJL startup line") : (startup_ms = s[1])
        foreach(l -> push!(failures, "game: $l"), filter(l -> startswith(l, "FAILED") || startswith(l, "ERROR:"),
                                                          split(output, '\n')))
    end
    status = isempty(failures) ? "PASS" : "FAIL"
    println(rpad("$status  $name $config", 32), "export $(round(export_s; digits = 1)) s, size $(mib(size)) MiB",
            isempty(startup_ms) ? "" : ", Julia startup $startup_ms ms, run $(round(run_s; digits = 1)) s")
    foreach(f -> println("      ", f), failures)
    isempty(failures) || println("      logs: ", work)
    return isempty(failures)
end

function main()
    configs = isempty(ARGS) ? ["sysimage-debug", "sysimage-release", "jit-debug"] : ARGS
    godot = find_godot()
    println("Using ", godot)
    results = Bool[]
    for config in configs, (name, src) in PROJECTS
        # The smoke project only checks that the payload boots; once per config is enough.
        push!(results, export_and_run(godot, name, src, config))
    end
    println(count(results), "/", length(results), " exports passed")
    exit(all(results) ? 0 : 1)
end

main()
