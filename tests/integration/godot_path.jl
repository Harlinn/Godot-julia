# Locating the Godot editor binary for the test runners: GODOT, then .tools/godot/, then `godot` on PATH.

function find_godot(root::AbstractString)
    godot = get(ENV, "GODOT", "")
    isempty(godot) || return godot
    tools = joinpath(root, ".tools", "godot")
    if isdir(tools)
        for f in readdir(tools; join = true)
            occursin(r"^Godot_v.*(_console\.exe|\.x86_64|\.arm64|\.universal)$", basename(f)) && return f
        end
        app = joinpath(tools, "Godot.app", "Contents", "MacOS", "Godot")
        isfile(app) && return app
    end
    path = Sys.which("godot")
    path === nothing && error("Godot not found: set GODOT or put the editor binary in .tools/godot/")
    return path
end
