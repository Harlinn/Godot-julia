# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Script classes and script resources: `@godot_class` metadata, loading `.jl` files into per-generation modules, and
# the handlers behind JuliaScript / JuliaLanguage (native/src/julia_script.cpp).
# Behavior ported from modules/mono/csharp_script.cpp and GodotSharp/Core/Bridge/ScriptManagerBridge.cs
# (MIT, Godot contributors).

const JS = Base.JuliaSyntax

const USAGE_STORAGE = UInt32(2)
const USAGE_EDITOR = UInt32(4)
const USAGE_DEFAULT = USAGE_STORAGE | USAGE_EDITOR
const USAGE_GROUP = UInt32(64)
const USAGE_CATEGORY = UInt32(128)
const USAGE_SUBGROUP = UInt32(256)
const USAGE_SCRIPT_VARIABLE = UInt32(4096)
const USAGE_NIL_IS_VARIANT = UInt32(131072)
const HINT_NONE = UInt32(0)
const HINT_RESOURCE_TYPE = UInt32(17)
const HINT_NODE_TYPE = UInt32(34)
const METHOD_FLAG_NORMAL = 1
const METHOD_FLAG_STATIC = 32
const ERR_OK = 0
const ERR_COMPILATION_FAILED = 36
const ERR_PARSE_ERROR = 43

const VT_NIL = FFI.GDEXTENSION_VARIANT_TYPE_NIL
const VT_INT = FFI.GDEXTENSION_VARIANT_TYPE_INT
const VT_FLOAT = FFI.GDEXTENSION_VARIANT_TYPE_FLOAT
const VT_STRING = FFI.GDEXTENSION_VARIANT_TYPE_STRING
const VT_COLOR = FFI.GDEXTENSION_VARIANT_TYPE_COLOR
const VT_NODE_PATH = FFI.GDEXTENSION_VARIANT_TYPE_NODE_PATH
const VT_OBJECT = FFI.GDEXTENSION_VARIANT_TYPE_OBJECT
const VT_CALLABLE = FFI.GDEXTENSION_VARIANT_TYPE_CALLABLE
const VT_ARRAY = FFI.GDEXTENSION_VARIANT_TYPE_ARRAY
const VT_DICTIONARY = FFI.GDEXTENSION_VARIANT_TYPE_DICTIONARY

"`PROPERTY_HINT_<name>` as an integer."
hint_value(name::Symbol) = UInt32(Integer(getglobal(Godot, Symbol("PROPERTY_HINT_", name))))

"""
    ScriptDiagnostic(code, message)

Error in a script class definition, raised while the script loads (C#: source generator / analyzer diagnostics).
Codes `GDJLnnnn` mirror the C# `GDnnnn` codes; see docs/diagnostics.md.
"""
struct ScriptDiagnostic <: Exception
    code::String
    message::String
end
Base.showerror(io::IO, e::ScriptDiagnostic) = print(io, e.code, ": ", e.message)
diagnostic(code::AbstractString, msg::AbstractString) = throw(ScriptDiagnostic(String(code), String(msg)))

"""
A field of a script class (C#: a field or property). Fields with Variant-compatible types are Godot properties;
`hint`/`hint_string`/`usage` override the values derived from the type (export annotations).
"""
struct ScriptField
    name::Symbol
    type::Any
    exported::Bool
    line::Int
    has_default::Bool
    hint::Union{Nothing, UInt32}
    hint_string::Union{Nothing, String}
    usage::Union{Nothing, UInt32}
end

ScriptField(name, type, exported, line, has_default) = ScriptField(name, type, exported, line, has_default, nothing, nothing, nothing)

"Export annotation of a field (`@export_range (0, 100) x::Int`) with its arguments evaluated in the script module."
struct ExportSpec
    kind::Symbol
    args::Tuple
    kwargs::NamedTuple
end

"A field declaration produced by the `@godot_class` expansion."
struct FieldDecl
    name::Symbol
    type::Any
    line::Int
    has_default::Bool
    spec::Union{Nothing, ExportSpec}
end

"`@export_category`, `@export_group` or `@export_subgroup` (C#: `[ExportCategory]`, `[ExportGroup]`, `[ExportSubgroup]`)."
struct ScriptGroup
    kind::Symbol
    name::String
    prefix::String
end

"`@export_tool_button` (C#: `[ExportToolButton]`): an editor button calling script function `target` on the instance."
struct ScriptToolButton
    name::Symbol
    text::String
    icon::String
    target::Symbol
    line::Int
end

"A signal declared with `@signal` (C#: a `[Signal]` delegate)."
struct ScriptSignal
    name::Symbol
    args::Vector{Pair{Symbol, Any}}
end

"Methods callable by name on a script instance (resolved once per script generation)."
struct ScriptMethod
    f::Function
    methods::Vector{Method}
    virtual::Bool
    thunks::Dict{Int, Any}   # argc => compiled call thunk (`nothing` when overloads need dynamic dispatch)
end

ScriptMethod(f, methods, virtual) = ScriptMethod(f, methods, virtual, Dict{Int, Any}())

"Metadata of a `@godot_class` (analog of the type information CSharpScript keeps)."
mutable struct ScriptClassInfo
    const name::Symbol
    const type::Type                 # abstract type users dispatch on
    const instance_type::DataType    # concrete struct instances are
    const native_base::Symbol
    const native_type::Type          # abstract engine class type of `native_base`
    const base::Union{Nothing, ScriptClassInfo}
    const fields::Vector{ScriptField}  # stored fields, base-class fields first
    const layout::Vector{Any}          # own property-list entries in declaration order
    const defaults::Function           # () -> tuple of the values of this class's own fields
    const signals::Vector{ScriptSignal}
    const tool::Bool
    const global_class::Bool
    const is_abstract::Bool
    const icon::String
    const mod::Module
    const line::Int
    const file::String
    state::Any                         # ScriptState when the class was loaded from a script resource
    const methods::Dict{Symbol, Union{Nothing, ScriptMethod}}
    const methods_lock::ReentrantLock
    const generated::Set{Symbol}       # helper functions generated for the class (not engine methods)
    const rpc::Dict{Symbol, Dict{String, Any}}
end

Base.show(io::IO, info::ScriptClassInfo) = print(io, "ScriptClassInfo(", info.name, " <: ", info.native_base, ")")

"A JuliaScript resource, keyed by its engine object pointer."
mutable struct ScriptState
    const ptr::Ptr{Cvoid}
    path::String
    valid::Bool
    generation::Int
    mod::Union{Nothing, Module}
    info::Union{Nothing, ScriptClassInfo}
    base_script::Any                   # strong reference to the base script resource
    source::String                     # source of the last load attempt
    deps::Set{Ptr{Cvoid}}              # scripts this one inherits from or refers to with `script_type`
    const instances::Set{Ptr{Cvoid}}   # owners of live instances
    const placeholders::Set{Ptr{Cvoid}}
end

ScriptState(p::Ptr{Cvoid}) = ScriptState(p, "", false, 0, nothing, nothing, nothing, "", Set{Ptr{Cvoid}}(),
                                         Set{Ptr{Cvoid}}(), Set{Ptr{Cvoid}}())

const SCRIPT_CLASSES = IdDict{Any, ScriptClassInfo}()
const CLASSES_LOCK = ReentrantLock()
const SCRIPTS = Dict{Ptr{Cvoid}, ScriptState}()
const SCRIPTS_LOCK = ReentrantLock()
const PINNED_SCRIPTS = Any[]              # script resources kept loaded by `script_type`
const LANGUAGE_PTR = Ref{Ptr{Cvoid}}(C_NULL)
const GENERATION = Ref(0)
const EDITOR_HINT = Ref{Union{Nothing, Bool}}(nothing)

mutable struct LoadContext
    path::String
    classes::Vector{ScriptClassInfo}
    deps::Set{Ptr{Cvoid}}
    dep_paths::Vector{String}   # `res://` paths of the scripts in `deps` (recorded for exports)
end
LoadContext(path::String) = LoadContext(path, ScriptClassInfo[], Set{Ptr{Cvoid}}(), String[])
const LOAD_LOCK = ReentrantLock()
const LOAD_STACK = LoadContext[]

