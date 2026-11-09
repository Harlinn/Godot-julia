# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Debugging support: script errors located at `res://` frames, Julia frames for Godot's backtraces and script debugger,
# break on error, and `Godot.@breakpoint`. Behavior ported from CSharpLanguage (modules/mono/csharp_script.cpp:
# debug_get_current_stack_info, debug_break, debug_get_error) and GodotSharp/Core/DebuggingUtils.cs
# (MIT, Godot contributors). Design: ADR 0013.

const PROJECT_DIR = Ref("")
const PACKAGES_DIRS = String[]

normslash(s) = replace(String(s), '\\' => '/')

function project_dir()
    if isempty(PROJECT_DIR[]) && FFI.INITIALIZED[]
        PROJECT_DIR[] = rstrip(normslash(Godot.globalize_path(Godot.ProjectSettings, "res://")), '/') * "/"
    end
    return PROJECT_DIR[]
end

"Directory holding Godot.jl (and its sibling packages), as given and resolved (junctions, symlinks); lowercase."
function packages_dirs()
    if isempty(PACKAGES_DIRS)
        d = dirname(dirname(dirname(pathof(Godot))))
        for p in unique([d, realpath(d)])
            push!(PACKAGES_DIRS, lowercase(rstrip(normslash(p), '/') * "/"))
        end
    end
    return PACKAGES_DIRS
end

"""
`res://` path of a source file inside the project, else the file itself. Scripts are evaluated with `res://` names,
which Julia's debug info returns as `.res:\\x.jl` on Windows.
"""
function res_path(file::AbstractString)
    f = normslash(file)
    m = match(r"^(?:\./?)?res:/+(.*)$", f)
    m === nothing || return "res://" * m.captures[1]
    p = project_dir()
    return !isempty(p) && startswith(lowercase(f), lowercase(p)) ? "res://" * f[ncodeunits(p)+1:end] : f
end

"Whether a frame runs code of the Godot package itself (its recorded file path depends on where it was compiled)."
function godot_frame(fr)
    mi = fr.linfo
    mi isa Core.CodeInstance && (mi = mi.def)
    m = mi isa Core.MethodInstance ? mi.def : mi
    mod = m isa Method ? m.module : m isa Module ? m : nothing
    return mod !== nothing && Base.moduleroot(mod) === Godot
end

"Frames of user code, innermost first: scripts, project files and user packages (not Base, stdlibs or Godot.jl)."
function user_frames(bt)
    frames = Base.StackTraces.StackFrame[]
    bt === nothing && return frames
    for fr in stacktrace(bt)
        fr.from_c && continue
        file = res_path(string(fr.file))
        if !startswith(file, "res://")
            (isempty(file) || file == "none" || startswith(file, ".") || occursin("/share/julia/", file) ||
             godot_frame(fr) || any(d -> startswith(lowercase(file), d), packages_dirs())) && continue
        end
        push!(frames, fr)
    end
    return frames
end

is_script_frame(fr) = startswith(res_path(string(fr.file)), "res://")

stack_info(frames) = Dict{String, Any}[Dict{String, Any}("file" => res_path(string(f.file)), "func" => string(f.func),
                                                         "line" => Int(f.line)) for f in frames]

"Julia's stack trace text with script paths shown as `res://` (Windows debug info has `.res:\\x.jl`)."
fix_res_paths(s::AbstractString) = replace(s, r"\.res:\\[^\s\]]*" => m -> res_path(m))

