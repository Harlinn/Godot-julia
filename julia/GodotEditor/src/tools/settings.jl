# Editor and project settings of the Julia tools (C#: GodotTools `dotnet/*` settings in GodotSharpEditor.cs).

const S_PACKAGE_NAME = "julia/project/package_name"
const S_EXTERNAL_EDITOR = "julia/editor/external_editor"
const S_EXEC_PATH = "julia/editor/custom_exec_path"
const S_EXEC_ARGS = "julia/editor/custom_exec_path_args"
const S_VERBOSITY = "julia/build/verbosity"
const S_BUILD_ON_PLAY = "julia/build/build_on_play"

@enum ExternalEditor EDITOR_NONE EDITOR_VSCODE EDITOR_VSCODIUM EDITOR_EMACS EDITOR_VIM EDITOR_CUSTOM
const EXTERNAL_EDITOR_NAMES = "None,VS Code,VSCodium,Emacs,Vim/Neovim,Custom"

@enum BuildVerbosity VERBOSITY_QUIET VERBOSITY_NORMAL VERBOSITY_DETAILED
const VERBOSITY_NAMES = "Quiet,Normal,Detailed"

const VT_BOOL, VT_INT, VT_STRING = 1, 2, 4
const HINT_ENUM, HINT_GLOBAL_FILE = 2, 15

property_info(name, type, hint = 0, hint_string = "") =
    Dict{String, Any}("name" => name, "type" => type, "hint" => hint, "hint_string" => hint_string)

editor_settings() = Godot.get_editor_settings(EditorInterface)

function define_editor_setting(name, default, type, hint = 0, hint_string = "")
    es = editor_settings()
    Godot.has_setting(es, name) || Godot.set_setting(es, name, default)
    Godot.set_initial_value(es, name, default, false)
    Godot.add_property_info(es, property_info(name, type, hint, hint_string))
    return nothing
end

function define_project_setting(name, default, type, hint = 0, hint_string = "")
    ps = Godot.ProjectSettings
    Godot.has_setting(ps, name) || Godot.set_setting(ps, name, default)
    Godot.set_initial_value(ps, name, default)
    Godot.add_property_info(ps, property_info(name, type, hint, hint_string))
    return nothing
end

"Register the editor settings and the project settings owned by the editor tools (runtime ones come from the host)."
function define_settings!()
    define_project_setting(S_PACKAGE_NAME, "", VT_STRING)
    define_editor_setting(S_EXTERNAL_EDITOR, Int(EDITOR_NONE), VT_INT, HINT_ENUM, EXTERNAL_EDITOR_NAMES)
    define_editor_setting(S_EXEC_PATH, "", VT_STRING, HINT_GLOBAL_FILE)
    define_editor_setting(S_EXEC_ARGS, "{file}", VT_STRING)
    define_editor_setting(S_VERBOSITY, Int(VERBOSITY_NORMAL), VT_INT, HINT_ENUM, VERBOSITY_NAMES)
    define_editor_setting(S_BUILD_ON_PLAY, false, VT_BOOL)
    return nothing
end

editor_setting(name, default) = (v = Godot.get_setting(editor_settings(), name); v === nothing ? default : v)

external_editor() = ExternalEditor(clamp(Int(editor_setting(S_EXTERNAL_EDITOR, 0)), 0, length(instances(ExternalEditor)) - 1))
build_verbosity() = BuildVerbosity(clamp(Int(editor_setting(S_VERBOSITY, 1)), 0, 2))
build_on_play() = editor_setting(S_BUILD_ON_PLAY, false) === true
