# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Script authoring: `@godot_class`, its annotations and options, and `@rpc` (analog of a C# `partial class Player :
# Node2D` with Godot's attributes and source generators). Expansion targets live in runtime/scripts.jl.

# Engine callbacks a script can override that are not part of extension_api.json (Object's script virtuals).
for name in Runtime.OBJECT_VIRTUALS
    @eval function $name end
end

"""
    Godot._before_reload(self::T) / Godot._after_reload(self::T)

Hot-reload hooks of a script class (C#: `ISerializationListener.OnBeforeSerialize` / `OnAfterDeserialize`).
`_before_reload` runs on the old instance before its state is transferred to the reloaded script;
`_after_reload` runs on the new instance once fields, references and connected callables are re-targeted.
"""
function _before_reload end
"See [`_before_reload`](@ref): runs on the new instance after a hot reload (C#: `OnAfterDeserialize`)."
function _after_reload end

"`SignalName(T)`: named tuple of the signal names of script class `T` (C#: `T.SignalName.HealthChanged`)."
function SignalName end

"`PropertyName(T)`: named tuple of the property names of script class `T` (C#: `T.PropertyName`)."
function PropertyName end

"`MethodName(T)`: named tuple of the engine-callable method names of script class `T` (C#: `T.MethodName`)."
MethodName(T::Type{<:GodotObject}) = Runtime.method_name_table(T)

const diag = Runtime.diagnostic

"""
    @godot_class [tool] [global_class] [abstract] [icon = "res://icon.svg"] mutable struct Name <: Base
        @export_category("Movement")
        @export speed::Float64 = 300.0                     # [Export]
        @export_range (0, 100, 1; or_greater = true) hp::Int = 100
        @export_group("Visuals"; prefix = "visual_")
        @export visual_tint::Color = Color(1, 1, 1)
        @export_tool_button ("Reset", "Reload") reset = reset!   # [ExportToolButton], needs @tool
        cooldown::Float64 = 0.0                             # script variable
        target::Node                                        # engine objects default to `nothing`
        @signal health_changed(old::Int, new::Int)          # [Signal]; generates emit_/connect_ helpers
    end

Declare the class of a Julia script. A script file `Name.jl` defines exactly one class named after the file (like
C#), deriving from a Godot class or from another Julia script (`<: script_type("res://base.jl")` or a global class
name). `Name` becomes an abstract type to dispatch on; instances are a concrete struct with the declared fields.
Override engine callbacks by extending Godot's functions (`Godot._ready(self::Name)`); any other function of the
script module whose first argument is typed `self::Name` can be called by name from the engine, and functions taking
`::Type{Name}` are static methods. `Name()` creates the engine object with the script attached. Annotations with
arguments take them as a tuple separated by a space (`@export_range (0, 10) x::Int`). See docs/diagnostics.md for
the errors reported while a script loads.
"""
macro godot_class(args...)
    isempty(args) && diag("GDJL0001", "@godot_class expects a `mutable struct Name <: GodotClass ... end` definition")
    return esc(godot_class_expr(__module__, __source__, args[end], Any[args[1:end-1]...]))
end

"Positional and keyword arguments of an annotation: `(a, b; k = v)`, `a b k = v`, or a mix."
function annotation_args(raw, where_)
    pos = Any[]
    kws = Pair{Symbol, Any}[]
    function add(a)
        if a isa Expr && a.head === :tuple
            foreach(add, a.args)
        elseif a isa Expr && a.head === :parameters
            for x in a.args
                x isa Expr && x.head === :kw && x.args[1] isa Symbol ||
                    diag("GDJL0105", "$where_: invalid keyword argument `$x`")
                push!(kws, x.args[1] => x.args[2])
            end
        elseif a isa Expr && a.head in (:(=), :kw) && a.args[1] isa Symbol
            push!(kws, a.args[1] => a.args[2])
        else
            push!(pos, a)
        end
    end
    foreach(add, raw)
    return pos, kws
end

kwargs_expr(kws) = isempty(kws) ? :(NamedTuple()) :
                   :(NamedTuple{($(QuoteNode.(first.(kws))...),)}(($(last.(kws)...),)))

