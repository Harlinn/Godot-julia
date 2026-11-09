# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Hot reload of Julia scripts. Behavior ported from CSharpLanguage::reload_assemblies / CSharpScript::reload
# (modules/mono/csharp_script.cpp), ScriptSerializationGenerator and DelegateUtils (Godot.SourceGenerators,
# GodotSharp/Core/DelegateUtils.cs), and GDScriptLanguage::reload_scripts (modules/gdscript/gdscript.cpp)
# (MIT, Godot contributors). Design: ADR 0011.

const RELOAD_ATTEMPTS_SETTING = "julia/project/reload_attempts"
const RELOAD_ATTEMPTS_DEFAULT = 3
const RELOAD_LOCK = ReentrantLock()
const PENDING_RELOADS = Dict{Ptr{Cvoid}, Int}()      # scripts whose reload from disk failed => attempts left
const GENERATIONS = IdDict{Module, ScriptState}()    # every live generation module => its script
const REVISE_ID = Base.PkgId(Base.UUID("295af30f-e4ad-537b-8983-00126c2a3abe"), "Revise")

function register_reload_settings!()
    ps = Godot.ProjectSettings
    Godot.has_setting(ps, RELOAD_ATTEMPTS_SETTING) || Godot.set_setting(ps, RELOAD_ATTEMPTS_SETTING, RELOAD_ATTEMPTS_DEFAULT)
    Godot.set_initial_value(ps, RELOAD_ATTEMPTS_SETTING, RELOAD_ATTEMPTS_DEFAULT)
    Godot.add_property_info(ps, Dict{String, Any}("name" => RELOAD_ATTEMPTS_SETTING, "type" => Int(VT_INT),
                                                  "hint" => Int(hint_value(:RANGE)), "hint_string" => "1,16,1"))
    return nothing
end

function reload_attempts()
    v = Godot.get_setting(Godot.ProjectSettings, RELOAD_ATTEMPTS_SETTING, RELOAD_ATTEMPTS_DEFAULT)
    return v isa Integer ? max(1, Int(v)) : RELOAD_ATTEMPTS_DEFAULT
end

"Let Revise.jl update changed packages first, when the user loaded it (C# reloads all project assemblies)."
function revise_packages!()
    m = get(Base.loaded_modules, REVISE_ID, nothing)
    m === nothing && return nothing
    try
        Base.invokelatest(getglobal(m, :revise))
    catch e
        report_exception(e, catch_backtrace())
    end
    return nothing
end

instances_of(st::ScriptState) = @lock INSTANCES_LOCK ScriptInstance[si for si in values(INSTANCES) if si.script == st.ptr]

"`roots` plus every loaded script that depends on them (transitively), each after the scripts it depends on."
function reload_order(roots::Vector{ScriptState})
    states = @lock SCRIPTS_LOCK collect(values(SCRIPTS))
    selected = Dict{Ptr{Cvoid}, ScriptState}(st.ptr => st for st in roots)
    grown = true
    while grown
        grown = false
        for st in states
            haskey(selected, st.ptr) && continue
            if any(d -> haskey(selected, d), st.deps)
                selected[st.ptr] = st
                grown = true
            end
        end
    end
    order = ScriptState[]
    seen = Set{Ptr{Cvoid}}()
    function visit(st)
        st.ptr in seen && return
        push!(seen, st.ptr)
        for d in st.deps
            ds = get(selected, d, nothing)
            ds === nothing || visit(ds)
        end
        push!(order, st)
    end
    foreach(visit, roots)
    foreach(visit, sort!(collect(values(selected)); by = st -> st.path))
    return order
end

needs_reload(st::ScriptState, source::String) =
    !st.valid || st.info === nothing || source != st.source || any(si -> si.suspended, instances_of(st))

"""
    reload_scripts!(requests) -> Dict{ScriptState, Int}

Load each `script => source` pair and every script depending on them, then migrate their live instances to the new
generation (C#: `CSharpLanguage::reload_assemblies`). Returns the load result (`Error` code) per script.
"""
function reload_scripts!(requests::Vector{<:Pair{ScriptState, String}})
    @lock RELOAD_LOCK begin
        results = Dict{ScriptState, Int}()
        todo = Pair{ScriptState, String}[]
        for (st, src) in requests
            st.generation > 0 && !needs_reload(st, src) ? (results[st] = ERR_OK) : push!(todo, st => src)
        end
        isempty(todo) && return results
        any(p -> p.first.generation > 0, todo) && revise_packages!()
        sources = Dict{ScriptState, String}(todo)
        order = reload_order(first.(todo))
        for st in order
            results[st] = load_script!(st, get(sources, st, st.source))
            st.mod === nothing || (GENERATIONS[st.mod] = st)
        end
        migrate_instances!(order)
        return results
    end
