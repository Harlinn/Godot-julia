# Color (always 32-bit floats, independent of real_t).
# Ported from Godot's core/math/color.h/.cpp and GodotSharp/Core/Color.cs, Colors.cs (MIT, Godot contributors).

Color() = Color(0, 0, 0, 1)
Color(r::Real, g::Real, b::Real) = Color(r, g, b, 1)
"`c` with alpha replaced by `alpha`."
Color(c::Color, alpha::Real) = Color(c.r, c.g, c.b, alpha)
"Color from a 32-bit RGBA integer (C#: `new Color(uint)`); same as `hex(Color, rgba)`."
Color(rgba::UInt32) = hex(Color, rgba)
"Color from a 64-bit RGBA integer (C#: `new Color(ulong)`); same as `hex64(Color, rgba)`."
Color(rgba::UInt64) = hex64(Color, rgba)
"Color from an HTML code (`\"#ff8000\"`) or a named color (`\"red\"`); see `from_string`."
Color(code::AbstractString) = from_string(Color, code, Color())
Color(code::AbstractString, alpha::Real) = Color(Color(code), alpha)

@inline _f32(x) = convert(Float32, x)
Base.:+(c::Color) = c
Base.:-(c::Color) = Color(1 - c.r, 1 - c.g, 1 - c.b, 1 - c.a)
Base.:+(a::Color, b::Color) = Color(a.r + b.r, a.g + b.g, a.b + b.b, a.a + b.a)
Base.:-(a::Color, b::Color) = Color(a.r - b.r, a.g - b.g, a.b - b.b, a.a - b.a)
Base.:*(a::Color, b::Color) = Color(a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.a)
Base.:/(a::Color, b::Color) = Color(a.r / b.r, a.g / b.g, a.b / b.b, a.a / b.a)
Base.:*(c::Color, s::Real) = (s = _f32(s); Color(c.r * s, c.g * s, c.b * s, c.a * s))
Base.:*(s::Real, c::Color) = c * s
Base.:/(c::Color, s::Real) = (s = _f32(s); Color(c.r / s, c.g / s, c.b / s, c.a / s))
Base.:(==)(a::Color, b::Color) = a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a
Base.show(io::IO, c::Color) = print(io, "Color(", c.r, ", ", c.g, ", ", c.b, ", ", c.a, ")")
Base.@propagate_inbounds Base.getindex(c::Color, i::Integer) =
    (@boundscheck 1 <= i <= 4 || throw(BoundsError(c, i)); getfield(c, Int(i)))
is_equal_approx(a::Color, b::Color) =
    is_equal_approx(a.r, b.r) && is_equal_approx(a.g, b.g) && is_equal_approx(a.b, b.b) && is_equal_approx(a.a, b.a)
Base.isapprox(a::Color, b::Color; kwargs...) = isempty(kwargs) ? is_equal_approx(a, b) :
    isapprox(a.r, b.r; kwargs...) && isapprox(a.g, b.g; kwargs...) && isapprox(a.b, b.b; kwargs...) && isapprox(a.a, b.a; kwargs...)

"Hue in `[0, 1)`."
function get_h(c::Color)
    lo = _min(_min(c.r, c.g), c.b)
    hi = _max(_max(c.r, c.g), c.b)
    delta = hi - lo
    delta == 0 && return 0f0
    h = c.r == hi ? (c.g - c.b) / delta : c.g == hi ? 2 + (c.b - c.r) / delta : 4 + (c.r - c.g) / delta
    h /= 6
    return h < 0 ? h + 1 : h
end
"HSV saturation."
get_s(c::Color) = (lo = _min(_min(c.r, c.g), c.b); hi = _max(_max(c.r, c.g), c.b); hi != 0 ? (hi - lo) / hi : 0f0)
"HSV value."
get_v(c::Color) = _max(_max(c.r, c.g), c.b)
"`(h, s, v)` of `c` (C#: `ToHsv`)."
to_hsv(c::Color) = (get_h(c), get_s(c), get_v(c))
_ok_hsl(c::Color) = OkColor.srgb_to_okhsl(c.r, c.g, c.b)
_ok_h(c::Color) = (h = _ok_hsl(c)[1]; isnan(h) ? 0f0 : _clamp(h, 0f0, 1f0))
_ok_s(c::Color) = _clamp(_ok_hsl(c)[2], 0f0, 1f0)
_ok_l(c::Color) = _clamp(_ok_hsl(c)[3], 0f0, 1f0)
_c8(x::Float32) = trunc(Int32, _round(x * 255f0))

