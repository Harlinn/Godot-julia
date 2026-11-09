# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Generates generated/classes.jl: the engine class API (analog of the GodotSharp/GodotSharpEditor glue).

function class_order(ctx::Context)
    order = String[]
    visit(name) = begin
        name in order && return
        parent = get(ctx.classes[name], "inherits", nothing)
        parent === nothing || visit(parent)
        push!(order, name)
    end
    foreach(visit, sort(collect(keys(ctx.classes))))
    return order
end

parent_ref(ctx, c) = haskey(c, "inherits") ? class_ref(ctx, c["inherits"]) : nothing

function class_doc(c)
    parts = String[]
    brief = get(c, "brief_description", "")
    isempty(brief) || push!(parts, bbcode_to_markdown(brief))
    desc = get(c, "description", "")
    isempty(desc) || push!(parts, bbcode_to_markdown(desc))
    return join(parts, "\n\n")
end

"Method names defined by `class` or any ancestor (used to validate property accessors)."
function inherited_methods(ctx::Context, class)
    names = Set{String}()
    while class !== nothing
        c = ctx.classes[class]
        foreach(m -> push!(names, m["name"]), get(c, "methods", []))
        class = get(c, "inherits", nothing)
    end
    return names
end

struct Param
    name::String
    spec::TypeSpec
    default::Union{String, Nothing}
end

function method_params(ctx::Context, class, m, fields)
    params = Param[]
    for a in get(m, "arguments", [])
        spec = type_spec(ctx, a["type"])
        spec === nothing && return nothing
        d = haskey(a, "default_value") ? julia_default(ctx, a["type"], a["default_value"], fields) : nothing
        if haskey(a, "default_value") && d === nothing
            push!(ctx.renames, "default dropped: $class.$(m["name"])($(a["name"]) = $(a["default_value"]))")
        end
        push!(params, Param(safe_arg(a["name"]), spec, d))
    end
    # Julia only allows trailing defaults: anything before a required parameter becomes required too.
    last_required = something(findlast(p -> p.default === nothing, params), 0)
    return [i <= last_required ? Param(p.name, p.spec, nothing) : p for (i, p) in enumerate(params)]
end

param_decl(p::Param) = "$(p.name)::$(p.spec.annot)" * (p.default === nothing ? "" : " = $(p.default)")

function method_doc(ctx, class, m, fname, sig)
    lines = ["    $sig", ""]
    desc = get(m, "description", "")
    isempty(desc) || push!(lines, bbcode_to_markdown(desc))
    get(m, "is_static", false) && push!(lines, "", "Static method of `$(type_name(class))`.")
    return docstring(lines)
end

"Engine methods that may block; they run in a GC-safe region so Julia threads can collect garbage meanwhile."
const BLOCKING_METHODS = Set(["WorkerThreadPool.wait_for_task_completion", "WorkerThreadPool.wait_for_group_task_completion",
                              "Thread.wait_to_finish", "Semaphore.wait", "Mutex.lock", "OS.delay_msec", "OS.delay_usec",
                              "OS.execute", "ResourceLoader.load_threaded_get"])

