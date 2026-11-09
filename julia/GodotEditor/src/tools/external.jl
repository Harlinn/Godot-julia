# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# External editors (C#: GodotTools/Ides and `CSharpLanguage::open_in_external_editor`). Command construction is pure
# so it can be unit-tested per OS; launching goes through `OS.create_process`.

struct EditorCommand
    exec::String
    args::Vector{String}
end

Base.:(==)(a::EditorCommand, b::EditorCommand) = a.exec == b.exec && a.args == b.args

"Split a command-line template into arguments; double quotes group words."
function split_args(s::AbstractString)
    args = String[]
    buf = IOBuffer()
    quoted = started = false
    for c in s
        if c == '"'
            quoted = !quoted
            started = true
        elseif isspace(c) && !quoted
            started && push!(args, String(take!(buf)))
            started = false
        else
            write(buf, c)
            started = true
        end
    end
    started && push!(args, String(take!(buf)))
    return args
end

expand_placeholders(arg, file, line, col, project) =
    replace(arg, "{file}" => file, "{line}" => string(line), "{col}" => string(col), "{project}" => project)

"First existing candidate: an explicit path, else programs found on PATH."
function find_program(exec_path::AbstractString, names; which = Sys.which)
    isempty(exec_path) || return String(exec_path)
    for n in names
        p = which(n)
        p === nothing || return p
    end
    return nothing
end

"VS Code's `bin/code.cmd` on Windows cannot be started directly; use the `Code.exe` next to it."
function vscode_executable(p::AbstractString, windows::Bool; exists = isfile)
    windows && endswith(lowercase(p), ".cmd") || return String(p)
    exe = joinpath(dirname(dirname(p)), lowercase(basename(p)) == "codium.cmd" ? "VSCodium.exe" : "Code.exe")
    return exists(exe) ? exe : String(p)
end

"""
    external_editor_command(kind, file, line, col, project; exec_path, args_template, windows, which, exists)

Command opening `file` at 1-based `line`/`col` in the external editor `kind`, or `nothing` (no editor / not found).
"""
function external_editor_command(kind::ExternalEditor, file::AbstractString, line::Integer, col::Integer,
                                 project::AbstractString; exec_path::AbstractString = "", args_template::AbstractString = "{file}",
                                 windows::Bool = Sys.iswindows(), which = Sys.which, exists = isfile)
    kind == EDITOR_NONE && return nothing
    if kind == EDITOR_VSCODE || kind == EDITOR_VSCODIUM
        p = find_program(exec_path, kind == EDITOR_VSCODE ? ("code",) : ("codium",); which)
        p === nothing && return nothing
        return EditorCommand(vscode_executable(p, windows; exists), [String(project), "--goto", "$file:$line:$col"])
    elseif kind == EDITOR_EMACS
        p = find_program(exec_path, ("emacsclient", "emacs"); which)
        p === nothing && return nothing
        client = startswith(lowercase(basename(p)), "emacsclient")
        return EditorCommand(p, client ? ["-n", "+$line:$col", String(file)] : ["+$line:$col", String(file)])
    elseif kind == EDITOR_VIM
        p = find_program(exec_path, ("nvim-qt", "gvim", "nvim", "vim"); which)
        p === nothing && return nothing
        args = ["+call cursor($line, $col)", String(file)]
        return EditorCommand(p, startswith(lowercase(basename(p)), "nvim-qt") ? vcat("--", args) : args)
    else
        isempty(exec_path) && return nothing
        return EditorCommand(String(exec_path), [expand_placeholders(a, file, line, col, project) for a in split_args(args_template)])
    end
end

const DEBUG_PORT = 47100

"""
Workspace settings so the Julia extension uses the project environment, plus (given the Godot executable) a task
that runs the game with the Julia debug server and a launch config for the debug REPL client (docs/debugging.md).
Files are written only if missing.
"""
function write_vscode_settings!(project::AbstractString; godot::AbstractString = "")
    dir = joinpath(project, ".vscode")
    mkpath(dir)
    settings = joinpath(dir, "settings.json")
    isfile(settings) || write(settings, "{\n    \"julia.environmentPath\": $(repr(replace(String(project), '\\' => '/')))\n}\n")
    ext = joinpath(dir, "extensions.json")
    isfile(ext) || write(ext, "{\n    \"recommendations\": [\"julialang.language-julia\"]\n}\n")
    isempty(godot) && return nothing
    tasks = joinpath(dir, "tasks.json")
    isfile(tasks) || write(tasks, """
        {
            "version": "2.0.0",
            "tasks": [
                {
                    "label": "Godot: run game with Julia debug server",
                    "type": "process",
                    "command": $(repr(replace(String(godot), '\\' => '/'))),
                    "args": ["--path", "\${workspaceFolder}"],
                    "options": { "env": { "GDJL_DEBUG_PORT": "$DEBUG_PORT" } },
                    "isBackground": true,
                    "problemMatcher": []
                }
            ]
        }
        """)
    launch = joinpath(dir, "launch.json")
    isfile(launch) || write(launch, """
        {
            "version": "0.2.0",
            "configurations": [
                {
                    "name": "Godot: Julia debug REPL",
                    "type": "julia",
                    "request": "launch",
                    "program": "\${workspaceFolder}/addons/godot_julia/tools/godot_repl.jl",
                    "args": ["$DEBUG_PORT"],
                    "juliaEnv": "\${workspaceFolder}"
                }
            ]
        }
        """)
    return nothing
end

const ERR_OK, ERR_FAILED, ERR_UNAVAILABLE = 0, 1, 2

overrides_external_editor(::Ptr{Cvoid}) = external_editor() != EDITOR_NONE

"Bridge handler for `JuliaLanguage::_open_in_external_editor` (Godot passes 0-based line and column)."
function open_in_external_editor(::Ptr{Cvoid}, script, line::Integer, col::Integer)
    script === nothing && return ERR_UNAVAILABLE
    file = Godot.globalize_path(Godot.ProjectSettings, Godot.get_path(script))
    kind = external_editor()
    project = project_dir()
    cmd = external_editor_command(kind, file, max(line, 0) + 1, max(col, 0) + 1, project;
                                  exec_path = editor_setting(S_EXEC_PATH, ""), args_template = editor_setting(S_EXEC_ARGS, "{file}"))
    if cmd === nothing
        log!("No external editor found for $(kind); set $(S_EXEC_PATH).")
        return ERR_UNAVAILABLE
    end
    kind in (EDITOR_VSCODE, EDITOR_VSCODIUM) && write_vscode_settings!(project; godot = Godot.get_executable_path(Godot.OS))
    pid = Godot.create_process(Godot.OS, cmd.exec, cmd.args)
    return pid > 0 ? ERR_OK : ERR_FAILED
end