@inline function Base.getproperty(c::Color, s::Symbol)
    s === :h && return get_h(c)
    s === :s && return get_s(c)
    s === :v && return get_v(c)
    s === :r8 && return _c8(getfield(c, :r))
    s === :g8 && return _c8(getfield(c, :g))
    s === :b8 && return _c8(getfield(c, :b))
    s === :a8 && return _c8(getfield(c, :a))
    s === :ok_hsl_h && return _ok_h(c)
    s === :ok_hsl_s && return _ok_s(c)
    s === :ok_hsl_l && return _ok_l(c)
    s === :luminance && return get_luminance(c)
    return getfield(c, s)
end
Base.propertynames(::Color) = (:r, :g, :b, :a, :h, :s, :v, :r8, :g8, :b8, :a8, :ok_hsl_h, :ok_hsl_s, :ok_hsl_l, :luminance)

_byte(x::Float32) = UInt32(Int64(_round(x * 255f0)) & 0xff)
_word(x::Float32) = UInt64(Int64(_round(Float64(x) * 65535)) & 0xffff)
_pack32(a, b, c, d) = Int64((_byte(a) << 24) | (_byte(b) << 16) | (_byte(c) << 8) | _byte(d))
_pack64(a, b, c, d) = reinterpret(Int64, (_word(a) << 48) | (_word(b) << 32) | (_word(c) << 16) | _word(d))
"32-bit integer in ARGB order."
to_argb32(c::Color) = _pack32(c.a, c.r, c.g, c.b)
"32-bit integer in ABGR order."
to_abgr32(c::Color) = _pack32(c.a, c.b, c.g, c.r)
"32-bit integer in RGBA order."
to_rgba32(c::Color) = _pack32(c.r, c.g, c.b, c.a)
"64-bit integer in ARGB order."
to_argb64(c::Color) = _pack64(c.a, c.r, c.g, c.b)
"64-bit integer in ABGR order."
to_abgr64(c::Color) = _pack64(c.a, c.b, c.g, c.r)
"64-bit integer in RGBA order."
to_rgba64(c::Color) = _pack64(c.r, c.g, c.b, c.a)

_hex2(x::Float32) = string(_clamp(Int(_round(x * 255f0)), 0, 255); base = 16, pad = 2)
"HTML hex code without `#` (`\"rrggbbaa\"`, or `\"rrggbb\"` without alpha)."
to_html(c::Color, with_alpha::Bool = true) = string(_hex2(c.r), _hex2(c.g), _hex2(c.b), with_alpha ? _hex2(c.a) : "")

Base.clamp(c::Color, lo::Color = Color(0, 0, 0, 0), hi::Color = Color(1, 1, 1, 1)) =
    Color(_clamp(c.r, lo.r, hi.r), _clamp(c.g, lo.g, hi.g), _clamp(c.b, lo.b, hi.b), _clamp(c.a, lo.a, hi.a))
"RGB inverted (alpha kept)."
inverted(c::Color) = Color(1 - c.r, 1 - c.g, 1 - c.b, c.a)
lerp(a::Color, b::Color, w::Real) = (w = _f32(w); Color(lerp(a.r, b.r, w), lerp(a.g, b.g, w), lerp(a.b, b.b, w), lerp(a.a, b.a, w)))
"`c` mixed toward white by `amount`."
lightened(c::Color, amount::Real) =
    (t = _f32(amount); Color(c.r + (1 - c.r) * t, c.g + (1 - c.g) * t, c.b + (1 - c.b) * t, c.a))
"`c` mixed toward black by `amount`."
darkened(c::Color, amount::Real) = (t = _f32(amount); Color(c.r * (1 - t), c.g * (1 - t), c.b * (1 - t), c.a))
"`over` alpha-blended on top of `c`."
function blend(c::Color, over::Color)
    sa = 1 - over.a
    a = c.a * sa + over.a
    a == 0 && return Color(0, 0, 0, 0)
    return Color((c.r * c.a * sa + over.r * over.a) / a, (c.g * c.a * sa + over.g * over.a) / a,
                 (c.b * c.a * sa + over.b * over.a) / a, a)
end
"Relative luminance (Rec. 709 weights)."
get_luminance(c::Color) = 0.2126f0 * c.r + 0.7152f0 * c.g + 0.0722f0 * c.b
_to_linear(x::Float32) = x < 0.04045f0 ? x * (1f0 / 12.92f0) : Float32((x + 0.055) * (1.0 / (1.0 + 0.055)))^2.4f0
_to_srgb(x::Float32) = x < 0.0031308f0 ? 12.92f0 * x : (1f0 + 0.055f0) * x^(1f0 / 2.4f0) - 0.055f0
"`c` converted from sRGB to linear encoding."
srgb_to_linear(c::Color) = Color(_to_linear(c.r), _to_linear(c.g), _to_linear(c.b), c.a)
"`c` converted from linear to sRGB encoding."
linear_to_srgb(c::Color) = Color(_to_srgb(c.r), _to_srgb(c.g), _to_srgb(c.b), c.a)