function emit_ptrcall_method(io::IO, ctx::Context, class, m, fields)
    name = m["name"]
    params = method_params(ctx, class, m, fields)
    ret_type = haskey(m, "return_value") ? m["return_value"]["type"] : nothing
    ret_spec = ret_type === nothing ? nothing : type_spec(ctx, ret_type)
    if params === nothing || (ret_type !== nothing && ret_spec === nothing)
        push!(ctx.skipped, "$class.$name (unsupported argument or return type)")
        return false
    end
    fname = method_function(ctx, name)
    is_static = get(m, "is_static", false)
    self_decl = is_static ? "::Type{$(class_ref(ctx, class))}" : "self::$(class_ref(ctx, class))"
    decls = join([self_decl; param_decl.(params)], ", ")
    sig = "$fname($decls)"
    print(io, method_doc(ctx, class, m, fname, sig))
    println(io, "function $sig")
    println(io, "    __mb = Internals.@method_bind($(repr(Symbol(class))), $(repr(Symbol(name))), $(m["hash"]))")
    owner = is_static ? "C_NULL" : "Internals.native_ptr(self)"
    args = String[]
    owned = Tuple{String, String}[]
    for (i, p) in enumerate(params)
        local_name = "__a$i"
        if p.spec.owned
            push!(owned, (local_name, subst(p.spec.arg, p.name)))
        else
            println(io, "    $local_name = $(subst(p.spec.arg, p.name))")
        end
        push!(args, local_name)
    end
    native_ret = ret_spec === nothing ? "Nothing" : ret_spec.native
    callf = "$class.$name" in BLOCKING_METHODS ? "FFI.ptrcall_gcsafe" : "FFI.ptrcall"
    call = "$callf($native_ret, __mb, $owner" * join((", " * a for a in args)) * ")"
    indent = "    "
    isempty(owned) || println(io, indent, "local __r")
    for (local_name, expr) in owned
        println(io, indent, "$local_name = $expr")
        println(io, indent, "try")
        indent *= "    "
    end
    println(io, indent, "__r = $call")
    for (local_name, _) in reverse(owned)
        indent = indent[1:(end - 4)]
        println(io, indent, "finally")
        println(io, indent, "    FFI.destroy!($local_name)")
        println(io, indent, "end")
    end
    println(io, "    return ", ret_spec === nothing ? "nothing" : subst(ret_spec.ret, "__r"))
    println(io, "end\n")
    return true
end

function emit_vararg_method(io::IO, ctx::Context, class, m, fields)
    name = m["name"]
    params = method_params(ctx, class, m, fields)
    if params === nothing
        push!(ctx.skipped, "$class.$name (unsupported argument type)")
        return false
    end
    fname = method_function(ctx, name)
    is_static = get(m, "is_static", false)
    self_decl = is_static ? "::Type{$(class_ref(ctx, class))}" : "self::$(class_ref(ctx, class))"
    decls = join([self_decl; param_decl.(params); "args..."], ", ")
    sig = "$fname($decls)"
    print(io, method_doc(ctx, class, m, fname, sig))
    owner = is_static ? "C_NULL" : "Internals.native_ptr(self)"
    fixed = join(("Internals.to_variant($(p.name)), " for p in params))
    ret_type = haskey(m, "return_value") ? m["return_value"]["type"] : nothing
    convert_ret = "__v"
    if ret_type !== nothing && (startswith(ret_type, "enum::") || startswith(ret_type, "bitfield::"))
        ref = enum_type_ref(ctx, ret_type)
        ref === nothing || (convert_ret = "$ref(__v)")
    end
    println(io, """
    function $sig
        __mb = Internals.@method_bind($(repr(Symbol(class))), $(repr(Symbol(name))), $(m["hash"]))
        __vs = FFI.RawVariant[$(fixed)(Internals.to_variant(a) for a in args)...]
        try
            __v = Internals.take_variant(FFI.variant_call(__mb, $owner, __vs))
            return $(ret_type === nothing ? "nothing" : convert_ret)
        finally
            foreach(FFI.destroy!, __vs)
        end
    end
    """)
    return true
end

function emit_properties(io::IO, ctx::Context, class)
    c = ctx.classes[class]
    available = inherited_methods(ctx, class)
    props = [p for p in get(c, "properties", []) if get(p, "getter", "") in available]
    isempty(props) && return
    T = class_ref(ctx, class)
    parent = parent_ref(ctx, c)
    call(accessor, extra) = method_function(ctx, accessor) * "(self" * extra * ")"
    idx(p) = haskey(p, "index") ? ", $(p["index"])" : ""
    println(io, "Base.@constprop :aggressive @inline function Base.getproperty(self::$T, s::Symbol)")
    for p in props
        println(io, "    s === $(repr(Symbol(p["name"]))) && return $(call(p["getter"], idx(p)))")
    end
    println(io, "    return invoke(Base.getproperty, Tuple{$parent, Symbol}, self, s)\nend")
    println(io, "Base.@constprop :aggressive @inline function Base.setproperty!(self::$T, s::Symbol, value)")
    for p in props
        setter = get(p, "setter", "")
        if !isempty(setter) && setter in available
            println(io, "    s === $(repr(Symbol(p["name"]))) && return ($(call(setter, idx(p) * ", value")); value)")
        else
            println(io, "    s === $(repr(Symbol(p["name"]))) && throw(Internals.ReadOnlyPropertyError($(repr(class)), s))")
        end
    end
    println(io, "    return invoke(Base.setproperty!, Tuple{$parent, Symbol, Any}, self, s, value)\nend")
    names = join((repr(Symbol(p["name"])) for p in props), ", ")
    println(io, "Internals.class_property_names(::Type{$T}) = ($names,)\n")