script_info(@nospecialize(T)) = @lock CLASSES_LOCK get(SCRIPT_CLASSES, T, nothing)
script_state(p::Ptr{Cvoid}) = @lock SCRIPTS_LOCK get!(() -> ScriptState(p), SCRIPTS, p)
find_state(p::Ptr{Cvoid}) = @lock SCRIPTS_LOCK get(SCRIPTS, p, nothing)
loaded_info(p::Ptr{Cvoid}) = (st = find_state(p); st === nothing ? nothing : st.info)

function editor_hint()
    h = EDITOR_HINT[]
    h === nothing || return h
    return EDITOR_HINT[] = Godot.is_editor_hint(Godot.Engine)
end

function class_chain(info::ScriptClassInfo)
    chain = ScriptClassInfo[]
    ci = info
    while ci !== nothing
        push!(chain, ci)
        ci = ci.base
    end
    return chain
end

own_fields(info::ScriptClassInfo) = view(info.fields, (info.base === nothing ? 0 : length(info.base.fields)) + 1:length(info.fields))
all_defaults(info::ScriptClassInfo) = info.base === nothing ? info.defaults() : (all_defaults(info.base)..., info.defaults()...)
script_path(info::ScriptClassInfo) = info.state === nothing ? info.file : info.state.path

# --- Defining classes (target of the @godot_class expansion) -------------------------------------------------------

"""
    default_value(T)

Initial value of a script field declared without one (C#/GDScript zero-initialize): `nothing` for engine objects
and `Any`, zero for numbers, empty strings and collections, otherwise `T()`.
"""
function default_value(@nospecialize(T))
    T === Any && return nothing
    T isa Type || error("field type $T needs an explicit default value")
    (T <: GodotObject || Nothing <: T) && return nothing
    T <: Number && return zero(T)
    T <: AbstractString && return convert(T, "")
    T === Symbol && return Symbol("")
    hasmethod(T, Tuple{}) && return T()
    error("a field of type $T needs an explicit default value")
end

"Resolve the base type named `name` in a script: a binding of `mod`, or a Julia global class (`@global_class`)."
function resolve_base(mod::Module, name::Symbol)
    isdefined(mod, name) && return getglobal(mod, name)
    path = global_class_path(name)
    path === nothing && throw(UndefVarError(name, mod))
    return script_type(path)
end

function global_class_path(name::Symbol)
    b = EXPORT_BUILD[]
    b === nothing || return get(b.global_classes, String(name), nothing)
    FFI.INITIALIZED[] || return nothing
    for d in Godot.get_global_class_list(Godot.ProjectSettings)
        String(d["class"]) == String(name) && return String(d["path"])
    end
    return nothing
end

"""
    script_type(path) -> Type

The class type defined by the Julia script at `path` (`res://...`), loading it if needed, for inheriting from
another script (`@godot_class mutable struct Boss <: script_type("res://enemy.jl")`) or dispatching on it. The
script stays loaded for the rest of the session.
"""
function script_type(path::AbstractString)
    path = String(path)
    in_load = islocked(LOAD_LOCK) && !isempty(LOAD_STACK)
    in_load && push!(LOAD_STACK[end].dep_paths, path)
    EXPORT_BUILD[] === nothing || return build_script!(path).info.type
    res = Godot.load(Godot.ResourceLoader, path)
    res === nothing && error("could not load script $path")
    in_load && push!(LOAD_STACK[end].deps, Internals.native_ptr(res))
    info = loaded_info(Internals.native_ptr(res))
    info === nothing && error("$path is not a valid Julia script")
    @lock SCRIPTS_LOCK any(r -> r === res, PINNED_SCRIPTS) || push!(PINNED_SCRIPTS, res)
    return info.type
end

"Engine class type a script type ultimately derives from."
function native_type_of(@nospecialize(T))
    while script_info(T) !== nothing
        T = supertype(T)
    end
    return T
end

const LAYER_HINTS = Dict(:flags_2d_render => :LAYERS_2D_RENDER, :flags_2d_physics => :LAYERS_2D_PHYSICS,
                         :flags_2d_navigation => :LAYERS_2D_NAVIGATION, :flags_3d_render => :LAYERS_3D_RENDER,
                         :flags_3d_physics => :LAYERS_3D_PHYSICS, :flags_3d_navigation => :LAYERS_3D_NAVIGATION,
                         :flags_avoidance => :LAYERS_AVOIDANCE)
const PATH_HINTS = Dict(:file => :FILE, :dir => :DIR, :global_file => :GLOBAL_FILE, :global_dir => :GLOBAL_DIR,
                        :save_file => :SAVE_FILE, :global_save_file => :GLOBAL_SAVE_FILE)
const RANGE_FLAGS = (:or_greater, :or_less, :exp, :radians_as_degrees, :degrees, :hide_slider, :prefer_slider)

"Annotation kinds accepted as `@export_<kind>` before a field (groups and tool buttons are handled separately)."
const EXPORT_KINDS = Set{Symbol}([:range, :enum, :flags, :multiline, :placeholder, :exp_easing, :color_no_alpha,
                                  :node_path, :storage, :custom, keys(LAYER_HINTS)..., keys(PATH_HINTS)...])

hint_number(x::Integer) = string(x)
hint_number(x::Real) = string(Float64(x))
hint_name(x::Type) = String(class_hint_name(x))
hint_name(x) = string(x)

"Godot's `min,max[,step][,flags...][,suffix:...]` range hint string (GDScript `@export_range`)."
function range_hint_string(args::Tuple, kwargs::NamedTuple, where_::String)
    nums = String[hint_number(x) for x in args if x isa Real]
    extra = String[String(x) for x in args if x isa Union{AbstractString, Symbol}]
    length(nums) + length(extra) == length(args) && 2 <= length(nums) <= 3 ||
        diagnostic("GDJL0105", "$where_: @export_range expects (min, max[, step]; flags...)")
    for (k, v) in pairs(kwargs)
        if k === :step && length(nums) == 2
            push!(nums, hint_number(v))
        elseif k === :suffix
            push!(extra, "suffix:" * String(v))
        elseif k in RANGE_FLAGS
            v === true && push!(extra, String(k))
        else
            diagnostic("GDJL0105", "$where_: unknown @export_range option `$k`")
        end
    end
    return join(vcat(nums, extra), ",")
end

"`(hint, hint_string, usage)` overrides for an export annotation on a property with type info `t`."
function export_hint(spec::ExportSpec, t, where_::String)
    k, a, kw = spec.kind, spec.args, spec.kwargs
    vt = t[1]
    need(types...) = vt in types || diagnostic("GDJL0106", "$where_: @export_$k does not apply to this type")
    k === :export && return (nothing, nothing, nothing)
    k === :storage && return (nothing, nothing, USAGE_STORAGE | USAGE_SCRIPT_VARIABLE)
    if k === :custom
        length(a) == 3 || diagnostic("GDJL0105", "$where_: @export_custom expects (hint, hint_string, usage)")
        return (UInt32(Integer(a[1])), String(a[2]), UInt32(Integer(a[3])) | USAGE_SCRIPT_VARIABLE)
    end
    if k === :range
        need(VT_INT, VT_FLOAT)
        return (hint_value(:RANGE), range_hint_string(a, kw, where_), nothing)
    end
    isempty(kw) || diagnostic("GDJL0105", "$where_: @export_$k takes no keyword options")
    k === :enum && (need(VT_INT, VT_STRING); return (hint_value(:ENUM), join(hint_name.(a), ","), nothing))
    k === :flags && (need(VT_INT); return (hint_value(:FLAGS), join(hint_name.(a), ","), nothing))
    haskey(LAYER_HINTS, k) && (need(VT_INT); return (hint_value(LAYER_HINTS[k]), "", nothing))
    haskey(PATH_HINTS, k) && (need(VT_STRING); return (hint_value(PATH_HINTS[k]), join(hint_name.(a), ","), nothing))
    k === :multiline && (need(VT_STRING); return (hint_value(:MULTILINE_TEXT), "", nothing))
    k === :placeholder && (need(VT_STRING); return (hint_value(:PLACEHOLDER_TEXT), join(hint_name.(a), ","), nothing))
    k === :exp_easing && (need(VT_FLOAT); return (hint_value(:EXP_EASING), join(hint_name.(a), ","), nothing))
    k === :color_no_alpha && (need(VT_COLOR); return (hint_value(:COLOR_NO_ALPHA), "", nothing))
    k === :node_path && (need(VT_NODE_PATH); return (hint_value(:NODE_PATH_VALID_TYPES), join(hint_name.(a), ","), nothing))
    diagnostic("GDJL0005", "$where_: unknown export annotation @export_$k")