end

"Reload scripts from their files (editor saves, the remote debugger, retries); failed loads are retried in `_frame`."
function reload_from_disk!(states::Vector{ScriptState}; retry::Bool = false)
    requests = Pair{ScriptState, String}[]
    for st in states
        isempty(st.path) && continue
        src = try
            read_source(st.path)
        catch e
            report_exception(e, catch_backtrace())
            continue
        end
        # A retry of an unchanged failing file would only repeat the same errors.
        retry && src == st.source || push!(requests, st => src)
    end
    results = isempty(requests) ? Dict{ScriptState, Int}() : reload_scripts!(requests)
    for st in states
        r = get(results, st, retry ? ERR_COMPILATION_FAILED : ERR_OK)
        if r == ERR_OK
            delete!(PENDING_RELOADS, st.ptr)
        else
            left = retry ? get(PENDING_RELOADS, st.ptr, 1) - 1 : reload_attempts() - 1
            left > 0 ? (PENDING_RELOADS[st.ptr] = left) : delete!(PENDING_RELOADS, st.ptr)
        end
    end
    return results
end

"Retry failed reloads once per frame, up to `julia/project/reload_attempts` (C#: `dotnet/project/assembly_reload_attempts`)."
function retry_reloads!()
    isempty(PENDING_RELOADS) && return nothing
    states = ScriptState[]
    for p in collect(keys(PENDING_RELOADS))
        st = find_state(p)
        st === nothing ? delete!(PENDING_RELOADS, p) : push!(states, st)
    end
    isempty(states) || reload_from_disk!(states; retry = true)
    return nothing
end

# --- State transfer (C#: ScriptSerializationGenerator's SaveGodotObjectData / RestoreGodotObjectData) -------------

struct NoTransfer end
const NO_TRANSFER = NoTransfer()

is_generation_type(@nospecialize(T)) = T isa DataType && haskey(GENERATIONS, parentmodule(T))

"`v` as a value for a field of type `T` after reload, or `NO_TRANSFER` (the field then keeps its default)."
function migrate_value(@nospecialize(v), @nospecialize(T), replaced::IdDict{Any, Any}, depth::Int = 0)
    v = get(replaced, v, v)
    v isa T && return v
    depth > 8 && return NO_TRANSFER
    if v isa Base.Enum && T isa DataType && T <: Base.Enum
        return try T(Integer(v)) catch; NO_TRANSFER end
    end
    if v isa AbstractVector && T isa DataType && T <: AbstractVector && isconcretetype(T)
        E = eltype(T)
        xs = Any[migrate_value(x, E, replaced, depth + 1) for x in v]
        any(x -> x === NO_TRANSFER, xs) && return NO_TRANSFER
        return try convert(T, xs) catch; NO_TRANSFER end
    end
    # A struct declared in the script itself: rebuild it as the same-named struct of the new generation.
    S = typeof(v)
    if is_generation_type(S) && T isa DataType && isconcretetype(T) && nameof(T) === nameof(S) &&
       fieldnames(T) == fieldnames(S) && !(T <: GodotObject)
        vals = Any[migrate_value(getfield(v, i), fieldtype(T, i), replaced, depth + 1) for i in 1:fieldcount(T)]
        any(x -> x === NO_TRANSFER, vals) && return NO_TRANSFER
        return ccall(:jl_new_structv, Any, (Any, Ptr{Any}, UInt32), T, vals, length(vals))
    end
    return try convert(T, v) catch; NO_TRANSFER end
end

"A new-generation struct for the object of `si`: field initializers run, then every field that still exists takes its old value."
function transfer_state(si::ScriptInstance, info::ScriptClassInfo, replaced::IdDict{Any, Any})
    obj = Base.invokelatest(construct_instance, info, si.owner)
    old = si.obj
    OT = typeof(old)
    for f in info.fields
        hasfield(OT, f.name) || continue                    # new field: default
        v = Base.invokelatest(migrate_value, getfield(old, f.name), f.type, replaced)
        v === NO_TRANSFER || setfield!(obj, f.name, v)      # type changed incompatibly: default
    end
    return obj
end