end

function signal_literal(ctx::Context, s)
    args = join(["$(repr(Symbol(safe_arg(a["name"])))) => $(repr(a["type"]))" for a in get(s, "arguments", [])], ", ")
    return "Internals.SignalInfo($(repr(Symbol(s["name"]))), Pair{Symbol, String}[$args])"
end

function virtual_literal(ctx::Context, m)
    args = join(["$(repr(Symbol(safe_arg(a["name"])))) => $(repr(a["type"]))" for a in get(m, "arguments", [])], ", ")
    ret = haskey(m, "return_value") ? repr(m["return_value"]["type"]) : "nothing"
    return "Internals.VirtualInfo($(repr(Symbol(m["name"]))), Pair{Symbol, String}[$args], $ret, " *
           "$(get(m, "hash", 0)), $(get(m, "is_const", false)), $(get(m, "is_required", false)))"
end

function emit_enums_and_constants(io::IO, ctx::Context, class)
    c = ctx.classes[class]
    T = type_name(class)
    for e in get(c, "enums", [])
        emit_enum(io, "$(T)_$(e["name"])", "$(T)_", e)
    end
    for k in get(c, "constants", [])
        desc = get(k, "description", "")
        isempty(desc) || print(io, docstring([bbcode_to_markdown(desc)]))
        println(io, "const $(T)_$(k["name"]) = $(k["value"])")
    end
end

enum_exports(ctx, class) = begin
    c = ctx.classes[class]
    T = type_name(class)
    vcat(["$(T)_$(e["name"])" for e in get(c, "enums", [])],
         ["$(T)_$(v["name"])" for e in get(c, "enums", []) for v in e["values"]],
         ["$(T)_$(k["name"])" for k in get(c, "constants", [])])
end

"Classes generated in `ctx.scope` (`:core` → module `Godot`, `:editor` → package `GodotEditor`), parents first."
scope_classes(ctx::Context) = [c for c in class_order(ctx) if is_editor(ctx, c) == (ctx.scope == :editor)]

function emit_type_declarations(io::IO, ctx::Context, classes)
    for class in classes
        class == "Object" && continue  # `GodotObject` is hand-written
        c = ctx.classes[class]
        doc = class_doc(c)
        isempty(doc) || print(io, docstring([doc]))
        println(io, "abstract type $(type_name(class)) <: $(parent_ref(ctx, c)) end")
    end
    owner = ctx.scope == :core ? "Godot" : "GodotEditor"
    println(io, "\nmodule Native\nimport ..$owner")
    for class in classes
        println(io, "mutable struct $(type_name(class)) <: $owner.$(type_name(class))\n    __ptr::Ptr{Cvoid}\nend")
    end
    println(io, "end # module Native\n")
    for class in classes
        emit_enums_and_constants(io, ctx, class)
    end
end

