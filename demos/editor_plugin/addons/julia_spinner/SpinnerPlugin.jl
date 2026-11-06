using Godot

# An editor plugin written in Julia (C#: a [Tool] class deriving from EditorPlugin). It adds a dock with a button
# that inserts a Spinner into the edited scene.
@tool @godot_class mutable struct SpinnerPlugin <: Godot.Editor.EditorPlugin
    dock::Union{Nothing, Control} = nothing
    added::Int = 0
end

function Godot._enter_tree(self::SpinnerPlugin)
    dock = VBoxContainer()
    set_name(dock, "Julia Spinner")
    label = Label()
    label.text = "Spinners added: 0"
    set_name(label, "Count")
    button = Button()
    button.text = "Add Spinner to scene"
    set_name(button, "AddButton")
    connect(button, :pressed, () -> add_spinner!(self))
    add_child(dock, label)
    add_child(dock, button)
    self.dock = dock
    Godot.add_control_to_dock(self, Godot.Editor.EditorPlugin_DOCK_SLOT_RIGHT_UL, dock)
end

function Godot._exit_tree(self::SpinnerPlugin)
    dock = self.dock
    dock === nothing && return
    Godot.remove_control_from_docks(self, dock)
    queue_free(dock)
    self.dock = nothing
end

"Insert a Spinner into the edited scene (undoable edits are left out to keep the demo short)."
function add_spinner!(self::SpinnerPlugin)
    root = Godot.get_edited_scene_root(Godot.Editor.EditorInterface)
    root === nothing && return nothing
    spinner = Base.invokelatest(Godot.script_type("res://addons/julia_spinner/Spinner.jl"))
    set_name(spinner, "Spinner$(self.added + 1)")
    add_child(root, spinner)
    set_owner(spinner, root)
    self.added += 1
    get_node(Label, self.dock, "Count").text = "Spinners added: $(self.added)"
    return spinner
end
