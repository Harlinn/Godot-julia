#!/usr/bin/env julia
# Copies a C# demo from godot-demo-projects (mono/<name>) into demos/<dest>, converting the project to Julia:
# drops C# project files and .cs scripts, points scene script references at .jl files, renames signal
# connection methods and exported properties to snake_case, removes the [dotnet] section and the "C#" feature.
# The Julia scripts themselves are written by hand next to the copied scenes.
# Usage: julia scripts/port_csharp_demo.jl <godot-demo-projects checkout> <mono demo name> <dest name>

function snake(s::AbstractString)
    s = replace(s, r"^_" => "")
    s = replace(s, r"([a-z])([0-9]+[A-Z]?)(?=[A-Z]|$)" => s -> lowercase(s))   # Notifier2D -> notifier2d
    s = replace(s, r"([a-z0-9])([A-Z])" => s"\1_\2")
    s = replace(s, r"([A-Z]+)([A-Z][a-z])" => s"\1_\2")
    return lowercase(s)
end

function convert_scene(text::AbstractString)
    # The .cs scripts' UIDs do not exist for the .jl files; Godot resolves the path instead.
    text = replace(text, r"(\[ext_resource type=\"Script\") uid=\"[^\"]*\"" => s"\1")
    text = replace(text, r"path=\"(res://[^\"]+)\.cs\"" => s -> replace(s, ".cs\"" => ".jl\""))
    text = replace(text, r"(\[connection [^\]]*method=\")([A-Za-z0-9_]+)(\")" => s -> begin
        m = match(r"(\[connection [^\]]*method=\")([A-Za-z0-9_]+)(\")", s)
        m[1] * snake(m[2]) * m[3]
    end)
    text = replace(text, r"(\[connection signal=\")([A-Za-z]+)(\")" => s -> begin
        m = match(r"(\[connection signal=\")([A-Za-z]+)(\")", s)
        m[1] * snake(m[2]) * m[3]
    end)
    # Exported script properties set in the scene: C# PascalCase properties or _camelCase fields (engine-internal
    # properties such as Curve3D's `_data` stay as they are).
    text = replace(text, r"(?m)^(_?[A-Za-z][A-Za-z0-9]*) = " => s -> begin
        name = match(r"^(_?[A-Za-z][A-Za-z0-9]*)", s)[1]
        csharp = isuppercase(name[1]) || (startswith(name, "_") && any(isuppercase, name))
        csharp ? snake(name) * " = " : s
    end)
    return text
end

function convert_project(text::AbstractString)
    text = replace(text, r"\[dotnet\]\n(?:[^\[\n][^\n]*\n|\n)*" => "")
    text = replace(text, r", \"C#\"" => "")
    text = replace(text, r"config/name=\"([^\"]*?) (?:with|in) C#\"" => s"config/name=\"\1 with Julia\"")
    text = replace(text, "ported to C#" => "ported to Julia")
    return text
end

function port(src_root, demo, dest_name)
    src = joinpath(src_root, "mono", demo)
    dest = joinpath(@__DIR__, "..", "demos", dest_name)
    isdir(dest) && error("$dest exists")
    for (dir, _, names) in walkdir(src)
        rel = relpath(dir, src)
        for n in names
            (endswith(n, ".cs") || endswith(n, ".csproj") || endswith(n, ".sln") || endswith(n, ".cs.uid")) && continue
            target = joinpath(dest, rel, n)
            mkpath(dirname(target))
            path = joinpath(dir, n)
            if endswith(n, ".tscn") || endswith(n, ".tres")
                write(target, convert_scene(read(path, String)))
            elseif n == "project.godot"
                write(target, convert_project(read(path, String)))
            else
                cp(path, target; force = true)
            end
        end
    end
    println("Ported mono/$demo -> demos/$dest_name")
end

port(ARGS[1], ARGS[2], ARGS[3])