"""
Run the hot-reload hook `name` (`_before_reload` on the old instance, `_after_reload` on the new one) if the script
defines it (C#: `ISerializationListener.OnBeforeSerialize` / `OnAfterDeserialize`). Errors are reported, not thrown.
"""
function reload_hook(name::Symbol, @nospecialize(obj))
    f = getglobal(Godot, name)
    isempty(self_methods(f, typeof(obj))) && return nothing
    try
        Base.invokelatest(f, obj)
    catch e
        report_exception(e, catch_backtrace())
    end
    return nothing
end

function migrate_instances!(order::Vector{ScriptState})
    replaced = IdDict{Any, Any}()
    migrated = Any[]
    for st in order
        info = st.info
        for si in instances_of(st)
            if info === nothing
                # Failed load: keep the instance and its state, run no user code (C#: placeholder instances).
                si.suspended = true
                continue
            end
            si.info === info && (si.suspended = false; continue)
            si.suspended || reload_hook(:_before_reload, si.obj)
            new = try
                transfer_state(si, info, replaced)
            catch e
                report_exception(e, catch_backtrace())
                si.suspended = true
                continue
            end
            old = si.obj
            replaced[old] = new
            si.obj = new
            si.info = info
            si.suspended = false
            Godot.bind_wrapper!(si.owner, new)   # the old struct now reads as a freed object
            push!(migrated, new)
        end
    end
    if !isempty(replaced)
        retarget_fields!(replaced)
        retarget_callables!(replaced)
    end
    foreach(o -> reload_hook(:_after_reload, o), migrated)
    retire_generations!()
    return nothing
end

"Point fields of other live instances that held a migrated struct at its replacement."
function retarget_fields!(replaced::IdDict{Any, Any})
    for si in @lock INSTANCES_LOCK collect(values(INSTANCES))
        o = si.obj
        C = typeof(o)
        for i in 2:fieldcount(C)                             # field 1 is __ptr
            isdefined(o, i) || continue
            v = getfield(o, i)
            nv = get(replaced, v, nothing)
            if nv !== nothing
                nv isa fieldtype(C, i) && setfield!(o, i, nv)
            elseif v isa Vector && !isbitstype(eltype(v))
                for j in eachindex(v)
                    isassigned(v, j) || continue
                    r = get(replaced, v[j], nothing)
                    r !== nothing && r isa eltype(v) && (v[j] = r)
                end
            end
        end
    end
    return nothing
end

# --- Julia callables (C#: DelegateUtils.TrySerializeDelegate / TryDeserializeDelegate) ----------------------------

"Placeholder for a connected Julia callable whose code did not survive a reload; calling it does nothing."
struct RetiredCallable
    description::String
end
(::RetiredCallable)(args...) = nothing
Base.show(io::IO, r::RetiredCallable) = print(io, "RetiredCallable(", r.description, ")")

function current_module(m::Module)
    st = get(GENERATIONS, m, nothing)
    return st === nothing || !st.valid ? nothing : st.mod
end

function migrate_captured(@nospecialize(x), replaced::IdDict{Any, Any})
    if x isa Core.Box
        isdefined(x, :contents) && haskey(replaced, x.contents) && (x.contents = replaced[x.contents])
        return x
    end
    return get(replaced, x, x)
end

"Concrete type of `W` (a closure type's UnionAll wrapper) whose type-parameter fields hold `vals`, or `nothing`."
function closure_type(@nospecialize(W), vals::Vector{Any})
    U = Base.unwrap_unionall(W)
    U isa DataType && fieldcount(U) == length(vals) || return nothing
    params = Dict{TypeVar, Any}()
    for (i, t) in enumerate(fieldtypes(U))
        t isa TypeVar && (params[t] = typeof(vals[i]))
    end
    all(tv -> haskey(params, tv), U.parameters) || return nothing
    T = isempty(U.parameters) ? U : W{(params[tv] for tv in U.parameters)...}
    all(i -> vals[i] isa fieldtype(T, i), eachindex(vals)) || return nothing
    return T
end