end

"Element type of a container type that makes it non-Variant-compatible, if any."
function bad_element(@nospecialize(T))
    T isa DataType || return nothing
    if T <: GDArray || (T <: AbstractVector && !(T <: Godot.PackedArray))
        E = eltype(T)
        return property_type(E) === nothing ? E : nothing
    elseif T <: GDDictionary
        K, V = keytype(T), valtype(T)
        property_type(K) === nothing && return K
        property_type(V) === nothing && return V
    end
    return nothing
end

strip_nothing(@nospecialize(T)) = T isa Union ? (T.a === Nothing ? T.b : T.b === Nothing ? T.a : T) : T

function exports_node(@nospecialize(T))
    S = strip_nothing(T)
    S isa Type || return false
    S <: Godot.Node && return true
    S isa DataType && (S <: GDArray || S <: AbstractVector) && return exports_node(eltype(S))
    return false
end

function make_field(d::FieldDecl, class::Symbol, @nospecialize(N))
    T = !d.has_default && d.type isa Type && d.type <: GodotObject ? Union{Nothing, d.type} : d.type
    spec = d.spec
    spec === nothing && return ScriptField(d.name, T, false, d.line, d.has_default)
    where_ = "@godot_class $class (line $(d.line)): field $(d.name)::$(d.type)"
    t = property_type(T)
    if t === nothing
        E = bad_element(T)
        E === nothing && diagnostic("GDJL0102", "$where_: the type cannot be exported (not Variant-compatible)")
        diagnostic("GDJL0301", "$where_: the element type $E is not Variant-compatible")
    end
    exports_node(T) && !(N <: Godot.Node) &&
        diagnostic("GDJL0107", "$where_: classes not derived from Node cannot export Node members")
    hint, hs, usage = export_hint(spec, t, where_)
    return ScriptField(d.name, T, true, d.line, d.has_default, hint, hs, usage)
end

function check_signals(signals, class::Symbol)
    for s in signals, (n, T) in s.args
        T === Any || property_type(T) !== nothing ||
            diagnostic("GDJL0202", "@godot_class $class: parameter $n::$T of signal $(s.name) is not Variant-compatible")
    end
end

script_get_field(obj, s::Symbol, ret::Ptr{Cvoid}) = false
script_set_field!(obj, s::Symbol, raw::FFI.RawVariant) = false

"Generate type-stable property access for instances of `C` (C#: generated `Get/SetGodotClassPropertyValue`)."
function define_field_access!(C::DataType, fields::Vector{ScriptField})
    props = [QuoteNode(f.name) for f in fields if property_type(f.type) !== nothing]
    types = Any[f.type for f in fields if property_type(f.type) !== nothing]
    gets = [:(s === $n && (Internals.assign_variant_slot!(ret, getfield(obj, $n)); return true)) for n in props]
    sets = [:(s === $n && (setfield!(obj, $n, convert_arg($T, raw)); return true)) for (n, T) in zip(props, types)]
    Core.eval(@__MODULE__, :(function script_get_field(obj::$C, s::Symbol, ret::Ptr{Cvoid})
                                 $(gets...)
                                 return false
                             end))
    Core.eval(@__MODULE__, :(function script_set_field!(obj::$C, s::Symbol, raw::FFI.RawVariant)
                                 $(sets...)
                                 return false
                             end))
    return nothing
end

"Generate `emit_<signal>`/`connect_<signal>` helpers (C#: `EmitSignal<Name>` and the generated events)."
function define_signal_helpers!(mod::Module, @nospecialize(T), signals::Vector{ScriptSignal})
    names = Symbol[]
    for s in signals
        params = [U === Any ? n : :($n::$U) for (n, U) in s.args]
        emit, conn = Symbol("emit_", s.name), Symbol("connect_", s.name)
        Core.eval(mod, :($emit(self::$T, $(params...)) =
                             $(GlobalRef(Godot, :emit_signal))(self, $(QuoteNode(s.name)), $(first.(s.args)...))))
        Core.eval(mod, :($conn(self::$T, f; flags::Integer = 0) =
                             $(GlobalRef(Godot, :connect))(self, $(QuoteNode(s.name)), $(GlobalRef(Godot, :Callable))(f), flags)))
        push!(names, emit, conn)
    end
    return names
end

name_table(names) = (u = Tuple(unique(names)); NamedTuple{u}(u))

"Called by the `@godot_class` expansion: define the instance struct and register the class."
function define_script_class!(mod::Module, @nospecialize(T::Type), name::Symbol, items::Vector{Any}, defaults::Function,
                              signals::Vector{Any}, tool::Bool, global_class::Bool, is_abstract::Bool, icon::String,
                              line::Int, file::String)
    B = supertype(T)
    B <: GodotObject || diagnostic("GDJL0401", "@godot_class $name must derive from GodotObject or a derived class, not $B")
    base = script_info(B)
    N = base === nothing ? B : base.native_type
    native = base === nothing ? Godot.godot_class_name(B) : base.native_base
    own = ScriptField[]
    layout = Any[]
    for item in items
        if item isa FieldDecl
            f = make_field(item, name, N)
            push!(own, f)
            push!(layout, f)
        elseif item isa ScriptToolButton
            tool || diagnostic("GDJL0108", "@godot_class $name (line $(item.line)): @export_tool_button requires a @tool class")
            push!(layout, item)
        else
            push!(layout, item::ScriptGroup)
        end
    end
    sigs = ScriptSignal[s for s in signals]
    check_signals(sigs, name)
    all_fields = base === nothing ? own : vcat(base.fields, own)
    seen = Set{Symbol}()
    for n in vcat([f.name for f in all_fields], [b.name for ci in (base === nothing ? () : class_chain(base))
                                                 for b in ci.layout if b isa ScriptToolButton],
                  [b.name for b in layout if b isa ScriptToolButton])
        n in seen && diagnostic("GDJL0007", "@godot_class $name: member $n is declared more than once (including base classes)")
        n === :__ptr && diagnostic("GDJL0007", "@godot_class $name: the member name __ptr is reserved")
        push!(seen, n)
    end
    iname = Symbol(name, "#Instance")
    body = Expr(:block, :(__ptr::Ptr{Cvoid}), (Expr(:(::), f.name, f.type) for f in all_fields)...)
    C = Core.eval(mod, Expr(:block, Expr(:struct, true, Expr(:<:, iname, T), body), iname))::DataType
    Core.eval(mod, :($(GlobalRef(Godot, :godot_class_name))(::Type{<:$T}) = $(QuoteNode(native))))
    Core.eval(mod, :((::Type{$T})() = $(GlobalRef(@__MODULE__, :new_script_object))($T)))
    # Julia fields take precedence over inherited engine properties.
    Core.eval(mod, quote
        Base.@constprop :aggressive @inline function Base.getproperty(o::$C, s::Symbol)
            hasfield($C, s) && return getfield(o, s)
            return invoke(Base.getproperty, Tuple{$N, Symbol}, o, s)
        end
        Base.@constprop :aggressive @inline function Base.setproperty!(o::$C, s::Symbol, v)
            hasfield($C, s) && return setfield!(o, s, convert(fieldtype($C, s), v))
            return invoke(Base.setproperty!, Tuple{$N, Symbol, Any}, o, s, v)
        end
    end)
    define_field_access!(C, all_fields)
    generated = Set{Symbol}(define_signal_helpers!(mod, T, sigs))
    all_signals = vcat([s.name for ci in (base === nothing ? () : reverse(class_chain(base))) for s in ci.signals],
                       [s.name for s in sigs])
    Core.eval(mod, :($(GlobalRef(Godot, :SignalName))(::Type{<:$T}) = $(name_table(all_signals))))
    prop_names = vcat([f.name for f in all_fields],
                      [b.name for ci in (base === nothing ? () : class_chain(base)) for b in ci.layout if b isa ScriptToolButton],
                      [b.name for b in layout if b isa ScriptToolButton])
    Core.eval(mod, :($(GlobalRef(Godot, :PropertyName))(::Type{<:$T}) = $(name_table(prop_names))))
    info = ScriptClassInfo(name, T, C, native, N, base, all_fields, layout, defaults, sigs, tool, global_class,
                           is_abstract, icon, mod, line, file, nothing, Dict{Symbol, Union{Nothing, ScriptMethod}}(),
                           ReentrantLock(), generated, Dict{Symbol, Dict{String, Any}}())
    @lock CLASSES_LOCK SCRIPT_CLASSES[T] = info
    islocked(LOAD_LOCK) && !isempty(LOAD_STACK) && push!(LOAD_STACK[end].classes, info)
    return C
