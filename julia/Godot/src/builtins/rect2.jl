# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Rect2 and Rect2i.
# Ported from Godot's core/math/rect2.h/.cpp, rect2i.h and GodotSharp/Core/Rect2.cs, Rect2I.cs (MIT, Godot contributors).

for (R, V, S) in ((:Rect2, :Vector2, :Real), (:Rect2i, :Vector2i, :Integer))
    @eval begin
        $R() = $R($V(), $V())
        Base.:(==)(a::$R, b::$R) = a.position == b.position && a.size == b.size
        Base.show(io::IO, r::$R) = print(io, $(string(R)), "(", r.position.x, ", ", r.position.y, ", ", r.size.x, ", ", r.size.y, ")")
        "Ending corner (`position + size`); C#: `End`. Also available as the property `r.end_`."
        get_end(r::$R) = r.position + r.size
        @inline function Base.getproperty(r::$R, s::Symbol)
            s === :end_ && return get_end(r)
            return getfield(r, s)
        end
        Base.propertynames(::$R) = (:position, :size, :end_)
        "Area (`size.x * size.y`)."
        get_area(r::$R) = r.size.x * r.size.y
        "`true` if width and height are both positive."
        has_area(r::$R) = r.size.x > 0 && r.size.y > 0
        "`true` if `b` lies completely inside `a`."
        encloses(a::$R, b::$R) = b.position.x >= a.position.x && b.position.y >= a.position.y &&
                                 b.position.x + b.size.x <= a.position.x + a.size.x &&
                                 b.position.y + b.size.y <= a.position.y + a.size.y
        "Intersection of `a` and `b`, or an empty rect when they do not intersect."
        function intersection(a::$R, b::$R)
            intersects(a, b) || return $R()
            pos = max(b.position, a.position)
            return $R(pos, min(b.position + b.size, a.position + a.size) - pos)
        end
        "Smallest rect enclosing both `a` and `b` (Base `merge`)."
        function Base.merge(a::$R, b::$R)
            pos = min(b.position, a.position)
            return $R(pos, max(b.position + b.size, a.position + a.size) - pos)
        end
        "`r` expanded to include `to`."
        function expand(r::$R, to::$V)
            b = r.position
            e = r.position + r.size
            b = $V(_min(b.x, to.x), _min(b.y, to.y))
            e = $V(_max(e.x, to.x), _max(e.y, to.y))
            return $R(b, e - b)
        end
        "`r` grown by `amount` on every side."
        grow(r::$R, amount::$S) = grow_individual(r, amount, amount, amount, amount)
        "`r` grown by the given amounts on each side."
        grow_individual(r::$R, left::$S, top::$S, right::$S, bottom::$S) =
            $R(r.position.x - left, r.position.y - top, r.size.x + left + right, r.size.y + top + bottom)
        "`r` grown by `amount` on `side` (a `Side` value)."
        grow_side(r::$R, side::Union{Side, Integer}, amount::$S) =
            (s = Internals.enum_value(side);
             grow_individual(r, s == 0 ? amount : zero(amount), s == 1 ? amount : zero(amount),
                             s == 2 ? amount : zero(amount), s == 3 ? amount : zero(amount)))
        "Equivalent rect with non-negative size."
        Base.abs(r::$R) = $R(r.position + min(r.size, $V()), abs(r.size))
    end
end

Rect2(r::Rect2i) = Rect2(Vector2(r.position), Vector2(r.size))
Rect2i(r::Rect2) = Rect2i(Vector2i(r.position), Vector2i(r.size))

get_center(r::Rect2) = r.position + r.size * 0.5f0
get_center(r::Rect2i) = r.position + r.size / 2

"`true` if `point` is inside `r` (the ending edges are excluded)."
function has_point(r::Rect2, p::Vector2)
    (p.x < r.position.x || p.y < r.position.y) && return false
    (p.x >= r.position.x + r.size.x || p.y >= r.position.y + r.size.y) && return false
    return true
end
function has_point(r::Rect2i, p::Vector2i)
    (p.x < r.position.x || p.y < r.position.y) && return false
    (p.x >= r.position.x + r.size.x || p.y >= r.position.y + r.size.y) && return false
    return true
end

"`true` if the rects overlap; edges count when `include_borders` is set."
function intersects(a::Rect2, b::Rect2, include_borders::Bool = false)
    if include_borders
        a.position.x > b.position.x + b.size.x && return false
        a.position.x + a.size.x < b.position.x && return false
        a.position.y > b.position.y + b.size.y && return false
        a.position.y + a.size.y < b.position.y && return false
    else
        a.position.x >= b.position.x + b.size.x && return false
        a.position.x + a.size.x <= b.position.x && return false
        a.position.y >= b.position.y + b.size.y && return false
        a.position.y + a.size.y <= b.position.y && return false
    end
    return true
end
function intersects(a::Rect2i, b::Rect2i)
    a.position.x >= b.position.x + b.size.x && return false
    a.position.x + a.size.x <= b.position.x && return false
    a.position.y >= b.position.y + b.size.y && return false
    a.position.y + a.size.y <= b.position.y && return false
    return true
end

"Vertex of `r` furthest in `direction`."
get_support(r::Rect2, d::Vector2) =
    Vector2(r.position.x + (d.x > 0 ? r.size.x : zero(real_t)), r.position.y + (d.y > 0 ? r.size.y : zero(real_t)))
is_equal_approx(a::Rect2, b::Rect2) = is_equal_approx(a.position, b.position) && is_equal_approx(a.size, b.size)
Base.isapprox(a::Rect2, b::Rect2; kwargs...) =
    isapprox(a.position, b.position; kwargs...) && isapprox(a.size, b.size; kwargs...)
is_finite(r::Rect2) = is_finite(r.position) && is_finite(r.size)
