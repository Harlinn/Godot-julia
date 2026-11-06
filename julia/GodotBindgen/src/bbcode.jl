# Godot class-reference BBCode → Markdown for docstrings.

function dedent(code::AbstractString)
    lines = split(strip(code, '\n'), '\n')
    indents = [length(l) - length(lstrip(l, ['\t', ' '])) for l in lines if !isempty(strip(l))]
    n = isempty(indents) ? 0 : minimum(indents)
    return join((length(l) >= n ? l[(n + 1):end] : lstrip(l) for l in lines), '\n')
end

function replace_blocks(s::AbstractString, re::Regex, f)
    out = IOBuffer()
    last = 1
    for m in eachmatch(re, s)
        print(out, s[last:(m.offset - 1)], f(m))
        last = m.offset + ncodeunits(m.match)
    end
    print(out, s[last:end])
    return String(take!(out))
end

"""
    bbcode_to_markdown(text) -> String

Convert Godot class-reference markup to Markdown. Code examples keep their GDScript and C# variants.
"""
function bbcode_to_markdown(text::AbstractString)
    s = replace(String(text), "\r" => "")
    s = replace_blocks(s, r"\[codeblocks\](.*?)\[/codeblocks\]"s, m -> begin
        parts = String[]
        for lang in ("gdscript", "csharp")
            mm = match(Regex("\\[$lang\\](.*?)\\[/$lang\\]", "s"), m[1])
            mm === nothing || push!(parts, "```$lang\n" * dedent(mm[1]) * "\n```")
        end
        "\n" * join(parts, "\n") * "\n"
    end)
    s = replace_blocks(s, r"\[codeblock(?:\s[^\]]*)?\](.*?)\[/codeblock\]"s, m -> "\n```\n" * dedent(m[1]) * "\n```\n")
    s = replace(s, r"\[code\](.*?)\[/code\]"s => s"`\1`")
    s = replace(s, r"\[kbd\](.*?)\[/kbd\]"s => s"`\1`")
    s = replace(s, r"\[b\](.*?)\[/b\]"s => s"**\1**")
    s = replace(s, r"\[i\](.*?)\[/i\]"s => s"*\1*")
    s = replace(s, r"\[s\](.*?)\[/s\]"s => s"~~\1~~")
    s = replace(s, r"\[url=([^\]]+)\](.*?)\[/url\]"s => s"[\2](\1)")
    s = replace(s, r"\[url\](.*?)\[/url\]"s => s"<\1>")
    s = replace(s, r"\[/?(u|center|color[^\]]*|font[^\]]*|font_size[^\]]*|lang[^\]]*)\]" => "")
    s = replace(s, r"\[(method|member|signal|constant|enum|annotation|theme_item|param|operator|constructor) ([^\]]+)\]" => s"`\2`")
    s = replace(s, r"\[(Object)\]" => "`GodotObject`")
    s = replace(s, r"\[(@?[A-Z][A-Za-z0-9_]*)\]" => s"`\1`")
    s = replace(s, "[br]" => "\n")
    s = replace(s, "[lb]" => "[", "[rb]" => "]")
    return strip(s)
end