end

const RPC_MODES = Dict(:disabled => 0, :any_peer => 1, :authority => 2)
const RPC_TRANSFER_MODES = Dict(:unreliable => 0, :unreliable_ordered => 1, :reliable => 2)

"Called by `@rpc`: record the RPC configuration of script function `name` (C#: `[Rpc]`, feeds `_get_rpc_config`)."
function register_rpc!(@nospecialize(T), name::Symbol, mode::Symbol, call_local::Bool, transfer::Symbol, channel::Integer)
    info = T isa Type ? script_info(T) : nothing
    info === nothing && diagnostic("GDJL0501", "@rpc $name: the first argument must be typed with a @godot_class type, not $T")
    info.rpc[name] = Dict{String, Any}("rpc_mode" => RPC_MODES[mode], "call_local" => call_local,
                                       "transfer_mode" => RPC_TRANSFER_MODES[transfer], "channel" => Int(channel))
    return nothing
end

"Construct the instance struct for the engine object `owner` with the field initializers evaluated."
construct_instance(info::ScriptClassInfo, owner::Ptr{Cvoid}) = info.instance_type(owner, all_defaults(info)...)

"""
    new_script_object(T)

Create an engine object of `T`'s native base class with the script attached (what `Player()` does; C#: `new Player()`).
"""
function new_script_object(@nospecialize(T::Type))
    info = script_info(isabstracttype(T) ? T : supertype(T))
    info === nothing && throw(ArgumentError("$T is not a script class"))
    st = info.state
    st === nothing && error("$(info.name) was not loaded from a script resource; load it with Godot.script_type(path)")
    W = Internals.resolve_wrapper(info.native_base)
    obj = Internals.construct_object(W, info.native_base)
    p = getfield(obj, :__ptr)
    Godot.set_script(obj, Godot.wrap_object(st.ptr, false))
    w = Godot.wrap_object(p, false)
    w isa T || error("could not attach script $(script_path(info)) to a new $(info.native_base)")
    return w
end

# --- Loading -----------------------------------------------------------------------------------------------------

class_name_from_path(path::AbstractString) = splitext(basename(String(path)))[1]
normalize_class_name(s::AbstractString) = lowercase(replace(s, "_" => "", "-" => ""))
matches_file(name::Symbol, file_class::AbstractString) =
    String(name) == file_class || normalize_class_name(String(name)) == normalize_class_name(file_class)

function first_error(d::JS.ParseError)
    for diag in d.diagnostics
        diag.level === :error && return diag
    end
    return isempty(d.diagnostics) ? nothing : d.diagnostics[1]
end

function user_frame_line(path::String, bt)
    bt === nothing && return 0
    for frame in stacktrace(bt)
        string(frame.file) == path && return frame.line
    end
    return 0
end

"`(line, message)` describing an error raised while loading the script at `path`."
function script_error_location(path::String, @nospecialize(e), bt)
    while e isa LoadError && e.error isa LoadError
        e = e.error
    end
    if e isa LoadError
        inner = e.error
        if inner isa Meta.ParseError
            d = inner.detail
            if d isa JS.ParseError
                diag = first_error(d)
                if diag !== nothing
                    return JS.source_location(d.source, JS.first_byte(diag))[1], "syntax error: " * diag.message
                end
            end
            return e.line, "syntax error: " * inner.msg
        end
        line = 0
        for (exc, ebt) in Base.current_exceptions()
            line = user_frame_line(path, ebt)
            line > 0 && break
        end
        return line > 0 ? line : e.line, sprint(showerror, inner)
    end
    return user_frame_line(path, bt), sprint(showerror, e)
end

function report_script_error(path::String, line::Integer, msg::AbstractString)
    host_report_script_error(false, "load_script", path, Int(line), msg, "$path:$line: $msg")
    return nothing
end

"Julia global classes of the project by name (the export build's table while building an export)."
function julia_global_classes()
    b = EXPORT_BUILD[]
    b === nothing || return b.global_classes
    FFI.INITIALIZED[] || return Dict{String, String}()
    classes = Dict{String, String}()
    for d in Godot.get_global_class_list(Godot.ProjectSettings)
        String(d["language"]) == "Julia" && (classes[String(d["class"])] = String(d["path"]))
    end
    return classes
end

"""
Bind the Julia global classes that `source` mentions in `mod`, so scripts can use them as types anywhere (field
types, method signatures), as C# code can name any [GlobalClass]. Scripts being loaded (cycles) are skipped.
"""
function bind_global_classes!(mod::Module, path::String, source::String)
    own = class_name_from_path(path)
    loading = Set(c.path for c in LOAD_STACK)
    for (name, cpath) in julia_global_classes()
        (name == own || cpath == path || cpath in loading) && continue
        occursin(Regex("\\b" * name * "\\b"), source) || continue
        T = try
            script_type(cpath)
        catch
            continue   # the script reports its own errors; this one fails later with UndefVarError
        end
        Core.eval(mod, Expr(:const, Expr(:(=), Symbol(name), T)))
    end
    return nothing
end

"Evaluate `source` into a fresh module; returns `(module, context, error code, generation)` (errors are reported unless `report` is false)."
function eval_script(path::String, source::String; report::Bool = true)
    file_class = class_name_from_path(path)
    gen = (GENERATION[] += 1)
    mod = Module(Symbol("Script_", isempty(file_class) ? "anonymous" : file_class, "_", gen))
    Core.eval(mod, :(using Godot))
    Core.eval(mod, :(eval(x) = Core.eval($mod, x)))
    Core.eval(mod, :(include(p) = Base.include($mod, p)))
    ctx = LoadContext(path)
    push!(LOAD_STACK, ctx)
    err = ERR_OK
    try
        bind_global_classes!(mod, path, source)
        include_string(mod, source, path)
    catch e
        report || rethrow()
        line, msg = script_error_location(path, e, catch_backtrace())
        report_script_error(path, line, msg)
        err = e isa LoadError && e.error isa Meta.ParseError ? ERR_PARSE_ERROR : ERR_COMPILATION_FAILED
    finally
        pop!(LOAD_STACK)
    end
    return mod, ctx, err, gen
end

"The class named after the file among `classes`, or `(nothing, line, message)` describing GDJL0003/GDJL0004."
function file_class_info(path::String, classes::Vector{ScriptClassInfo})
    file_class = class_name_from_path(path)
    found = filter(c -> matches_file(c.name, file_class), classes)
    length(found) == 1 && return found[1], 0, ""
    msg = isempty(found) ? "GDJL0004: the script must define a @godot_class named $file_class (after its file name)" :
          "GDJL0003: the script defines more than one @godot_class named $file_class"
    return nothing, isempty(classes) ? 1 : classes[1].line, msg
end

"""
Load the class of script `st`: from the module compiled into an exported game's system image (the exported file is
an empty stub), else by evaluating `source` into a fresh module (one per generation).
"""
function load_script!(st::ScriptState, source::String)
    path = st.path
    @lock LOAD_LOCK begin
        pre = isempty(source) ? get(PRECOMPILED_SCRIPTS, path, nothing) : nothing
        if pre === nothing
            isempty(source) && (source = something(exported_source(path), source))
            mod, ctx, err, gen = eval_script(path, source)
            info = nothing
            if err == ERR_OK
                info, line, msg = file_class_info(path, ctx.classes)
                info === nothing && (report_script_error(path, line, msg); err = ERR_COMPILATION_FAILED)
            end
        else
            # Base classes and `script_type` targets are loaded as when the source runs.
            ctx = LoadContext(path)
            push!(LOAD_STACK, ctx)
            try
                foreach(script_type, pre.deps)
            finally
                pop!(LOAD_STACK)
            end
            mod, info, err, gen = pre.mod, pre.info, ERR_OK, (GENERATION[] += 1)
        end
        old = st.info
        old === nothing || old === info || (old.state = nothing)
        st.source = source
        st.mod = mod
        st.generation = gen
        st.info = info
        st.valid = info !== nothing
        st.base_script = nothing
        st.deps = ctx.deps
        if info !== nothing
            info.state = st
            base_state = info.base === nothing ? nothing : info.base.state
            base_state === nothing || (st.base_script = Godot.wrap_object(base_state.ptr, false); push!(st.deps, base_state.ptr))
        end
        update_placeholders!(st)
        return err
    end