function parse_field_decl(x, class, line)
    x isa Symbol && return (x, :Any)
    x isa Expr && x.head === :(::) && length(x.args) == 2 && x.args[1] isa Symbol && return (x.args[1], x.args[2])
    diag("GDJL0006", "@godot_class $class (line $line): expected a field declaration, got `$x`; define methods outside the struct")
end

"`(name, type_expr, has_default, default_expr)` of a field declaration in a `@godot_class` body."
function parse_field(item, class, line, exported)
    if item isa Expr && item.head === :const
        exported && diag("GDJL0103", "@godot_class $class (line $line): an exported member cannot be const (read-only)")
        diag("GDJL0006", "@godot_class $class (line $line): const fields are not supported")
    end
    if item isa Expr && item.head === :(=)
        n, t = parse_field_decl(item.args[1], class, line)
        return (n, t, true, item.args[2])
    end
    n, t = parse_field_decl(item, class, line)
    return (n, t, false, nothing)
end

function signal_spec(ex, class, line)
    bad() = diag("GDJL0006", "@godot_class $class (line $line): expected `@signal name(arg::Type, ...)`, got `$ex`")
    name, args = ex isa Symbol ? (ex, Any[]) :
                 ex isa Expr && ex.head === :call && ex.args[1] isa Symbol ? (ex.args[1], ex.args[2:end]) : bad()
    pairs = map(args) do a
        a isa Symbol && return :($(QuoteNode(a)) => Any)
        a isa Expr && a.head === :(::) && length(a.args) == 2 && a.args[1] isa Symbol || bad()
        return :($(QuoteNode(a.args[1])) => $(a.args[2]))
    end
    return :($(GlobalRef(Runtime, :ScriptSignal))($(QuoteNode(name)), Pair{Symbol, Any}[$(pairs...)]))
end

const GROUP_ANNOTATIONS = Dict("@export_category" => :category, "@export_group" => :group, "@export_subgroup" => :subgroup)

function group_spec(kind::Symbol, margs, where_)
    pos, kws = annotation_args(margs, where_)
    length(pos) == 1 || diag("GDJL0105", "$where_: @export_$kind expects a name")
    prefix = ""
    for (k, v) in kws
        k === :prefix && kind !== :category || diag("GDJL0105", "$where_: unknown @export_$kind option `$k`")
        prefix = v
    end
    return :($(GlobalRef(Runtime, :ScriptGroup))($(QuoteNode(kind)), string($(pos[1])), string($prefix)))
end

function tool_button_spec(margs, where_, line)
    isempty(margs) && diag("GDJL0110", "$where_: expected `@export_tool_button (text[, icon]) name = function_name`")
    decl = margs[end]
    decl isa Expr && decl.head === :(=) && decl.args[1] isa Symbol && decl.args[2] isa Symbol ||
        diag("GDJL0110", "$where_: @export_tool_button must name a script function: `name = function_name`")
    pos, kws = annotation_args(margs[1:end-1], where_)
    1 <= length(pos) <= 2 && isempty(kws) || diag("GDJL0105", "$where_: @export_tool_button expects (text[, icon])")
    icon = length(pos) == 2 ? pos[2] : ""
    return :($(GlobalRef(Runtime, :ScriptToolButton))($(QuoteNode(decl.args[1])), string($(pos[1])), string($icon),
                                                      $(QuoteNode(decl.args[2])), $line))
end

