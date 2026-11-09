# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Plane and AABB.
# Ported from Godot's core/math/plane.h/.cpp, aabb.h/.cpp and GodotSharp/Core/Plane.cs, Aabb.cs (MIT, Godot contributors).

Plane() = Plane(Vector3(), 0)
"Plane through the origin with the given `normal`."
Plane(normal::Vector3) = Plane(normal, 0)
"Plane with `normal` passing through `point`."
Plane(normal::Vector3, point::Vector3) = Plane(normal, dot(normal, point))
"Plane through three points (clockwise winding)."
function Plane(p1::Vector3, p2::Vector3, p3::Vector3)
    normal = normalized(cross(p1 - p3, p1 - p2))
    return Plane(normal, dot(normal, p1))
end

Base.:+(p::Plane) = p
Base.:-(p::Plane) = Plane(-p.normal, -p.d)
# `p.x/y/z` are the normal's components (C#: `Plane.X/Y/Z`).
@inline function Base.getproperty(p::Plane, s::Symbol)
    s === :x && return getfield(p, :normal).x
    s === :y && return getfield(p, :normal).y
    s === :z && return getfield(p, :normal).z
    return getfield(p, s)
end
Base.propertynames(::Plane) = (:normal, :d, :x, :y, :z)
Base.:(==)(a::Plane, b::Plane) = a.normal == b.normal && a.d == b.d
Base.show(io::IO, p::Plane) = print(io, "Plane(", p.normal.x, ", ", p.normal.y, ", ", p.normal.z, ", ", p.d, ")")

"`p` with a unit normal (zero plane if the normal is zero)."
function normalized(p::Plane)
    l = length(p.normal)
    return l == 0 ? Plane(0, 0, 0, 0) : Plane(p.normal / l, p.d / l)
end
normalize(p::Plane) = normalized(p)
"Point on the plane closest to the origin."
get_center(p::Plane) = p.normal * p.d
"`true` if `point` is above the plane."
is_point_over(p::Plane, point::Vector3) = dot(p.normal, point) > p.d
"Signed distance from the plane to `point`."
distance_to(p::Plane, point::Vector3) = dot(p.normal, point) - p.d
"`true` if `point` is within `tolerance` of the plane."
has_point(p::Plane, point::Vector3, tolerance::Real = 1e-5) = abs(dot(p.normal, point) - p.d) <= tolerance
"Orthogonal projection of `point` onto the plane."
project(p::Plane, point::Vector3) = point - p.normal * distance_to(p, point)
is_equal_approx(a::Plane, b::Plane) = is_equal_approx(a.normal, b.normal) && is_equal_approx(a.d, b.d)
Base.isapprox(a::Plane, b::Plane; kwargs...) =
    isempty(kwargs) ? is_equal_approx(a, b) : isapprox(a.normal, b.normal; kwargs...) && isapprox(a.d, b.d; kwargs...)
is_finite(p::Plane) = is_finite(p.normal) && isfinite(p.d)

"Intersection point of three planes, or `nothing`."
function intersect_3(a::Plane, b::Plane, c::Plane)
    denom = dot(cross(a.normal, b.normal), c.normal)
    is_zero_approx(denom) && return nothing
    return ((cross(b.normal, c.normal) * a.d) + (cross(c.normal, a.normal) * b.d) + (cross(a.normal, b.normal) * c.d)) / denom
end
"Intersection of the ray from `from` along `dir` with the plane, or `nothing`."
function intersects_ray(p::Plane, from::Vector3, dir::Vector3)
    den = dot(p.normal, dir)
    is_zero_approx(den) && return nothing
    dist = (dot(p.normal, from) - p.d) / den
    dist > CMP_EPSILON && return nothing
    return from + dir * -dist
end
"Intersection of the segment `from`–`to` with the plane, or `nothing`."
function intersects_segment(p::Plane, from::Vector3, to::Vector3)
    segment = from - to
    den = dot(p.normal, segment)
    is_zero_approx(den) && return nothing
    dist = (dot(p.normal, from) - p.d) / den
    (dist < -CMP_EPSILON || dist > 1 + CMP_EPSILON) && return nothing
    return from + segment * -dist
end

AABB() = AABB(Vector3(), Vector3())
Base.:(==)(a::AABB, b::AABB) = a.position == b.position && a.size == b.size
Base.show(io::IO, a::AABB) = print(io, "AABB(", a.position, ", ", a.size, ")")
get_end(a::AABB) = a.position + a.size
@inline function Base.getproperty(a::AABB, s::Symbol)
    s === :end_ && return get_end(a)
    return getfield(a, s)
end
Base.propertynames(::AABB) = (:position, :size, :end_)

Base.abs(a::AABB) = AABB(a.position + min(a.size, Vector3()), abs(a.size))
get_center(a::AABB) = a.position + a.size * 0.5f0
"Volume (`size.x * size.y * size.z`)."
get_volume(a::AABB) = a.size.x * a.size.y * a.size.z
"`true` if every side is positive."
has_volume(a::AABB) = a.size.x > 0 && a.size.y > 0 && a.size.z > 0
"`true` if any side is positive."
has_surface(a::AABB) = a.size.x > 0 || a.size.y > 0 || a.size.z > 0
function has_point(a::AABB, p::Vector3)
    (p.x < a.position.x || p.y < a.position.y || p.z < a.position.z) && return false
    (p.x > a.position.x + a.size.x || p.y > a.position.y + a.size.y || p.z > a.position.z + a.size.z) && return false
    return true