end

"Drop the script references Julia holds (pinned scripts, base scripts) so the engine can free the resources."
function release_scripts!()
    pinned = @lock SCRIPTS_LOCK begin
        p = copy(PINNED_SCRIPTS)
        empty!(PINNED_SCRIPTS)
        for st in values(SCRIPTS)
            st.base_script = nothing
        end
        p
    end
    empty!(pinned)
    detach_instances!()
    return nothing
end

# --- Property and method metadata --------------------------------------------------------------------------------

"Godot property description (Godot's `PropertyInfo`)."
struct PropInfo
    type::Int32
    name::Symbol
    class_name::Symbol
    hint::UInt32
    hint_string::String
    usage::UInt32
end

PropInfo(name::Symbol, @nospecialize(T); usage::UInt32 = UInt32(0)) =
    let t = something(property_type(T), (VT_NIL, Symbol(""), HINT_NONE, "", USAGE_NIL_IS_VARIANT))
        PropInfo(Int32(t[1]), name, t[2], t[3], t[4], usage | t[5])
    end

prop_dict(p::PropInfo) = Dict{String, Any}("name" => String(p.name), "class_name" => p.class_name, "type" => Int(p.type),
                                           "hint" => Int(p.hint), "hint_string" => p.hint_string, "usage" => Int(p.usage))

function PropInfo(d::AbstractDict)
    get_(k, default) = (v = get(d, k, nothing); v === nothing ? default : v)
    return PropInfo(Int32(get_("type", 0)), Symbol(get_("name", "")), Symbol(get_("class_name", "")),
                    UInt32(get_("hint", 0)), String(get_("hint_string", "")), UInt32(get_("usage", USAGE_DEFAULT)))
end

"""
    property_type(T) -> Union{Nothing, Tuple}

`(variant_type, class_name, hint, hint_string, extra_usage)` for a script field of Julia type `T`, or `nothing` when
values of `T` cannot be stored in a Variant (such fields stay private to Julia).
"""
function property_type(@nospecialize(T))
    (T === Any || T === Godot.Variant) && return (VT_NIL, Symbol(""), HINT_NONE, "", USAGE_NIL_IS_VARIANT)
    if T isa Union
        T.a === Nothing && return property_type(T.b)
        T.b === Nothing && return property_type(T.a)
        return nothing
    end
    T isa Type || return nothing
    if T <: GodotObject
        cls = class_hint_name(T)
        hint = T <: Godot.Resource ? HINT_RESOURCE_TYPE : T <: Godot.Node ? HINT_NODE_TYPE : HINT_NONE
        return (VT_OBJECT, cls, hint, hint == HINT_NONE ? "" : String(cls), UInt32(0))
    end
    if T <: GDArray
        E = eltype(T)
        E === Any && return (VT_ARRAY, Symbol(""), HINT_NONE, "", UInt32(0))
        es = element_hint(E)
        return es === nothing ? nothing : (VT_ARRAY, Symbol(""), hint_value(:ARRAY_TYPE), es, UInt32(0))
    end
    if T <: GDDictionary
        K, V = keytype(T), valtype(T)
        K === Any && V === Any && return (VT_DICTIONARY, Symbol(""), HINT_NONE, "", UInt32(0))
        ks, vs = K === Any ? "Variant" : element_hint(K), V === Any ? "Variant" : element_hint(V)
        (ks === nothing || vs === nothing) && return nothing
        return (VT_DICTIONARY, Symbol(""), hint_value(:DICTIONARY_TYPE), "$ks;$vs", UInt32(0))
    end
    if T <: AbstractVector && !(T <: Godot.PackedArray)
        isconcretetype(T) || return nothing
        E = eltype(T)
        P = Godot.packed_for(E)
        P === nothing || return (Int32(Godot.typed_info(P)[1]), Symbol(""), HINT_NONE, "", UInt32(0))
        E === Any && return (VT_ARRAY, Symbol(""), HINT_NONE, "", UInt32(0))
        es = element_hint(E)
        return es === nothing ? nothing : (VT_ARRAY, Symbol(""), hint_value(:ARRAY_TYPE), es, UInt32(0))
    end
    T <: AbstractDict && return (VT_DICTIONARY, Symbol(""), HINT_NONE, "", UInt32(0))
    T <: GodotBitfield && return (VT_INT, Symbol(""), hint_value(:FLAGS), enum_hint_string(T), UInt32(0))
    T <: GodotEnum && return (VT_INT, Symbol(""), hint_value(:ENUM), enum_hint_string(T), UInt32(0))
    T <: Base.Enum && return (VT_INT, Symbol(""), hint_value(:ENUM), enum_hint_string(T), UInt32(0))
    Godot.isvarianttype(T) || return nothing
    vt, cls = try
        Godot.typed_info(T)
    catch
        return nothing
    end
    return (Int32(vt), cls, HINT_NONE, "", UInt32(0))
end

"Class name shown for an object type: the global class name of a `@global_class` script, else the engine class."
function class_hint_name(@nospecialize(T))
    S = T isa DataType && !isabstracttype(T) ? supertype(T) : T
    info = script_info(S)
    info !== nothing && info.global_class && return info.name
    return T <: GodotObject ? Godot.godot_class_name(T) : Symbol(T)
end

"Typed-container element description `type/hint:hint_string` (the format C# generates for `PROPERTY_HINT_ARRAY_TYPE`)."
function element_hint(@nospecialize(E))
    t = property_type(E)
    t === nothing && return nothing
    return "$(Int(t[1]))/$(Int(t[3])):$(t[4])"
end

enum_hint_string(T::Type{<:GodotEnum}) = join(("$(n):$(v)" for (n, v) in Internals.enum_values(T)), ",")
enum_hint_string(T::Type{<:Base.Enum}) = join(("$(x):$(Integer(x))" for x in instances(T)), ",")

"Property description of a field, or `nothing` if the field is not a Godot property."
function field_prop(f::ScriptField)
    t = property_type(f.type)
    t === nothing && return nothing
    usage = f.usage !== nothing ? f.usage : (f.exported ? USAGE_DEFAULT : UInt32(0)) | USAGE_SCRIPT_VARIABLE | t[5]
    return PropInfo(Int32(t[1]), f.name, t[2], something(f.hint, t[3]), something(f.hint_string, t[4]), usage)
end

function group_prop(g::ScriptGroup)
    usage = g.kind === :category ? USAGE_CATEGORY : g.kind === :subgroup ? USAGE_SUBGROUP : USAGE_GROUP
    return PropInfo(Int32(VT_NIL), Symbol(g.name), Symbol(""), HINT_NONE, g.prefix, usage)
end

tool_button_prop(b::ScriptToolButton) =
    PropInfo(Int32(VT_CALLABLE), b.name, Symbol(""), hint_value(:TOOL_BUTTON),
             isempty(b.icon) ? b.text : "$(b.text),$(b.icon)", USAGE_EDITOR)

function find_tool_button(info::ScriptClassInfo, name::Symbol)
    for ci in class_chain(info), b in ci.layout
        b isa ScriptToolButton && b.name === name && return (ci, b)
    end
    return nothing
end

function find_field(info::ScriptClassInfo, name::Symbol)
    for (i, f) in pairs(info.fields)
        f.name === name && return i
    end
    return 0
end

"Index of field `name` if it is exposed to Godot as a property, else 0."
property_index(info::ScriptClassInfo, name::Symbol) =
    (i = find_field(info, name); i != 0 && property_type(info.fields[i].type) !== nothing ? i : 0)

function category_prop(info::ScriptClassInfo)
    path = script_path(info)
    label = info.global_class || isempty(path) ? String(info.name) : basename(path)
    return PropInfo(Int32(VT_NIL), Symbol(label), Symbol(""), HINT_NONE, path, USAGE_CATEGORY)
end

"Script properties of `info` in declaration order (base classes first), each class preceded by its category when `categories`."
function script_props(info::ScriptClassInfo; categories::Bool = false)
    props = PropInfo[]
    for ci in reverse(class_chain(info))
        categories && push!(props, category_prop(ci))
        for item in ci.layout
            p = item isa ScriptField ? field_prop(item) : item isa ScriptGroup ? group_prop(item) : tool_button_prop(item)
            p === nothing || push!(props, p)
        end
    end
    return props