"""
    report_exception(err, bt; warning = false)

Report a Julia exception as a Godot script error: the source is the innermost `res://` frame (else the innermost user
frame), the message has the full Julia backtrace, and Godot's backtrace shows the user frames.
"""
function report_exception(err, bt; warning::Bool = false)
    try
        msg = fix_res_paths(sprint(showerror, err, bt))
        desc = first(split(sprint(showerror, err), '\n'))
        frames = user_frames(bt)
        i = findfirst(is_script_frame, frames)
        frame = i !== nothing ? frames[i] : isempty(frames) ? source_frame(bt) : frames[1]
        tls = task_local_storage()
        prev = get(tls, :gdjl_pending_bt, nothing)
        tls[:gdjl_pending_bt] = bt   # Godot asks for the Julia frames while reporting (debug_get_current_stack_info)
        try
            if frame === nothing
                host_report_script_error(warning, "julia", "", 0, desc, msg)
            else
                host_report_script_error(warning, string(frame.func), res_path(string(frame.file)), frame.line, desc, msg)
            end
        finally
            tls[:gdjl_pending_bt] = prev
        end
    catch inner
        Core.print(Core.stderr, "Godot-julia: failed to report a Julia exception: ", typeof(inner), "\n")
    end
    return nothing
end

"Report an exception that escaped user code (an engine callback, task, signal handler) and break into the debugger."
function report_unhandled(err, bt)
    report_exception(err, bt)
    try
        break_on_error(err, bt)
    catch inner
        Core.print(Core.stderr, "Godot-julia: debugger break failed: ", typeof(inner), "\n")
    end
    return nothing
end

"Bridge handler for `JuliaLanguage::_debug_get_current_stack_info` (any thread, for every error Godot reports)."
function debug_get_current_stack_info(::Ptr{Cvoid})
    tls = task_local_storage()
    get(tls, :gdjl_in_stack_info, false) && return Dict{String, Any}[]
    tls[:gdjl_in_stack_info] = true
    try
        bt = get(tls, :gdjl_pending_bt, nothing)
        return stack_info(user_frames(bt === nothing ? backtrace() : bt))
    finally
        tls[:gdjl_in_stack_info] = false
    end
end

# --- Breaking into Godot's script debugger (C#: CSharpLanguage::debug_break) ----------------------------------------

"What the script debugger shows while broken: error text, Julia frames, locals of frame 0, the receiving instance."
struct DebugState
    error::String
    frames::Vector{Base.StackTraces.StackFrame}
    locals::Vector{Pair{Symbol, Any}}
    instance::Any
end

const DEBUG_STATE = Ref{Union{Nothing, DebugState}}(nothing)

function setting(name::AbstractString, default)
    FFI.INITIALIZED[] || return default
    v = Godot.get_setting(Godot.ProjectSettings, name, default)
    return v === nothing ? default : v
end

engine_debugger_active() = FFI.INITIALIZED[] && Godot.on_main_thread() && LANGUAGE_PTR[] != C_NULL &&
                           Godot.is_active(Godot.EngineDebugger)

"Enter Godot's script debugger (blocks while the user inspects frames; Continue resumes). Returns whether it broke."
function godot_debug_break(state::DebugState, is_error::Bool)
    DEBUG_STATE[] === nothing || return false
    DEBUG_STATE[] = state
    try
        Godot.script_debug(Godot.EngineDebugger, Godot.wrap_object(LANGUAGE_PTR[], false), true, is_error)
    finally
        DEBUG_STATE[] = nothing
    end
    return true
end

function break_on_error(err, bt)
    setting("julia/debugger/break_on_error", true) === true || return false
    engine_debugger_active() || return false
    frames = user_frames(bt)
    isempty(frames) && return false
    return godot_debug_break(DebugState(sprint(showerror, err), frames, Pair{Symbol, Any}[], nothing), true)
end

"""
    hit_breakpoint(locals, bt, message)

Target of `Godot.@breakpoint`: break into Godot's debugger (game run from the editor), else into a connected debug REPL
client (`julia/debugger/port`); does nothing without a debugger, like GDScript's `breakpoint`.
"""
function hit_breakpoint(locals::AbstractDict, bt, message::AbstractString)
    pairs_ = Pair{Symbol, Any}[Symbol(k) => v for (k, v) in locals]
    self = get(locals, :self, nothing)
    state = DebugState(String(message), user_frames(bt), pairs_, self isa GodotObject ? self : nothing)
    engine_debugger_active() && return godot_debug_break(state, false)
    has_debug_client() && return debug_server_break(state)
    return false