function godot_class_expr(mod::Module, src::LineNumberNode, def, opts)
    def isa Expr && def.head === :struct || diag("GDJL0001", "@godot_class expects a `mutable struct` definition")
    def.args[1] === true ||
        diag("GDJL0001", "@godot_class requires a `mutable struct` (script instances are mutable, like C# classes)")
    head = def.args[2]
    head isa Expr && head.head === :<: ||
        diag("GDJL0401", "@godot_class: declare the base class, e.g. `mutable struct Player <: Node2D`")
    name, base = head.args
    name isa Symbol || diag("GDJL0402", "@godot_class: script classes must not be generic (got `$name`)")
    o = Runtime.parse_class_options(opts)
    line = src.line
    file = string(src.file)
    items = Any[]
    defaults = Any[]
    signals = Any[]
    for item in def.args[3].args
        item isa LineNumberNode && (line = item.line; continue)
        item isa String && continue   # docstring
        where_ = "@godot_class $name (line $line)"
        spec = nothing
        if item isa Expr && item.head === :macrocall
            m = String(Runtime.macro_basename(item.args[1]))
            margs = Any[a for a in item.args[2:end] if !(a isa LineNumberNode)]
            if m == "@signal" && length(margs) == 1
                push!(signals, signal_spec(margs[1], name, line))
                continue
            elseif haskey(GROUP_ANNOTATIONS, m)
                push!(items, group_spec(GROUP_ANNOTATIONS[m], margs, where_))
                continue
            elseif m == "@export_tool_button"
                push!(items, tool_button_spec(margs, where_, line))
                continue
            elseif m == "@export" || startswith(m, "@export_")
                kind = m == "@export" ? :export : Symbol(m[9:end])
                kind === :export || kind in Runtime.EXPORT_KINDS ||
                    diag("GDJL0005", "$where_: unknown export annotation `$m`")
                isempty(margs) && diag("GDJL0006", "$where_: `$m` must precede a field declaration")
                pos, kws = annotation_args(margs[1:end-1], where_)
                kind === :export && !(isempty(pos) && isempty(kws)) &&
                    diag("GDJL0105", "$where_: @export takes no arguments; use an @export_<hint> annotation")
                spec = :($(GlobalRef(Runtime, :ExportSpec))($(QuoteNode(kind)), ($(pos...),), $(kwargs_expr(kws))))
                item = margs[end]
            else
                diag("GDJL0005", "$where_: unsupported `$(item.args[1])` in the class body")
            end
        end
        fname, ftype, has_default, default = parse_field(item, name, line, spec !== nothing)
        push!(items, :($(GlobalRef(Runtime, :FieldDecl))($(QuoteNode(fname)), $ftype, $line, $has_default, $spec)))
        push!(defaults, has_default ? default : :($(GlobalRef(Runtime, :default_value))($ftype)))
    end
    base_expr = base isa Symbol ? :($(GlobalRef(Runtime, :resolve_base))($mod, $(QuoteNode(base)))) : base
    return quote
        abstract type $name <: $base_expr end
        $(GlobalRef(Runtime, :define_script_class!))($mod, $name, $(QuoteNode(name)), Any[$(items...)],
                                                     () -> $(Expr(:tuple, defaults...)), Any[$(signals...)],
                                                     $(o.tool), $(o.global_class), $(o.is_abstract), $(o.icon),
                                                     $line, $file)
        nothing
    end
end

function add_class_option(ex, opt)
    ex isa Expr && ex.head === :macrocall ||
        diag("GDJL0005", "expected `@godot_class mutable struct ...` after the class option macro")
    n = Runtime.macro_basename(ex.args[1])
    args = copy(ex.args)
    if n === Symbol("@godot_class")
        insert!(args, length(args), opt)
    elseif n in (Symbol("@tool"), Symbol("@global_class"), Symbol("@icon"))
        args[end] = add_class_option(args[end], opt)
    else
        diag("GDJL0005", "expected `@godot_class mutable struct ...` after the class option macro")
    end
    return Expr(:macrocall, args...)
end

"`@tool @godot_class ...`: the script also runs in the editor (C#: `[Tool]`). Same as the `tool` option."
macro tool(ex)
    return esc(add_class_option(ex, :tool))
end

"`@global_class @godot_class ...`: register the class by name in the editor (C#: `[GlobalClass]`)."
macro global_class(ex)
    return esc(add_class_option(ex, :global_class))
end

"""
    @breakpoint [message]

Pause here in Godot's script debugger with the Julia frames and local variables (GDScript's `breakpoint`), or in a
connected debug REPL client (`julia/debugger/port`, docs/debugging.md). Does nothing when no debugger is attached.
"""
macro breakpoint(message = "breakpoint")
    return esc(Expr(:call, GlobalRef(Runtime, :hit_breakpoint), Expr(:macrocall, GlobalRef(Base, Symbol("@locals")), __source__),
                    Expr(:call, GlobalRef(Base, :backtrace)), message))