"Color from a 32-bit RGBA integer."
function hex(::Type{Color}, h::Integer)
    h = UInt32(h & 0xffffffff)
    return Color(((h >> 24) & 0xff) / 255f0, ((h >> 16) & 0xff) / 255f0, ((h >> 8) & 0xff) / 255f0, (h & 0xff) / 255f0)
end
"Color from a 64-bit RGBA integer (16 bits per channel)."
function hex64(::Type{Color}, h::Integer)
    h = reinterpret(UInt64, Int64(h % Int64))
    return Color(((h >> 48) & 0xffff) / 65535f0, ((h >> 32) & 0xffff) / 65535f0, ((h >> 16) & 0xffff) / 65535f0,
                 (h & 0xffff) / 65535f0)
end
"Color from 8-bit channel values (C#: `Color.Color8`)."
from_rgba8(::Type{Color}, r8::Integer, g8::Integer, b8::Integer, a8::Integer = 255) =
    Color(r8 / 255f0, g8 / 255f0, b8 / 255f0, a8 / 255f0)
"Color from an RGBE9995 packed HDR value."
function from_rgbe9995(::Type{Color}, rgbe::Integer)
    r = Float32(rgbe & 0x1ff)
    g = Float32((rgbe >> 9) & 0x1ff)
    b = Float32((rgbe >> 18) & 0x1ff)
    e = Float32((rgbe >> 27) & 0x1f)
    m = 2f0^(e - 15f0 - 9f0)
    return Color(r * m, g * m, b * m, 1)
end

"Color from HSV components in `[0, 1]`."
function from_hsv(::Type{Color}, h::Real, s::Real, v::Real, alpha::Real = 1.0)
    h, s, v = _f32(h), _f32(s), _f32(v)
    s == 0 && return Color(v, v, v, alpha)
    h = rem(h * 6, 6f0)
    i = floor(Int, h)
    f = h - i
    p = v * (1 - s)
    q = v * (1 - s * f)
    t = v * (1 - s * (1 - f))
    i == 0 && return Color(v, t, p, alpha)
    i == 1 && return Color(q, v, p, alpha)
    i == 2 && return Color(p, v, t, alpha)
    i == 3 && return Color(p, q, v, alpha)
    i == 4 && return Color(t, p, v, alpha)
    return Color(v, p, q, alpha)
end
"Color from OKHSL components in `[0, 1]`."
function from_ok_hsl(::Type{Color}, h::Real, s::Real, l::Real, alpha::Real = 1.0)
    r, g, b = OkColor.okhsl_to_srgb(_f32(h), _f32(s), _f32(l))
    return clamp(Color(r, g, b, alpha))
end

_hexval(c::Char) = '0' <= c <= '9' ? Int(c - '0') : 'a' <= c <= 'f' ? Int(c - 'a') + 10 : 'A' <= c <= 'F' ? Int(c - 'A') + 10 : -1
_strip_hash(s::AbstractString) = startswith(s, '#') ? SubString(s, 2) : SubString(s, 1)

"`true` if `code` is a valid HTML color code (3, 4, 6 or 8 hex digits, optional `#`)."
function html_is_valid(::Type{Color}, code::AbstractString)
    s = _strip_hash(code)
    length(s) in (3, 4, 6, 8) || return false
    return all(c -> _hexval(c) >= 0, s)
end
"Color from an HTML code such as `\"#ff8000\"`, `\"f80\"` or `\"ff8000cc\"`; throws `ArgumentError` when invalid."
function html(::Type{Color}, code::AbstractString)
    html_is_valid(Color, code) || throw(ArgumentError("invalid color code: $code"))
    d = [_hexval(c) for c in _strip_hash(code)]
    n = length(d)
    if n <= 4
        return Color(d[1] / 15f0, d[2] / 15f0, d[3] / 15f0, n == 4 ? d[4] / 15f0 : 1f0)
    end
    return Color((16d[1] + d[2]) / 255f0, (16d[3] + d[4]) / 255f0, (16d[5] + d[6]) / 255f0,
                 n == 8 ? (16d[7] + d[8]) / 255f0 : 1f0)
end

"Named color (`\"red\"`, `\"Alice Blue\"`, `\"dark_green\"`), or `nothing`."
function named(::Type{Color}, name::AbstractString)
    key = uppercase(filter(c -> !(c in " -_'."), name))
    return get(_NAMED_COLORS, key, nothing)
end
# Built from the generated `Color_*` constants (Godot's named colors).
const _NAMED_COLORS = Dict{String, Color}(replace(String(n)[7:end], "_" => "") => getglobal(@__MODULE__, n)
                                          for n in names(@__MODULE__; all = true)
                                          if startswith(String(n), "Color_") && getglobal(@__MODULE__, n) isa Color)
"Color from an HTML code or a color name; `default` when neither matches."
function from_string(::Type{Color}, str::AbstractString, default::Color)
    html_is_valid(Color, str) && return html(Color, str)
    return something(named(Color, str), default)
end
