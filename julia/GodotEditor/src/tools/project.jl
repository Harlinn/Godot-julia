# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Project bootstrap (C#: the .csproj/.sln GodotTools generates for the first C# script).

const GODOT_PKG_UUID = "f37c0048-e111-4823-9dfb-7d6ad2e3f4cb"

project_dir() = rstrip(replace(String(Godot.globalize_path(Godot.ProjectSettings, "res://")), '\\' => '/'), '/')
project_toml(dir = project_dir()) = joinpath(dir, "Project.toml")
has_project(dir = project_dir()) = isfile(project_toml(dir))

"PascalCase package name from a project name (`my game 2` → `MyGame2`)."
function sanitize_package_name(s::AbstractString)
    n = join(uppercasefirst.(split(s, r"[^A-Za-z0-9]+"; keepempty = false)))
    isempty(n) && return "GodotProject"
    return isdigit(n[1]) ? "Project" * n : n
end

function package_name()
    configured = Godot.get_setting(Godot.ProjectSettings, S_PACKAGE_NAME)
    configured isa AbstractString && !isempty(configured) && return sanitize_package_name(configured)
    return sanitize_package_name(string(something(Godot.get_setting(Godot.ProjectSettings, "application/config/name"), "")))
end

"A random (version 4) UUID; avoids depending on the UUIDs stdlib."
function uuid4()
    u = rand(UInt128)
    u = (u & ~(UInt128(0xf) << 76)) | (UInt128(4) << 76)
    u = (u & ~(UInt128(0x3) << 62)) | (UInt128(2) << 62)
    return Base.UUID(u)
end

packages_dir() = dirname(dirname(dirname(pathof(Godot))))

"Path of the Godot package for `[sources]`: the copy shipped in the addon (relative) or the development checkout."
function godot_source(dir::AbstractString)
    rel = "addons/godot_julia/julia/Godot"
    isdir(joinpath(dir, rel)) && return rel
    return replace(joinpath(packages_dir(), "Godot"), '\\' => '/')
end

function project_toml_text(name::AbstractString, uuid::Base.UUID, godot_path::AbstractString, godot_version::VersionNumber)
    return """
    name = "$name"
    uuid = "$uuid"
    version = "0.1.0"

    [deps]
    Godot = "$GODOT_PKG_UUID"

    [compat]
    Godot = "$(godot_version.major).$(godot_version.minor).$(godot_version.patch)"
    julia = "1.12"

    [sources]
    Godot = {path = "$godot_path"}
    """
end

"""
    create_project!(dir = project_dir(); name = package_name()) -> Bool

Write `Project.toml` (depending on the Godot package of this editor) and activate it; `false` if one exists.
`Build` instantiates it.
"""
function create_project!(dir::AbstractString = project_dir(); name::AbstractString = package_name())
    toml = project_toml(dir)
    isfile(toml) && return false
    write(toml, project_toml_text(name, uuid4(), godot_source(dir), something(pkgversion(Godot), v"0.1.0")))
    Base.ACTIVE_PROJECT[] = toml
    log!("Created $(toml) for package $(name). Build to instantiate it.")
    return true
end

"Create the project when the first Julia script is created."
ensure_project!() = (has_project() || create_project!(); nothing)
