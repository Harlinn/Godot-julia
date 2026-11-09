# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# The "Julia" bottom panel: build output and a problems view (C#: GodotTools/Build/MSBuildPanel.cs, BuildProblemsView.cs).

mutable struct Panel
    dock::Any       # EditorDock in the bottom slot (Godot 4.6+ replacement of bottom panels)
    root::Any
    problems::Any   # Tree: problems, flat or grouped by file
    log::Any        # RichTextLabel
    status::Any     # Label
    errors_button::Any
    warnings_button::Any
    show_errors::Bool
    show_warnings::Bool
    search::String
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

function toggle(text, tooltip, pressed::Bool, on_toggled)
    b = Godot.Button()
    Godot.set_text(b, text)
    Godot.set_tooltip_text(b, tooltip)
    Godot.set_toggle_mode(b, true)
    Godot.set_pressed(b, pressed)
    connect(b, :toggled, on -> (on_toggled(on); nothing))
    return b
end

"Indices of the problems shown with the given severity filters and search text (case-insensitive, file or message)."
function visible_problems(problems::Vector{Problem}; errors::Bool = true, warnings::Bool = true, search::AbstractString = "")
    s = lowercase(strip(search))
    return [i for (i, p) in enumerate(problems)
            if (p.severity === :error ? errors : warnings) &&
               (isempty(s) || occursin(s, lowercase(p.file)) || occursin(s, lowercase(p.message)))]
end

"`file => indices` groups of the shown problems, in order of first appearance (problems without a file under \"\")."
function problem_groups(problems::Vector{Problem}, idxs::Vector{Int})
    groups = Pair{String, Vector{Int}}[]
    for i in idxs
        f = problems[i].file
        j = findfirst(g -> g.first == f, groups)
        j === nothing ? push!(groups, f => [i]) : push!(groups[j].second, i)
    end
    return groups
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
    left = Godot.VBoxContainer()
    Godot.set_custom_minimum_size(left, Godot.Vector2(320, 0))
    Godot.set_h_size_flags(left, Godot.Control_SIZE_EXPAND_FILL)
    Godot.add_child(split, left)
    filters = Godot.HBoxContainer()
    Godot.add_child(left, filters)
    errors_button = toggle("Errors", "Show errors", true, on -> (PANEL[].show_errors = on; refresh_problems!()))
    warnings_button = toggle("Warnings", "Show warnings", true, on -> (PANEL[].show_warnings = on; refresh_problems!()))
    Godot.add_child(filters, errors_button)
    Godot.add_child(filters, warnings_button)
    Godot.add_child(filters, toggle("Group by File", "Show problems grouped by file (julia/build/problems_layout)",
                                    problems_layout() == PROBLEMS_TREE,
                                    on -> (set_problems_layout!(on ? PROBLEMS_TREE : PROBLEMS_LIST); refresh_problems!())))
    search = Godot.LineEdit()
    Godot.set_placeholder(search, "Filter problems")
    Godot.set_clear_button_enabled(search, true)
    Godot.set_h_size_flags(search, Godot.Control_SIZE_EXPAND_FILL)
    connect(search, :text_changed, t -> (PANEL[].search = String(t); refresh_problems!(); nothing))
    Godot.add_child(filters, search)
    problems = Godot.Tree()
    Godot.set_hide_root(problems, true)
    Godot.set_v_size_flags(problems, Godot.Control_SIZE_EXPAND_FILL)
    connect(problems, :item_activated, () -> (activate_problem_item!(); nothing))
    Godot.add_child(left, problems)
    log = Godot.RichTextLabel()
    Godot.set_scroll_follow(log, true)
    Godot.set_selection_enabled(log, true)
    Godot.set_h_size_flags(log, Godot.Control_SIZE_EXPAND_FILL)
    Godot.add_child(split, log)
    panel = Panel(dock, root, problems, log, status, errors_button, warnings_button, true, true, "")
    for line in LOG
        Godot.add_text(log, line * "\n")
    end
    PANEL[] = panel
    refresh_problems!()
    return panel
end

panel_log!(line) = (p = PANEL[]; p === nothing || Godot.add_text(p.log, line * "\n"); nothing)
panel_status!(s) = (p = PANEL[]; p === nothing || Godot.set_text(p.status, s); nothing)
panel_clear_problems!() = refresh_problems!()
panel_clear!() = (p = PANEL[]; p === nothing || (Godot.clear(p.log); Godot.set_text(p.status, "")); refresh_problems!())
panel_problem!(::Problem) = refresh_problems!()

function add_problem_item!(tree, parent, i::Int, p::Problem; with_file::Bool = true)
    item = Godot.create_item(tree, parent)
    where_ = isempty(p.file) || !with_file ? (p.line > 0 ? "$(p.line):$(p.col)  " : "") : "$(p.file):$(p.line):$(p.col)  "
    Godot.set_text(item, 0, "$(where_)$(p.message)")
    Godot.set_tooltip_text(item, 0, "$(p.severity): $(p.message)")
    Godot.set_custom_color(item, 0, p.severity === :error ? ERROR_COLOR : WARNING_COLOR)
    Godot.set_metadata(item, 0, i)
    return item
end

"Rebuild the problems view from `PROBLEMS` with the panel's filters and the layout setting."
function refresh_problems!()
    panel = PANEL[]
    panel === nothing && return nothing
    nerr = count(p -> p.severity === :error, PROBLEMS)
    Godot.set_text(panel.errors_button, "Errors ($nerr)")
    Godot.set_text(panel.warnings_button, "Warnings ($(length(PROBLEMS) - nerr))")
    tree = panel.problems
    Godot.clear(tree)
    root = Godot.create_item(tree)
    idxs = visible_problems(PROBLEMS; errors = panel.show_errors, warnings = panel.show_warnings, search = panel.search)
    if problems_layout() == PROBLEMS_TREE
        for (file, is) in problem_groups(PROBLEMS, idxs)
            group = Godot.create_item(tree, root)
            Godot.set_text(group, 0, "$(isempty(file) ? "(no file)" : file) ($(length(is)))")
            Godot.set_metadata(group, 0, 0)
            foreach(i -> add_problem_item!(tree, group, i, PROBLEMS[i]; with_file = isempty(file)), is)
        end
    else
        foreach(i -> add_problem_item!(tree, root, i, PROBLEMS[i]), idxs)
    end
    return nothing
end

"Texts of the problem rows currently shown (file group rows excluded)."
function shown_problem_texts(panel::Panel)
    out = String[]
    stack = Any[Godot.get_root(panel.problems)]
    while !isempty(stack)
        item = pop!(stack)
        item === nothing && continue
        m = Godot.get_metadata(item, 0)
        m isa Integer && m > 0 && push!(out, String(Godot.get_text(item, 0)))
        append!(stack, reverse(collect(Godot.get_children(item))))
    end
    return out
end

function activate_problem_item!()
    panel = PANEL[]
    panel === nothing && return nothing
    item = Godot.get_selected(panel.problems)
    item === nothing && return nothing
    m = Godot.get_metadata(item, 0)
    m isa Integer && m > 0 && open_problem(Int(m))
    return nothing
end

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
