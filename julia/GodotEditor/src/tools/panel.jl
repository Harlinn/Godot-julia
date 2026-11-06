# The "Julia" bottom panel: build output and a problems list (C#: GodotTools/Build/MSBuildPanel.cs, BuildProblemsView.cs).

mutable struct Panel
    dock::Any       # EditorDock in the bottom slot (Godot 4.6+ replacement of bottom panels)
    root::Any
    problems::Any   # ItemList
    log::Any        # RichTextLabel
    status::Any     # Label
end

const PANEL = Ref{Union{Nothing, Panel}}(nothing)
const ERROR_COLOR = Godot.Color(1.0, 0.47, 0.42)
const WARNING_COLOR = Godot.Color(1.0, 0.87, 0.4)

function button(text, tooltip, on_pressed)
    b = Godot.Button()
    Godot.set_text(b, text)
    Godot.set_tooltip_text(b, tooltip)
    connect(b, :pressed, () -> (on_pressed(); nothing))
    return b
end

function make_panel()
    dock = EditorDock()
    Godot.set_title(dock, "Julia")
    Godot.set_layout_key(dock, "julia_build")
    Godot.set_default_slot(dock, EditorDock_DOCK_SLOT_BOTTOM)
    root = Godot.VBoxContainer()
    Godot.set_name(root, "Julia")
    Godot.add_child(dock, root)
    Godot.set_custom_minimum_size(root, Godot.Vector2(0, 200))
    bar = Godot.HBoxContainer()
    Godot.add_child(root, bar)
    Godot.add_child(bar, button("Build", "Instantiate and precompile the Julia environment, validate scripts, reload", () -> build!()))
    Godot.add_child(bar, button("Clear", "Clear the output and problems", clear_output!))
    Godot.add_child(bar, button("Copy Log", "Copy the build output to the clipboard",
                                () -> Godot.clipboard_set(Godot.DisplayServer, join(LOG, '\n'))))
    status = Godot.Label()
    Godot.add_child(bar, status)
    split = Godot.HSplitContainer()
    Godot.set_v_size_flags(split, Godot.Control_SIZE_EXPAND_FILL)
    Godot.add_child(root, split)
    problems = Godot.ItemList()
    Godot.set_custom_minimum_size(problems, Godot.Vector2(320, 0))
    Godot.set_h_size_flags(problems, Godot.Control_SIZE_EXPAND_FILL)
    connect(problems, :item_activated, i -> (open_problem(Int(i) + 1); nothing))
    Godot.add_child(split, problems)
    log = Godot.RichTextLabel()
    Godot.set_scroll_follow(log, true)
    Godot.set_selection_enabled(log, true)
    Godot.set_h_size_flags(log, Godot.Control_SIZE_EXPAND_FILL)
    Godot.add_child(split, log)
    panel = Panel(dock, root, problems, log, status)
    for line in LOG
        Godot.add_text(log, line * "\n")
    end
    foreach(p -> add_problem_item!(panel, p), PROBLEMS)
    PANEL[] = panel
    return panel
end

panel_log!(line) = (p = PANEL[]; p === nothing || Godot.add_text(p.log, line * "\n"); nothing)
panel_status!(s) = (p = PANEL[]; p === nothing || Godot.set_text(p.status, s); nothing)
panel_clear_problems!() = (p = PANEL[]; p === nothing || Godot.clear(p.problems); nothing)
panel_clear!() = (p = PANEL[]; p === nothing || (Godot.clear(p.problems); Godot.clear(p.log); Godot.set_text(p.status, "")); nothing)

function add_problem_item!(panel::Panel, p::Problem)
    where_ = isempty(p.file) ? "" : "$(p.file):$(p.line):$(p.col)  "
    idx = Godot.add_item(panel.problems, "$(where_)$(p.message)")
    Godot.set_item_tooltip(panel.problems, idx, "$(p.severity): $(p.message)")
    Godot.set_item_custom_fg_color(panel.problems, idx, p.severity === :error ? ERROR_COLOR : WARNING_COLOR)
    return nothing
end

panel_problem!(p::Problem) = (panel = PANEL[]; panel === nothing || add_problem_item!(panel, p); nothing)

"Open the script of problem `i` at its line (routes to the external editor when one is configured)."
function open_problem(i::Int)
    1 <= i <= length(PROBLEMS) || return nothing
    p = PROBLEMS[i]
    endswith(p.file, ".jl") || return nothing
    script = Godot.load(Godot.ResourceLoader, p.file)
    script isa Godot.Script || return nothing
    Godot.edit_script(EditorInterface, script, p.line, max(p.col, 1) - 1)
    return nothing
end
