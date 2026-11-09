# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Translatable strings in .jl scripts for POT generation (Project Settings → Localization → Template Generation).
# Analog of GodotTools/CsTranslationParserPlugin.cs (MIT, Godot contributors): string-literal arguments of
# `tr`/`atr` (message, context), `tr_n`/`atr_n` (message, plural, count, context) and
# `translate`/`translate_plural(TranslationServer, ...)`, with `# TRANSLATORS:` comments on the same line or the
# comment lines directly above, and `# NO_TRANSLATE` on the line to skip a call.

# Function name => (message, plural, context) positions among the call's positional arguments (0 = none).
const TR_CALLS = Dict(:tr => (2, 0, 3), :atr => (2, 0, 3), :tr_n => (2, 3, 5), :atr_n => (2, 3, 5),
                      :translate => (2, 0, 3), :translate_plural => (2, 3, 5))

called_name(f) = f isa Symbol ? f : f isa Expr && f.head === :. && f.args[end] isa QuoteNode ? f.args[end].value : nothing

literal(x) = x isa String ? x : nothing

"`# TRANSLATORS:` comment for a call on `line` (1-based), `nothing` when the line says `# NO_TRANSLATE`."
function translator_comment(lines::Vector{<:AbstractString}, line::Int)
    1 <= line <= length(lines) || return ""
    text = lines[line]
    occursin(r"#\s*NO_TRANSLATE\b", text) && return nothing
    m = match(r"#\s*TRANSLATORS:\s*(.*)$", text)
    m === nothing || return String(strip(m[1]))
    block = String[]
    k = line - 1
    while k >= 1 && startswith(lstrip(lines[k]), "#")
        pushfirst!(block, String(strip(lstrip(lstrip(lines[k]), '#'))))
        k -= 1
    end
    (isempty(block) || !startswith(block[1], "TRANSLATORS:")) && return ""
    block[1] = String(strip(block[1][13:end]))
    return join(filter(!isempty, block), " ")
end

function collect_tr!(out::Vector{Vector{String}}, @nospecialize(x), line::Int, lines)
    x isa Expr || return line
    if x.head in (:block, :toplevel)
        for a in x.args
            a isa LineNumberNode ? (line = a.line) : collect_tr!(out, a, line, lines)
        end
        return line
    end
    if x.head === :call
        spec = get(TR_CALLS, called_name(x.args[1]), nothing)
        if spec !== nothing
            pos = Any[a for a in x.args[2:end] if !(a isa Expr && a.head in (:parameters, :kw))]
            kws = Dict{Symbol, Any}()
            for a in x.args[2:end]
                a isa Expr && a.head === :kw && (kws[a.args[1]] = a.args[2])
                a isa Expr && a.head === :parameters && foreach(k -> k isa Expr && k.head === :kw && (kws[k.args[1]] = k.args[2]), a.args)
            end
            at(i) = 0 < i <= length(pos) ? literal(pos[i]) : nothing
            msg = at(spec[1])
            if msg !== nothing && !isempty(msg)
                comment = translator_comment(lines, line)
                if comment !== nothing
                    plural = something(at(spec[2]), literal(get(kws, :plural_message, nothing)), "")
                    ctx = something(at(spec[3]), literal(get(kws, :context, nothing)), "")
                    push!(out, [msg, ctx, plural, comment, string(line)])
                end
            end
        end
    end
    for a in x.args
        collect_tr!(out, a, line, lines)
    end
    return line
end

"""
    translation_strings(source) -> Vector{Vector{String}}

Translatable strings of a Julia script as `[msgid, msgctxt, msgid_plural, comment, source_line]` entries (the format
of `EditorTranslationParserPlugin._parse_file`). Parse errors yield the strings found before them.
"""
function translation_strings(source::AbstractString)
    out = Vector{String}[]
    lines = split(source, '\n')
    ex = try
        Meta.parseall(source; filename = "translation")
    catch
        return out
    end
    collect_tr!(out, ex, 1, lines)
    return out
end

"Bridge handler for `JuliaTranslationParserPlugin::_parse_file`."
function translation_parse_file(::Ptr{Cvoid}, path)
    source = Godot.get_file_as_string(Godot.FileAccess, String(path))
    return translation_strings(source)
end
