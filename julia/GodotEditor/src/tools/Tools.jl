# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

"""
    GodotEditor.Tools

Julia editor tooling (analog of C#'s GodotTools): project bootstrap, the Build button and Julia panel, external
editors, package management, editor settings. Driven by the native `JuliaEditorPlugin`. Design: ADR 0012.
"""
module Tools

using Godot
using ..GodotEditor: EditorInterface, EditorDock, EditorDock_DOCK_SLOT_BOTTOM, EditorPlugin_CONTAINER_TOOLBAR,
                     EditorExportPlatform_EXPORT_MESSAGE_ERROR as EXPORT_MESSAGE_ERROR

include("settings.jl")
include("external.jl")
include("project.jl")
include("jobs.jl")
include("export.jl")
include("translation.jl")
include("panel.jl")
include("plugin.jl")

"Install the bridge handlers the native editor plugin and `JuliaLanguage` call."
function install!()
    merge!(Godot.Runtime.BRIDGE, Dict{Symbol, Function}(
        :editor_plugin_enter_tree => plugin_enter_tree,
        :editor_plugin_exit_tree => plugin_exit_tree,
        :editor_plugin_process => plugin_process,
        :editor_plugin_build => plugin_build,
        :overrides_external_editor => overrides_external_editor,
        :open_in_external_editor => open_in_external_editor,
        :export_begin => export_begin,
        :export_file => export_file,
        :export_end => export_end,
        :translation_parse_file => translation_parse_file,
    ))
    return nothing
end

end # module Tools
