# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Bridge handlers of the native JuliaEditorPlugin (native/src/julia_editor.cpp) and the Project → Tools → Julia menu
# (C#: GodotSharpEditor.cs).

mutable struct PluginState
    plugin::Any
    panel::Panel
    toolbar_button::Any
    menu::Any
    package_dialog::Any
    package_name::Any     # LineEdit of the package dialog
    package_action::String
end

const PLUGIN = Ref{Union{Nothing, PluginState}}(nothing)

@enum MenuItem MENU_CREATE_PROJECT MENU_BUILD MENU_ADD_PACKAGE MENU_REMOVE_PACKAGE MENU_UPDATE_PACKAGES MENU_PACKAGE_STATUS

function menu_action(id::Integer)
    item = MenuItem(id)
    if item == MENU_CREATE_PROJECT
        create_project!() || log!("$(project_toml()) already exists.")
    elseif item == MENU_BUILD
        build!()
    elseif item == MENU_ADD_PACKAGE || item == MENU_REMOVE_PACKAGE
        show_package_dialog(item == MENU_ADD_PACKAGE ? "add" : "rm")
    elseif item == MENU_UPDATE_PACKAGES
        pkg_job!("update")
    else
        pkg_job!("status")
    end
    return nothing
end

function make_menu()
    menu = Godot.PopupMenu()
    Godot.add_item(menu, "Create Julia Project", Int(MENU_CREATE_PROJECT))
    Godot.add_item(menu, "Build", Int(MENU_BUILD))
    Godot.add_separator(menu)
    Godot.add_item(menu, "Add Package...", Int(MENU_ADD_PACKAGE))
    Godot.add_item(menu, "Remove Package...", Int(MENU_REMOVE_PACKAGE))
    Godot.add_item(menu, "Update Packages", Int(MENU_UPDATE_PACKAGES))
    Godot.add_item(menu, "Package Status", Int(MENU_PACKAGE_STATUS))
    connect(menu, :id_pressed, id -> (menu_action(id); nothing))
    return menu
end

function make_package_dialog()
    dialog = Godot.ConfirmationDialog()
    Godot.set_title(dialog, "Julia Package")
    name = Godot.LineEdit()
    Godot.set_placeholder(name, "Package names, separated by spaces")
    Godot.add_child(dialog, name)
    connect(dialog, :confirmed, () -> begin
        s = PLUGIN[]
        s === nothing && return nothing
        names = split_args(Godot.get_text(s.package_name))
        isempty(names) || pkg_job!(s.package_action, names)
        nothing
    end)
    return dialog, name
end

function show_package_dialog(action::String)
    s = PLUGIN[]
    s === nothing && return nothing
    s.package_action = action
    Godot.set_title(s.package_dialog, action == "add" ? "Add Julia Package" : "Remove Julia Package")
    Godot.set_text(s.package_name, "")
    Godot.popup_centered(s.package_dialog, Godot.Vector2i(420, 100))
    return nothing
end

const UI_PENDING = Ref(false)

function plugin_enter_tree(self::Ptr{Cvoid})
    plugin = Godot.wrap_object(self, false)
    define_settings!()
    Godot.Runtime.SCRIPT_CREATED_HOOK[] = ensure_project!
    # Extension editor plugins enter the tree while EditorNode is still being built (no editor theme yet; docks
    # added then crash), so the UI is built from `_process` once the editor is ready.
    UI_PENDING[] = true
    Godot.set_process(plugin, true)
    return nothing
end

function editor_ready()
    base = Godot.get_base_control(EditorInterface)
    return base !== nothing && Godot.is_node_ready(base) && Godot.get_editor_theme(EditorInterface) !== nothing &&
           Godot.get_process_frames(Godot.Engine) > 1
end

function build_ui!(plugin)
    PLUGIN[] === nothing || return nothing
    panel = make_panel()
    Godot.add_dock(plugin, panel.dock)
    toolbar = button("Build", "Build the Julia project (instantiate, precompile, validate, reload)", () -> build!())
    Godot.add_control_to_container(plugin, EditorPlugin_CONTAINER_TOOLBAR, toolbar)
    menu = make_menu()
    Godot.add_tool_submenu_item(plugin, "Julia", menu)
    dialog, name = make_package_dialog()
    Godot.add_child(Godot.get_base_control(EditorInterface), dialog)
    PLUGIN[] = PluginState(plugin, panel, toolbar, menu, dialog, name, "add")
    Godot.call(plugin, :register_syntax_highlighter)
    return nothing
end

function plugin_exit_tree(self::Ptr{Cvoid})
    Godot.Runtime.SCRIPT_CREATED_HOOK[] = nothing
    UI_PENDING[] = false
    s = PLUGIN[]
    s === nothing && return nothing
    Godot.remove_dock(s.plugin, s.panel.dock)
    Godot.remove_control_from_container(s.plugin, EditorPlugin_CONTAINER_TOOLBAR, s.toolbar_button)
    Godot.remove_tool_menu_item(s.plugin, "Julia")
    foreach(Godot.queue_free, (s.panel.dock, s.toolbar_button, s.package_dialog))
    PANEL[] = nothing
    PLUGIN[] = nothing
    return nothing
end

function plugin_process(self::Ptr{Cvoid}, ::Real)
    if UI_PENDING[] && editor_ready()
        UI_PENDING[] = false
        build_ui!(Godot.wrap_object(self, false))
        busy() || Godot.set_process(PLUGIN[].plugin, false)
    end
    poll_job!()
    return nothing
end

"Before running the project (C#: `_Build` builds unless disabled). Returning false cancels Play."
function plugin_build(::Ptr{Cvoid})
    build_on_play() || return true
    build!()
    wait_jobs!()
    return last_build_ok() === true
end