function emit_registries(io::IO, ctx::Context, classes)
    println(io, "const __CLASS_WRAPPERS = Dict{Symbol, DataType}(")
    for class in classes
        println(io, "    $(repr(Symbol(class))) => $(native_ref(ctx, class)),")
    end
    println(io, ")")
    println(io, "const __CLASS_SIGNALS = Dict{Symbol, Vector{Internals.SignalInfo}}(")
    for class in classes
        sigs = get(ctx.classes[class], "signals", [])
        isempty(sigs) && continue
        println(io, "    $(repr(Symbol(class))) => [$(join((signal_literal(ctx, s) for s in sigs), ", "))],")
    end
    println(io, ")")
    println(io, "const __CLASS_VIRTUALS = Dict{Symbol, Vector{Internals.VirtualInfo}}(")
    for class in classes
        vs = [m for m in get(ctx.classes[class], "methods", []) if get(m, "is_virtual", false)]
        isempty(vs) && continue
        println(io, "    $(repr(Symbol(class))) => [$(join((virtual_literal(ctx, m) for m in vs), ", "))],")
    end
    println(io, ")\n")
end

"Per-signal helper names (`connect_<signal>`, `disconnect_<signal>`) that do not clash with engine method names."
function signal_helper_names(api)
    methods = Set(m["name"] for c in api["classes"] for m in get(c, "methods", []))
    helpers = Set{String}()
    for c in api["classes"], s in get(c, "signals", []), prefix in ("connect_", "disconnect_")
        n = prefix * s["name"]
        n in methods || push!(helpers, n)
    end
    return helpers
end

"C#-event equivalents for engine signals: `connect_pressed(button, f)` (`button.Pressed += f`) and `disconnect_pressed`."
function emit_signal_helpers(io::IO, ctx::Context, class, helpers)
    T = class_ref(ctx, class)
    for s in get(ctx.classes[class], "signals", [])
        n = s["name"]
        sym = repr(Symbol(n))
        if "connect_$n" in helpers
            println(io, "$(qualify(ctx, false, "connect_$n"))(self::$T, f; flags = 0) = ",
                    "$(qualify(ctx, false, "connect_callable"))(self, $sym, f, flags)")
        end
        if "disconnect_$n" in helpers
            println(io, "$(qualify(ctx, false, "disconnect_$n"))(self::$T, f) = ",
                    "$(qualify(ctx, false, "disconnect_callable"))(self, $sym, f)")
        end
    end
end

function emit_members(io::IO, ctx::Context, classes, fields)
    helpers = signal_helper_names(ctx.api)
    for class in classes
        c = ctx.classes[class]
        T = class_ref(ctx, class)
        if get(c, "is_instantiable", false)
            println(io, "\"Create a new `$(type_name(class))`.\"")
            println(io, "$T() = Internals.construct_object($(native_ref(ctx, class)), $(repr(Symbol(class))))\n")
        end
        for m in get(c, "methods", [])
            get(m, "is_virtual", false) && continue
            if get(m, "is_vararg", false)
                emit_vararg_method(io, ctx, class, m, fields)
            else
                emit_ptrcall_method(io, ctx, class, m, fields)
            end
        end
        emit_properties(io, ctx, class)
        emit_signal_helpers(io, ctx, class, helpers)
    end
end

function emit_singletons(io::IO, ctx::Context, classes)
    for s in ctx.api["singletons"]
        class = s["type"]
        class in classes || continue
        T = class_ref(ctx, class)
        println(io, "const __SINGLETON_$(type_name(class)) = Internals.SingletonCache{$(native_ref(ctx, class))}($(repr(Symbol(s["name"]))))")
        println(io, "Internals.singleton(::Type{$T}) = Internals.get_singleton!(__SINGLETON_$(type_name(class)))")
        methods = get(ctx.classes[class], "methods", [])
        statics = Set(m["name"] for m in methods if get(m, "is_static", false))
        for f in sort(unique(method_function(ctx, m["name"]) for m in methods
                             if !get(m, "is_virtual", false) && !(m["name"] in statics)))
            println(io, "$f(::Type{$T}, args...) = $f(Internals.singleton($T), args...)")
        end
        println(io)
    end
end