"`f` re-targeted to the new script generation: same-named function or closure there, captured instances replaced."
function retarget(@nospecialize(f), replaced::IdDict{Any, Any})
    T = typeof(f)
    old_mod = parentmodule(T)
    from_old_generation = haskey(GENERATIONS, old_mod) && current_module(old_mod) !== old_mod
    target_mod = from_old_generation ? current_module(old_mod) : old_mod
    target_mod === nothing && return RetiredCallable(sprint(show, f))
    if fieldcount(T) == 0
        from_old_generation || return f
        if f isa Function && !startswith(String(nameof(f)), "#")
            g = isdefined(target_mod, nameof(f)) ? getglobal(target_mod, nameof(f)) : nothing
            g isa Function && return g
        end
        W = isdefined(target_mod, nameof(T)) ? getglobal(target_mod, nameof(T)) : nothing
        return W isa DataType && isdefined(W, :instance) ? W.instance : RetiredCallable(sprint(show, f))
    end
    vals = Any[migrate_captured(getfield(f, i), replaced) for i in 1:fieldcount(T)]
    if !from_old_generation
        changed = [i for i in eachindex(vals) if vals[i] !== getfield(f, i)]
        isempty(changed) && return f
        if ismutabletype(T)
            for i in changed
                vals[i] isa fieldtype(T, i) && !isconst(T, i) || continue
                Base.isfieldatomic(T, i) ? setfield!(f, i, vals[i], :sequentially_consistent) : setfield!(f, i, vals[i])
            end
            return f
        end
    end
    W = from_old_generation ? (isdefined(target_mod, nameof(T)) ? getglobal(target_mod, nameof(T)) : nothing) : T.name.wrapper
    (W isa Type && fieldnames(Base.unwrap_unionall(W)) == fieldnames(T)) || return RetiredCallable(sprint(show, f))
    NT = closure_type(W, vals)
    NT === nothing && return RetiredCallable(sprint(show, f))
    return ccall(:jl_new_structv, Any, (Any, Ptr{Any}, UInt32), NT, vals, length(vals))
end

function retarget_callables!(replaced::IdDict{Any, Any})
    boxes = @lock PINS_LOCK JuliaCallable[x for x in values(PINS) if x isa JuliaCallable]
    memo = IdDict{Any, Any}()
    for b in boxes
        b.f isa RetiredCallable && continue
        nf = get!(memo, b.f) do
            try
                Base.invokelatest(retarget, b.f, replaced)
            catch e
                report_exception(e, catch_backtrace())
                b.f
            end
        end
        nf === b.f && continue
        nf isa RetiredCallable && host_report_error(true, "reload", "", 0,
            "a connected Julia callable could not be moved to the reloaded script and was disabled: $(nf.description)")
        b.f = nf
    end
    return nothing
end

# --- Retiring generations (C#: unloading the collectible AssemblyLoadContext) ---------------------------------------

"Delete the methods and class records of generation modules nothing uses any more, so their code can be collected."
function retire_generations!()
    used = Set{Module}()
    for st in @lock SCRIPTS_LOCK collect(values(SCRIPTS))
        st.info === nothing || foreach(ci -> push!(used, ci.mod), class_chain(st.info))
    end
    for si in @lock INSTANCES_LOCK collect(values(INSTANCES))
        foreach(ci -> push!(used, ci.mod), class_chain(si.info))
    end
    dead = Set{Module}(m for m in keys(GENERATIONS) if !(m in used) && !is_precompiled(m))
    isempty(dead) && return 0
    ms = Method[]
    Base.visit(Core.methodtable) do m
        m isa Method && m.module in dead && push!(ms, m)
    end
    foreach(Base.delete_method, ms)
    @lock CLASSES_LOCK filter!(kv -> !(kv.second.mod in dead), SCRIPT_CLASSES)
    foreach(m -> delete!(GENERATIONS, m), dead)
    return length(dead)
end

live_generation_count() = length(GENERATIONS)

# --- JuliaLanguage handlers ----------------------------------------------------------------------------------------

function script_states(scripts)
    states = ScriptState[]
    for s in scripts
        s isa GodotObject || continue
        st = find_state(Internals.native_ptr(s))
        st === nothing || push!(states, st)
    end
    return states
end

"Push the file contents into the engine's script resource (what `GDScript::load_source_code` does) and reload."
function reload_resources!(scripts)
    states = script_states(scripts)
    results = reload_from_disk!(states)
    for s in scripts
        st = s isa GodotObject ? find_state(Internals.native_ptr(s)) : nothing
        st === nothing || Godot.set_source_code(s, st.source)
    end
    return results
end

language_reload_scripts(::Ptr{Cvoid}, scripts, ::Bool) = (reload_resources!(collect(scripts)); nothing)
language_reload_tool_script(::Ptr{Cvoid}, script, ::Bool) = (reload_resources!([script]); nothing)

function language_reload_all_scripts(::Ptr{Cvoid})
    scripts = Any[Godot.wrap_object(st.ptr, false) for st in @lock(SCRIPTS_LOCK, collect(values(SCRIPTS))) if !isempty(st.path)]
    reload_resources!(scripts)
    return nothing
end