end

# --- Script debugger queries (JuliaLanguage::_debug_*) --------------------------------------------------------------

function level_frame(level::Integer)
    s = DEBUG_STATE[]
    s === nothing && return nothing
    return 0 <= level < length(s.frames) ? s.frames[level+1] : nothing
end

"A value the debugger can display: Variant-compatible values as they are, anything else as its `repr`."
debug_value(x) = x === nothing || x isa Union{Bool, Integer, AbstractFloat, AbstractString, Symbol, GodotObject} ||
                 Godot.isvarianttype(typeof(x)) ? x : sprint(show, x; context = :limit => true)

debug_get_error(::Ptr{Cvoid}) = (s = DEBUG_STATE[]; s === nothing ? "" : s.error)
debug_get_stack_level_count(::Ptr{Cvoid}) = (s = DEBUG_STATE[]; s === nothing ? 0 : length(s.frames))
debug_get_stack_level_line(::Ptr{Cvoid}, level) = (f = level_frame(level); f === nothing ? -1 : Int(f.line))
debug_get_stack_level_function(::Ptr{Cvoid}, level) = (f = level_frame(level); f === nothing ? "" : string(f.func))
debug_get_stack_level_source(::Ptr{Cvoid}, level) = (f = level_frame(level); f === nothing ? "" : res_path(string(f.file)))

function named_values(key::String, pairs_)
    return Dict{String, Any}(key => String[string(k) for (k, _) in pairs_], "values" => Any[debug_value(v) for (_, v) in pairs_])
end

function debug_get_stack_level_locals(::Ptr{Cvoid}, level, ::Integer, ::Integer)
    s = DEBUG_STATE[]
    return named_values("locals", s === nothing || level != 0 ? Pair{Symbol, Any}[] : s.locals)
end

function instance_fields(obj)
    obj === nothing && return Pair{Symbol, Any}[]
    T = typeof(obj)
    return Pair{Symbol, Any}[fieldname(T, i) => getfield(obj, i) for i in 1:fieldcount(T)
                             if fieldname(T, i) !== :__ptr && isdefined(obj, i)]
end

debug_get_stack_level_members(::Ptr{Cvoid}, level, ::Integer, ::Integer) =
    named_values("members", (s = DEBUG_STATE[]; s === nothing ? Pair{Symbol, Any}[] : instance_fields(s.instance)))

function debug_get_globals(::Ptr{Cvoid}, ::Integer, ::Integer)
    s = DEBUG_STATE[]
    mod = s === nothing || s.instance === nothing ? nothing : parentmodule(typeof(s.instance))
    mod === nothing && return named_values("globals", Pair{Symbol, Any}[])
    names_ = [n for n in names(mod; all = true) if isdefined(mod, n) && !startswith(string(n), "#") &&
              !(getglobal(mod, n) isa Union{Function, Module, Type})]
    return named_values("globals", Pair{Symbol, Any}[n => getglobal(mod, n) for n in names_])
end

"Evaluate `code` with the frame-0 locals bound (in the instance's script module, else `Main`); returns `repr`."
function eval_in_state(state::Union{Nothing, DebugState}, code::AbstractString)
    mod = state === nothing || state.instance === nothing ? Main : parentmodule(typeof(state.instance))
    parsed = Meta.parseall(code)
    ex = Meta.isexpr(parsed, :toplevel) ? Expr(:block, parsed.args...) : parsed
    locals = state === nothing ? Pair{Symbol, Any}[] : state.locals
    body = isempty(locals) ? ex : Expr(:let, Expr(:block, (Expr(:(=), k, QuoteNode(v)) for (k, v) in locals)...), ex)
    return Core.eval(mod, body)
end

function debug_parse_stack_level_expression(::Ptr{Cvoid}, level, expr::AbstractString, ::Integer, ::Integer)
    return try
        sprint(show, eval_in_state(DEBUG_STATE[], expr); context = :limit => true)
    catch e
        sprint(showerror, e)
    end
end