function emit_exports(io::IO, ctx::Context, classes, functions = String[])
    exported_types = String[]
    for c in classes
        T = type_name(c)
        if T in ctx.reserved || T in ctx.base_functions
            push!(ctx.renames, "class not exported (clashes with Base): $(class_ref(ctx, c))")
        else
            push!(exported_types, T)
        end
    end
    exports = vcat(exported_types, functions, reduce(vcat, (enum_exports(ctx, c) for c in classes); init = String[]))
    for chunk in Iterators.partition(exports, 50)
        println(io, "export " * join(chunk, ", "))
    end
end

"Write the core engine API (included into module `Godot`). Returns the generation context."
function generate_classes(io::IO, api; precision::AbstractString = "single")
    ctx = Context(api; scope = :core)
    fields = struct_fields(api, build_configuration(precision))
    order = class_order(ctx)
    core = scope_classes(ctx)

    println(io, "# GENERATED by GodotBindgen from extension_api.json ($(api["header"]["version_full_name"])). Do not edit.\n" * SOURCE_NOTICE * "\n")

    # Every method generic function is owned by `Godot`, so core and editor classes (GodotEditor) share them.
    fnames = Set{String}()
    virtual_names = Set{String}()
    for c in order, m in get(ctx.classes[c], "methods", [])
        f = method_function(ctx, m["name"])
        startswith(f, "Base.") && continue
        get(m, "is_virtual", false) ? push!(virtual_names, f) : push!(fnames, f)
    end
    for f in sort(collect(fnames))
        println(io, "function $f end")
    end
    helpers = sort(collect(signal_helper_names(api)))
    for f in helpers
        println(io, "function $f end")
    end
    println(io)

    emit_type_declarations(io, ctx, core)
    emit_registries(io, ctx, core)
    println(io, "Internals.register_classes!(__CLASS_WRAPPERS, __CLASS_SIGNALS, __CLASS_VIRTUALS)\n")
    emit_members(io, ctx, core, fields)
    emit_singletons(io, ctx, core)

    for f in sort(collect(virtual_names))
        docs = String[]
        for class in order, m in get(ctx.classes[class], "methods", [])
            (get(m, "is_virtual", false) && method_function(ctx, m["name"]) == f) || continue
            args = join(["$(safe_arg(a["name"]))::$(a["type"])" for a in get(m, "arguments", [])], ", ")
            push!(docs, "    $f(self::$(type_name(class))$(isempty(args) ? "" : ", " * args))")
            isempty(docs[1:end-1]) && !isempty(get(m, "description", "")) && push!(docs, "", bbcode_to_markdown(m["description"]), "")
        end
        print(io, docstring(vcat(["Virtual method; define a method for your script type to override it.", ""], docs)))
        println(io, "function $f end")
    end
    println(io)

    emit_exports(io, ctx, core, vcat(sort(collect(fnames)), helpers))
    return ctx
end

"""
Write the editor-only API (included into package `GodotEditor`, the analog of GodotSharpEditor, which the native host
loads only when the editor runs). Returns the generation context.
"""
function generate_editor_classes(io::IO, api; precision::AbstractString = "single")
    ctx = Context(api; scope = :editor)
    fields = struct_fields(api, build_configuration(precision))
    classes = scope_classes(ctx)
    println(io, "# GENERATED by GodotBindgen from extension_api.json ($(api["header"]["version_full_name"])). Do not edit.\n" * SOURCE_NOTICE)
    println(io, "# Editor-only classes; included by module GodotEditor.\n")
    emit_type_declarations(io, ctx, classes)
    emit_registries(io, ctx, classes)
    emit_members(io, ctx, classes, fields)
    emit_singletons(io, ctx, classes)
    emit_exports(io, ctx, classes)
    return ctx
end

function generate_report(io::IO, ctx::Context, others::Context...)
    println(io, "# Generated binding report (renames, dropped defaults, skipped members)")
    println(io, "rename: Object -> GodotObject")
    for name in sort(collect(ctx.base_functions))
        any(c -> any(m -> m["name"] == name, get(c, "methods", [])), values(ctx.classes)) &&
            println(io, "extends Base: $name")
    end
    for c in (ctx, others...)
        foreach(r -> println(io, r), c.renames)
        foreach(s -> println(io, "skipped: ", s), c.skipped)
    end
end