end

"`Godot.has_feature(:windows)`: whether the running game has a feature tag (`OS.has_feature`)."
has_feature(tag::Union{Symbol, AbstractString}) = has_feature(OS, String(tag))

"""
    @feature(tag)

Whether the game has feature tag `tag` (`:windows`, `:pc`, `:mobile`, `:editor`, `:debug`, `:release`, custom tags).
In games exported with a system image the export preset's tags are compile-time constants, so the untaken branch of
`if Godot.@feature(:windows) ... end` is compiled out (C#: `#if GODOT_WINDOWS`); otherwise it is a runtime check.
"""
macro feature(tag)
    t = tag isa QuoteNode ? String(tag.value) : tag isa Union{String, Symbol} ? String(tag) :
        throw(ArgumentError("@feature expects a literal tag such as :windows"))
    b = Runtime.EXPORT_BUILD[]
    b === nothing || return t in b.features
    return :($(GlobalRef(Godot, :has_feature))($t))
end

"`@icon \"res://icon.svg\" @godot_class ...`: editor icon of the class (C#: `[Icon]`)."
macro icon(path, ex)
    path isa String || diag("GDJL0005", "@icon expects a string literal path")
    return esc(add_class_option(ex, Expr(:(=), :icon, path)))
end

"`(function_name, self_type_expr)` of a function definition whose first argument is typed."
function rpc_signature(def)
    bad() = diag("GDJL0501", "@rpc expects a function definition whose first argument is `self::ScriptClass`")
    def isa Expr && (def.head === :function || (def.head === :(=) && def.args[1] isa Expr)) || bad()
    sig = def.args[1]
    while sig isa Expr && sig.head in (:where, :(::))
        sig = sig.args[1]
    end
    sig isa Expr && sig.head === :call && sig.args[1] isa Symbol || bad()
    args = [a for a in sig.args[2:end] if !(a isa Expr && a.head === :parameters)]
    !isempty(args) && args[1] isa Expr && args[1].head === :(::) && length(args[1].args) == 2 || bad()
    return sig.args[1], args[1].args[2]
end

"""
    @rpc [mode] [sync] [transfer_mode] [channel] function name(self::T, args...) ... end

Make a script function callable over the network with `rpc(node, :name, args...)` / `rpc_id(node, peer, :name, ...)`
(C#: `[Rpc]`). `mode` is `:authority` (default), `:any_peer` or `:disabled`; `sync` is `:call_remote` (default) or
`:call_local`; `transfer_mode` is `:reliable` (default, as in C#), `:unreliable` or `:unreliable_ordered`; `channel`
is an integer (default 0), also accepted as `channel = n`.
"""
macro rpc(args...)
    isempty(args) && diag("GDJL0501", "@rpc expects a function definition")
    def = args[end]
    pos, kws = annotation_args(Any[args[1:end-1]...], "@rpc")
    mode, call_local, transfer, channel = :authority, false, :reliable, 0
    for p in pos
        s = p isa QuoteNode ? p.value : p
        if s isa Symbol && haskey(Runtime.RPC_MODES, s)
            mode = s
        elseif s === :call_local || s === :call_remote
            call_local = s === :call_local
        elseif s isa Symbol && haskey(Runtime.RPC_TRANSFER_MODES, s)
            transfer = s
        elseif s isa Integer
            channel = s
        else
            diag("GDJL0501", "@rpc: unknown argument `$p`")
        end
    end
    for (k, v) in kws
        k === :channel && v isa Integer || diag("GDJL0501", "@rpc: unknown option `$k = $v`")
        channel = v
    end
    fname, self_type = rpc_signature(def)
    return quote
        $(esc(def))
        $(GlobalRef(Runtime, :register_rpc!))($(esc(self_type)), $(QuoteNode(fname)), $(QuoteNode(mode)), $call_local,
                                              $(QuoteNode(transfer)), $channel)
        nothing
    end
end

const script_type = Runtime.script_type