end

"Methods of `f` callable on instances of `C`: the first argument is declared as a supertype of `C` (not `Any`)."
function self_methods(f::Function, C::DataType)
    ms = Method[]
    for m in methods(f)
        params = Base.unwrap_unionall(m.sig).parameters
        length(params) >= 2 || continue
        P = params[2]
        P isa Type && P !== Any && C <: P || continue
        push!(ms, m)
    end
    return ms
end

"Script-overridable engine callbacks that are not part of extension_api.json (Object's script virtuals)."
const OBJECT_VIRTUALS = (:_init, :_notification, :_get, :_set, :_get_property_list, :_validate_property,
                         :_property_can_revert, :_property_get_revert, :_to_string)

function is_virtual_name(name::Symbol)
    startswith(String(name), "_") && isdefined(Godot, name) || return false
    f = getglobal(Godot, name)
    return f isa Function && parentmodule(f) === Godot
end

function lookup_methods(info::ScriptClassInfo, name::Symbol)
    C = info.instance_type
    if is_virtual_name(name)
        f = getglobal(Godot, name)
        ms = self_methods(f, C)
        return isempty(ms) ? nothing : ScriptMethod(f, ms, true)
    end
    for ci in class_chain(info)
        mod = ci.mod
        isdefined(mod, name) || continue
        any(c -> name in c.generated, class_chain(info)) && return nothing
        f = getglobal(mod, name)
        f isa Function && parentmodule(f) === mod || continue
        ms = self_methods(f, C)
        isempty(ms) || return ScriptMethod(f, ms, false)
    end
    return nothing
end

"Static script methods named `name` (functions whose first argument is `::Type{T}` for a class of the chain)."
function static_methods(info::ScriptClassInfo, name::Symbol)
    for ci in class_chain(info)
        mod = ci.mod
        isdefined(mod, name) || continue
        f = getglobal(mod, name)
        f isa Function && parentmodule(f) === mod || continue
        ms = Method[]
        for m in methods(f)
            params = Base.unwrap_unionall(m.sig).parameters
            length(params) >= 2 || continue
            P = params[2]
            P isa DataType && P <: Type && length(P.parameters) == 1 || continue
            X = P.parameters[1]
            X isa TypeVar && (X = X.ub)
            X isa Type && X !== Any && info.type <: X && script_info(X) !== nothing || continue
            push!(ms, m)
        end
        isempty(ms) || return ScriptMethod(f, ms, false)
    end
    return nothing
end

function script_static_names(info::ScriptClassInfo)
    found = Symbol[]
    for ci in class_chain(info), n in names(ci.mod; all = true)
        (startswith(String(n), "#") || n in found) && continue
        static_methods(info, n) === nothing || push!(found, n)
    end
    return found
end

function method_name_table(@nospecialize(T))
    info = script_info(T)
    info === nothing && throw(ArgumentError("$T is not a script class"))
    return name_table(vcat(script_method_names(info), script_static_names(info)))
end

"The methods named `name` callable on instances of `info` (cached per script generation), or `nothing`."
find_methods(info::ScriptClassInfo, name::Symbol) =
    @lock info.methods_lock get!(() -> lookup_methods(info, name), info.methods, name)

arity(m::Method) = m.nargs - 2
accepts(m::Method, argc::Integer) = m.isva ? argc >= arity(m) - 1 : argc == arity(m)

"Declared Julia types of the `argc` arguments after `self`."
function arg_types(m::Method, argc::Integer)
    params = Base.unwrap_unionall(m.sig).parameters
    types = Vector{Any}(undef, argc)
    for i in 1:argc
        j = min(i + 2, length(params))
        T = params[j]
        T isa Core.TypeofVararg && (T = isdefined(T, :T) ? T.T : Any)
        T isa TypeVar && (T = T.ub)
        types[i] = T
    end
    return types
end

function method_prop_info(name::Symbol, m::Method)
    argc = m.isva ? arity(m) - 1 : arity(m)
    names = Base.method_argnames(m)
    types = arg_types(m, argc)
    args = [PropInfo(i + 2 <= length(names) ? names[i + 2] : Symbol("arg", i), types[i]) for i in 1:argc]
    return (name, args, PropInfo(Symbol(""), Any))
end

method_dict(name::Symbol, args::Vector{PropInfo}, ret::PropInfo; flags::Integer = METHOD_FLAG_NORMAL) =
    Dict{String, Any}("name" => String(name), "args" => [prop_dict(a) for a in args], "default_args" => Any[],
                      "flags" => Int(flags), "id" => 0, "return" => prop_dict(ret))

method_dict(name::Symbol, m::Method) = method_dict(method_prop_info(name, m)...)

signal_props(s::ScriptSignal) = PropInfo[PropInfo(n, T) for (n, T) in s.args]
signal_dict(s::ScriptSignal) = method_dict(s.name, signal_props(s), PropInfo(Symbol(""), Nothing))

"Names of the methods callable by name on instances of `info` (script functions and engine-callback overrides)."
function script_method_names(info::ScriptClassInfo)
    found = Symbol[]
    C = info.instance_type
    for ci in class_chain(info), n in names(ci.mod; all = true)
        (startswith(String(n), "#") || n in found || !isdefined(ci.mod, n)) && continue
        f = getglobal(ci.mod, n)
        f isa Function && parentmodule(f) === ci.mod && !isempty(self_methods(f, C)) &&
            !any(c -> n in c.generated, class_chain(info)) && push!(found, n)
    end
    class = info.native_base
    candidates = Symbol[OBJECT_VIRTUALS...]
    while !isempty(String(class))
        for v in get(Internals.CLASS_VIRTUALS, class, Internals.VirtualInfo[])
            push!(candidates, v.name)
        end
        class = FFI.INITIALIZED[] ? Internals.parent_class(class) : Symbol("")
    end
    for n in candidates
        n in found || !is_virtual_name(n) || isempty(self_methods(getglobal(Godot, n), C)) || push!(found, n)
    end
    return found
end

# --- Placeholders (editor instances of non-tool scripts) -----------------------------------------------------------

function exported_defaults(info::ScriptClassInfo)
    props = PropInfo[]
    values = Dict{Symbol, Any}()
    defaults = try
        all_defaults(info)
    catch e
        report_exception(e, catch_backtrace())
        return props, values
    end
    for (i, f) in pairs(info.fields)
        f.exported || continue
        p = field_prop(f)
        p === nothing && continue
        push!(props, p)
        values[f.name] = defaults[i]
    end
    return props, values
end

function update_placeholders!(st::ScriptState)
    isempty(st.placeholders) && return nothing
    props, values = st.info === nothing ? (PropInfo[], Dict{Symbol, Any}()) : exported_defaults(st.info)
    a = Ref(Internals.new_array([prop_dict(p) for p in props]))
    d = Ref(Internals.new_dictionary(values))
    try
        GC.@preserve a d for ph in st.placeholders
            FFI.placeholder_script_instance_update(ph, a, d)
        end
    finally
        FFI.destroy!(a[])
        FFI.destroy!(d[])
    end
    return nothing
end

# --- Parse-only queries (no code is executed) ----------------------------------------------------------------------

macro_basename(x::Symbol) = x
macro_basename(x::GlobalRef) = x.name
macro_basename(x::Expr) = x.head === :. && x.args[end] isa QuoteNode ? x.args[end].value : Symbol("")
macro_basename(x) = Symbol("")

"`(tool, global_class, is_abstract, icon)` from `@godot_class` options (`tool`, `global_class`, `abstract`, `icon = path`)."
function parse_class_options(opts)
    tool = global_class = is_abstract = false
    icon = ""
    for o in opts
        if o === :tool
            tool = true
        elseif o === :global_class
            global_class = true
        elseif o === :abstract
            is_abstract = true
        elseif o isa Expr && o.head === :(=) && o.args[1] === :icon && o.args[2] isa String
            icon = o.args[2]
        else
            diagnostic("GDJL0005", "unknown @godot_class option `$o` (expected tool, global_class, abstract or icon = \"path\")")
        end
    end
    return (tool = tool, global_class = global_class, is_abstract = is_abstract, icon = icon)
end