end
is_equal_approx(a::AABB, b::AABB) = is_equal_approx(a.position, b.position) && is_equal_approx(a.size, b.size)
Base.isapprox(a::AABB, b::AABB; kwargs...) = isapprox(a.position, b.position; kwargs...) && isapprox(a.size, b.size; kwargs...)
is_finite(a::AABB) = is_finite(a.position) && is_finite(a.size)

function intersects(a::AABB, b::AABB)
    for i in 1:3
        a.position[i] >= b.position[i] + b.size[i] && return false
        a.position[i] + a.size[i] <= b.position[i] && return false
    end
    return true
end
function encloses(a::AABB, b::AABB)
    smin, smax = a.position, a.position + a.size
    dmin, dmax = b.position, b.position + b.size
    return smin.x <= dmin.x && smax.x >= dmax.x && smin.y <= dmin.y && smax.y >= dmax.y && smin.z <= dmin.z &&
           smax.z >= dmax.z
end
"`true` if the box has corners on both sides of `plane`."
function intersects_plane(a::AABB, plane::Plane)
    over = under = false
    for i in 0:7
        distance_to(plane, get_endpoint(a, i)) > 0 ? (over = true) : (under = true)
    end
    return under && over
end
function intersection(a::AABB, b::AABB)
    smin, smax = a.position, a.position + a.size
    dmin, dmax = b.position, b.position + b.size
    for i in 1:3
        (smin[i] > dmax[i] || smax[i] < dmin[i]) && return AABB()
    end
    lo = max(smin, dmin)
    return AABB(lo, min(smax, dmax) - lo)
end
function Base.merge(a::AABB, b::AABB)
    lo = min(a.position, b.position)
    return AABB(lo, max(a.position + a.size, b.position + b.size) - lo)
end
function expand(a::AABB, p::Vector3)
    b = min(a.position, p)
    return AABB(b, max(a.position + a.size, p) - b)
end
"`a` grown by `by` on every side."
grow(a::AABB, by::Real) = AABB(a.position - Vector3(by, by, by), a.size + Vector3(by, by, by) * 2)
get_support(a::AABB, d::Vector3) = Vector3(a.position.x + (d.x > 0 ? a.size.x : zero(real_t)),
                                          a.position.y + (d.y > 0 ? a.size.y : zero(real_t)),
                                          a.position.z + (d.z > 0 ? a.size.z : zero(real_t)))

function _longest(a::AABB)
    i, m = 0, a.size.x
    a.size.y > m && ((i, m) = (1, a.size.y))
    a.size.z > m && ((i, m) = (2, a.size.z))
    return i, m
end
function _shortest(a::AABB)
    i, m = 0, a.size.x
    a.size.y < m && ((i, m) = (1, a.size.y))
    a.size.z < m && ((i, m) = (2, a.size.z))
    return i, m
end
_unit_axis(i) = Vector3(i == 0, i == 1, i == 2)
"Unit vector of the longest side."
get_longest_axis(a::AABB) = _unit_axis(_longest(a)[1])
"Index (0, 1 or 2) of the longest side."
get_longest_axis_index(a::AABB) = _longest(a)[1]
"Length of the longest side."
get_longest_axis_size(a::AABB) = _longest(a)[2]
"Unit vector of the shortest side."
get_shortest_axis(a::AABB) = _unit_axis(_shortest(a)[1])
"Index (0, 1 or 2) of the shortest side."
get_shortest_axis_index(a::AABB) = _shortest(a)[1]
"Length of the shortest side."
get_shortest_axis_size(a::AABB) = _shortest(a)[2]

"Corner `idx` (0–7; bit 2 = +X, bit 1 = +Y, bit 0 = +Z)."
function get_endpoint(a::AABB, idx::Integer)
    0 <= idx <= 7 || throw(BoundsError(a, idx))
    p, s = a.position, a.size
    z = zero(real_t)
    return Vector3(p.x + (idx & 4 != 0 ? s.x : z), p.y + (idx & 2 != 0 ? s.y : z), p.z + (idx & 1 != 0 ? s.z : z))
end

"Entry point of the segment `from`–`to` into the box, or `nothing`."
function intersects_segment(a::AABB, from::Vector3, to::Vector3)
    lo, hi = zero(real_t), one(real_t)
    for i in 1:3
        sf, st = from[i], to[i]
        bb = a.position[i]
        be = bb + a.size[i]
        if sf < st
            (sf > be || st < bb) && return nothing
            len = st - sf
            cmin = sf < bb ? (bb - sf) / len : zero(real_t)
            cmax = st > be ? (be - sf) / len : one(real_t)
        else
            (st > be || sf < bb) && return nothing
            len = st - sf
            cmin = sf > be ? (be - sf) / len : zero(real_t)
            cmax = st < bb ? (bb - sf) / len : one(real_t)
        end
        cmin > lo && (lo = cmin)
        cmax < hi && (hi = cmax)
        hi < lo && return nothing
    end
    return from + (to - from) * lo
end

"Entry point of the ray from `from` along `dir` into the box (`from` itself when starting inside), or `nothing`."
function intersects_ray(a::AABB, from::Vector3, dir::Vector3)
    e = a.position + a.size
    tmin, tmax = real_t(-1e20), real_t(1e20)
    for i in 1:3
        if dir[i] == 0
            (from[i] < a.position[i] || from[i] > e[i]) && return nothing
        else
            t1 = (a.position[i] - from[i]) / dir[i]
            t2 = (e[i] - from[i]) / dir[i]
            t1 > t2 && ((t1, t2) = (t2, t1))
            t1 >= tmin && (tmin = t1)
            if t2 < tmax
                t2 < 0 && return nothing
                tmax = t2
            end
            tmin > tmax && return nothing
        end
    end
    return tmin < 0 ? from : from + dir * tmin
end