"Name, base expression and options of the `@godot_class` in a top-level expression, or `nothing`."
function class_header(ex, opts = Any[])
    ex isa Expr && ex.head === :macrocall || return nothing
    n = macro_basename(ex.args[1])
    rest = Any[a for a in ex.args[2:end] if !(a isa LineNumberNode)]
    isempty(rest) && return nothing
    if n === Symbol("@godot_class")
        def = rest[end]
        def isa Expr && def.head === :struct || return nothing
        head = def.args[2]
        head isa Expr && head.head === :<: && head.args[1] isa Symbol || return nothing
        o = try
            parse_class_options(vcat(opts, rest[1:end-1]))
        catch
            return nothing
        end
        return (name = head.args[1]::Symbol, base = head.args[2], o...)
    elseif n === Symbol("@tool") || n === Symbol("@global_class")
        return class_header(rest[end], vcat(opts, Any[n === Symbol("@tool") ? :tool : :global_class]))
    elseif n === Symbol("@icon") && length(rest) == 2
        return class_header(rest[2], vcat(opts, Any[Expr(:(=), :icon, rest[1])]))
    end
    return nothing
end

function parse_header(source::AbstractString)
    ex = try
        Meta.parseall(source)
    catch
        return nothing
    end
    for a in ex.args
        h = class_header(a)
        h === nothing || return h
    end
    return nothing
end

read_source(path::AbstractString) = Godot.get_file_as_string(Godot.FileAccess, String(path))

"Godot base-type name for a class header: a native class, a global class, or the parent of a script base."
function base_type_name(base, depth::Int = 0)
    base isa Symbol && return String(base)
    base isa Expr && base.head === :. && base.args[end] isa QuoteNode && return String(base.args[end].value)
    if depth < 16 && base isa Expr && base.head === :call && macro_basename(base.args[1]) === :script_type &&
       length(base.args) == 2 && base.args[2] isa String
        h = parse_header(read_source(base.args[2]))
        h === nothing && return ""
        return h.global_class ? String(h.name) : base_type_name(h.base, depth + 1)
    end
    return ""
end

# --- JuliaLanguage handlers ----------------------------------------------------------------------------------------

language_init(self::Ptr{Cvoid}) = (LANGUAGE_PTR[] = self; register_reload_settings!(); start_debugging!(); nothing)
language_finish(::Ptr{Cvoid}) = release_scripts!()
language_frame(::Ptr{Cvoid}) = (Godot.pump_frame!(); retry_reloads!(); Internals.flush_releases!(); nothing)

function language_get_global_class_name(::Ptr{Cvoid}, path::String)
    h = parse_header(read_source(path))
    (h === nothing || !h.global_class) && return Dict{String, Any}()
    return Dict{String, Any}("name" => String(h.name), "base_type" => base_type_name(h.base), "icon_path" => h.icon,
                             "is_abstract" => h.is_abstract, "is_tool" => h.tool)
end

validation_error(line, column, msg, path) =
    Dict{String, Any}("line" => Int(line), "column" => Int(column), "message" => String(msg), "path" => path)

function function_name(ex)
    if ex isa Expr && (ex.head === :function || (ex.head === :(=) && ex.args[1] isa Expr && ex.args[1].head in (:call, :where)))
        sig = ex.args[1]
        while sig isa Expr && sig.head in (:where, :(::))
            sig = sig.args[1]
        end
        sig isa Expr && sig.head === :call || return nothing
        f = sig.args[1]
        f isa Symbol && return f
        f isa Expr && f.head === :. && f.args[end] isa QuoteNode && return f.args[end].value
    end
    return nothing
end

"Parse and lower `source` (macros are expanded, nothing runs) and report errors with line and column."
function language_validate(::Ptr{Cvoid}, source::String, path::String, validate_functions::Bool, ::Bool, ::Bool, ::Bool)
    errors = Dict{String, Any}[]
    functions = String[]
    ex = try
        JS.parseall(Expr, source; filename = path)
    catch e
        if e isa JS.ParseError
            for d in e.diagnostics
                d.level === :error || continue
                line, col = JS.source_location(e.source, JS.first_byte(d))
                push!(errors, validation_error(line, col, d.message, path))
            end
        else
            push!(errors, validation_error(1, 1, sprint(showerror, e), path))
        end
        nothing
    end
    if ex !== nothing
        mod = Module(:JuliaScriptValidation)
        Core.eval(mod, :(using Godot))
        line = 1
        for a in ex.args
            a isa LineNumberNode && (line = a.line; continue)
            name = function_name(a)
            validate_functions && name !== nothing && push!(functions, "$name:$line")
            lowered = try
                Meta.lower(mod, a)
            catch e
                push!(errors, validation_error(line, 1, sprint(showerror, e isa LoadError ? e.error : e), path))
                continue
            end
            if lowered isa Expr && lowered.head in (:error, :incomplete)
                push!(errors, validation_error(line, 1, string(lowered.args[1]), path))
            end
        end
    end
    return Dict{String, Any}("valid" => isempty(errors), "errors" => errors, "warnings" => Dict{String, Any}[],
                             "functions" => functions, "safe_lines" => Int32[])
end

const OBJECT_TEMPLATE = """
using Godot

@godot_class mutable struct _CLASS_ <: _BASE_
end
"""

const TOOL_TEMPLATE = """
using Godot

@tool @godot_class mutable struct _CLASS_ <: _BASE_
end
"""

const NODE_TEMPLATE = """
using Godot

@godot_class mutable struct _CLASS_ <: _BASE_
end

# Called when the node enters the scene tree for the first time.
function Godot._ready(self::_CLASS_)
end

# Called every frame. `delta` is the elapsed time since the previous frame.
function Godot._process(self::_CLASS_, delta::Float64)
end
"""

const EDITOR_PLUGIN_TEMPLATE = """
using Godot

@tool @godot_class mutable struct _CLASS_ <: _BASE_
end

function Godot._enter_tree(self::_CLASS_)
_TS_# Initialization of the plugin goes here.
end

function Godot._exit_tree(self::_CLASS_)
_TS_# Clean-up of the plugin goes here.
end
"""

const EDITOR_SCRIPT_TEMPLATE = """
using Godot

@tool @godot_class mutable struct _CLASS_ <: _BASE_
end

# Called when the script is executed (using File -> Run in Script Editor).
function Godot._run(self::_CLASS_)
end
"""

template_dict(inherit, name, description, content, id) =
    Dict{String, Any}("inherit" => inherit, "name" => name, "description" => description, "content" => content,
                      "id" => id, "origin" => 0)

# Mirrors the C# templates in modules/mono/editor/script_templates/ (Empty + Default per base class).
const BUILT_IN_TEMPLATES = Dict{Symbol, Vector{Dict{String, Any}}}(
    :Object => [template_dict("Object", "Empty", "Empty template suitable for all Objects", OBJECT_TEMPLATE, 0)],
    :Node => [template_dict("Node", "Default", "Base template for Node with default Godot callbacks", NODE_TEMPLATE, 1)],
    :Resource => [template_dict("Resource", "Empty", "Empty template for a custom Resource", OBJECT_TEMPLATE, 2)],
    :EditorPlugin => [template_dict("EditorPlugin", "Default", "Basic plugin template", EDITOR_PLUGIN_TEMPLATE, 3),
                      template_dict("EditorPlugin", "Empty", "Empty plugin template", TOOL_TEMPLATE, 4)],
    :EditorScript => [template_dict("EditorScript", "Default", "Basic editor script template", EDITOR_SCRIPT_TEMPLATE, 5),
                      template_dict("EditorScript", "Empty", "Empty editor script template", TOOL_TEMPLATE, 6)],
)

language_get_built_in_templates(::Ptr{Cvoid}, object::Symbol) = copy(get(BUILT_IN_TEMPLATES, object, Dict{String, Any}[]))

"Base-class expression for a template: a script path, an editor class (`Godot.Editor.X`), or a core class."
function template_base(base::AbstractString)
    (occursin("://", base) || endswith(base, ".jl")) && return "script_type(\"$base\")"
    s = Symbol(base)
    isdefined(Godot, s) && return String(base)
    editor = isdefined(Godot, :Editor) ? getglobal(Godot, :Editor) : nothing
    is_editor = editor === nothing ? startswith(base, "Editor") : isdefined(editor, s)
    return is_editor ? "Godot.Editor.$base" : String(base)
end

"Hook the editor tools set to bootstrap the Julia project when a script is created (C#: first script creates the .csproj)."
const SCRIPT_CREATED_HOOK = Ref{Any}(nothing)

function language_make_template(::Ptr{Cvoid}, template::String, class_name::String, base::String)
    hook = SCRIPT_CREATED_HOOK[]
    if hook !== nothing
        try
            Base.invokelatest(hook)
        catch e
            report_exception(e, catch_backtrace())
        end
    end
    name = isempty(class_name) ? "NewScript" : replace(class_name, r"[^A-Za-z0-9_]" => "")
    src = isempty(template) ? OBJECT_TEMPLATE : template
    return replace(src, "_BASE_" => template_base(base), "_CLASS_" => name, "_TS_" => "    ")
end

"Create Script dialog check: the class is named after the file, so the file name must be a Julia identifier."
function language_validate_path(::Ptr{Cvoid}, path::String)
    name = class_name_from_path(path)
    Base.isidentifier(name) || return "The file name must be a valid Julia identifier: the class is named after the file (\"$name\")."
    return ""
end

# Defaults until the editor tools (GodotEditor) replace them; games never open external editors.
language_overrides_external_editor(::Ptr{Cvoid}) = false
language_open_in_external_editor(::Ptr{Cvoid}, script, line, col) = 2   # ERR_UNAVAILABLE

function language_find_function(::Ptr{Cvoid}, func::String, code::String)
    name = Base.escape_string(func)
    re = Regex("^\\s*(function\\s+(Godot\\.)?" * name * "\\s*\\(|(Godot\\.)?" * name * "\\(.*\\)\\s*=[^=])")
    for (i, line) in enumerate(eachline(IOBuffer(code)))
        occursin(re, line) && return i
    end
    return -1
end

function language_make_function(::Ptr{Cvoid}, class_name::String, func::String, args)
    params = ["self::" * (isempty(class_name) ? "GodotObject" : class_name)]
    append!(params, [String(first(split(a, ':'))) for a in args])
    return "function $func($(join(params, ", ")))\nend\n"
end

# --- JuliaScript handlers ------------------------------------------------------------------------------------------

function script_reload(self::Ptr{Cvoid}, source::String, path::String, ::Bool)
    st = script_state(self)
    isempty(path) || (st.path = path)
    return reload_scripts!([st => source])[st]
end

function script_free(self::Ptr{Cvoid})
    st = @lock SCRIPTS_LOCK pop!(SCRIPTS, self, nothing)
    st === nothing && return nothing
    delete!(PENDING_RELOADS, self)
    st.info === nothing || (st.info.state = nothing)
    st.base_script = nothing
    return nothing
end

script_is_valid(self::Ptr{Cvoid}) = (st = find_state(self); st !== nothing && st.valid)
script_is_tool(self::Ptr{Cvoid}) = (info = loaded_info(self); info !== nothing && info.tool)
script_is_abstract(self::Ptr{Cvoid}) = (info = loaded_info(self); info !== nothing && info.is_abstract)
script_get_icon_path(self::Ptr{Cvoid}) = (info = loaded_info(self); info === nothing ? "" : info.icon)

function script_can_instantiate(self::Ptr{Cvoid})
    info = loaded_info(self)
    return info !== nothing && !info.is_abstract && (info.tool || !editor_hint())
end

script_get_base_script(self::Ptr{Cvoid}) = (st = find_state(self); st === nothing ? nothing : st.base_script)

function script_get_global_name(self::Ptr{Cvoid})
    info = loaded_info(self)
    return info !== nothing && info.global_class ? info.name : Symbol("")
end

script_get_instance_base_type(self::Ptr{Cvoid}) = (info = loaded_info(self); info === nothing ? Symbol("") : info.native_base)

function script_placeholder_create(self::Ptr{Cvoid}, owner::Int64)
    st = script_state(self)
    ph = FFI.placeholder_script_instance_create(LANGUAGE_PTR[], self, Ptr{Cvoid}(owner))
    push!(st.placeholders, ph)
    update_placeholders!(st)
    return Int64(UInt(ph))
end

function script_placeholder_erased(self::Ptr{Cvoid}, ph::Int64)
    st = find_state(self)
    st === nothing || delete!(st.placeholders, Ptr{Cvoid}(ph))
    return nothing
end

script_instance_has(self::Ptr{Cvoid}, owner::Int64) = (st = find_state(self); st !== nothing && Ptr{Cvoid}(owner) in st.instances)

function script_has_method(self::Ptr{Cvoid}, name::Symbol)
    info = loaded_info(self)
    return info !== nothing && find_methods(info, name) !== nothing
end

function script_get_method_argument_count(self::Ptr{Cvoid}, name::Symbol)
    info = loaded_info(self)
    sm = info === nothing ? nothing : find_methods(info, name)
    return sm === nothing ? nothing : arity(sm.methods[1])
end

function script_get_method_info(self::Ptr{Cvoid}, name::Symbol)
    info = loaded_info(self)
    sm = info === nothing ? nothing : find_methods(info, name)
    return sm === nothing ? Dict{String, Any}() : method_dict(name, sm.methods[1])
end

function script_get_method_list(self::Ptr{Cvoid})
    info = loaded_info(self)
    info === nothing && return Dict{String, Any}[]
    return vcat([method_dict(n, find_methods(info, n).methods[1]) for n in script_method_names(info)],
                [method_dict(method_prop_info(n, static_methods(info, n).methods[1])...; flags = METHOD_FLAG_STATIC)
                 for n in script_static_names(info)])
end

script_has_static_method(self::Ptr{Cvoid}, name::Symbol) =
    (info = loaded_info(self); info !== nothing && static_methods(info, name) !== nothing)

"Bridge handler for `JuliaScript.call_static(method, args...)`: call a static script method."
function script_call_static(self::Ptr{Cvoid}, name::Symbol, args)
    info = loaded_info(self)
    info === nothing && error("the script is not valid")
    sm = static_methods(info, name)
    sm === nothing && error("$(info.name) has no static method $name")
    xs = collect(Any, args)
    cands = filter(m -> accepts(m, length(xs)), sm.methods)
    isempty(cands) && error("static method $(info.name).$name does not take $(length(xs)) arguments")
    if length(cands) == 1
        types = arg_types(cands[1], length(xs))
        xs = Any[T === Any || x isa T ? x : convert(T, x) for (x, T) in zip(xs, types)]
    end
    return Base.invokelatest(sm.f, info.type, xs...)
end

function script_get_rpc_config(self::Ptr{Cvoid})
    info = loaded_info(self)
    config = Dict{String, Any}()
    info === nothing && return config
    for ci in reverse(class_chain(info)), (name, c) in ci.rpc
        config[String(name)] = c
    end
    return config
end

function script_has_signal(self::Ptr{Cvoid}, name::Symbol)
    info = loaded_info(self)
    info === nothing && return false
    return any(ci -> any(s -> s.name === name, ci.signals), class_chain(info))
end

function script_get_signal_list(self::Ptr{Cvoid})
    info = loaded_info(self)
    info === nothing && return Dict{String, Any}[]
    return [signal_dict(s) for ci in reverse(class_chain(info)) for s in ci.signals]
end

script_has_property_default(self::Ptr{Cvoid}, name::Symbol) =
    (info = loaded_info(self); info !== nothing && property_index(info, name) != 0)

function script_get_property_default(self::Ptr{Cvoid}, name::Symbol)
    info = loaded_info(self)
    info === nothing && return nothing
    i = property_index(info, name)
    return i == 0 ? nothing : all_defaults(info)[i]
end

script_update_exports(self::Ptr{Cvoid}) = (st = find_state(self); st === nothing || update_placeholders!(st); nothing)

function script_get_property_list(self::Ptr{Cvoid})
    info = loaded_info(self)
    return info === nothing ? Dict{String, Any}[] : [prop_dict(p) for p in script_props(info)]
end

function script_get_member_line(self::Ptr{Cvoid}, name::Symbol)
    info = loaded_info(self)
    info === nothing && return -1
    i = find_field(info, name)
    return i == 0 ? -1 : info.fields[i].line
end

function script_get_members(self::Ptr{Cvoid})
    info = loaded_info(self)
    info === nothing && return Symbol[]
    return vcat(Symbol[f.name for f in info.fields], Symbol[s.name for ci in class_chain(info) for s in ci.signals])
end
