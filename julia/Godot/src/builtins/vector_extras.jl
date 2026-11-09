# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Members specific to Vector2 and Vector3.
# Ported from Godot's core/math/vector2.cpp, vector3.cpp and GodotSharp/Core/Vector2.cs, Vector3.cs (MIT, Godot contributors).

"Angle of the vector relative to the positive X axis, in radians."
Base.angle(a::Vector2) = atan(a.y, a.x)
"Unit vector rotated `angle` radians from the positive X axis (C#: `Vector2.FromAngle`)."
from_angle(::Type{Vector2}, angle::Real) = Vector2(cos(angle), sin(angle))
"2D cross product (the Z component of the 3D cross product)."
cross(a::Vector2, b::Vector2) = a.x * b.y - a.y * b.x
"Signed angle from `a` to `b`, in radians."
angle_to(a::Vector2, b::Vector2) = atan(cross(a, b), dot(a, b))
"Angle of the line from `a` to `b`, in radians."
angle_to_point(a::Vector2, b::Vector2) = angle(b - a)
"`a` rotated by `angle` radians."
function rotated(a::Vector2, angle::Real)
    s, c = sincos(_rt(angle))
    return Vector2(a.x * c - a.y * s, a.x * s + a.y * c)
end
"Perpendicular vector rotated 90° counter-clockwise (in Godot's Y-down 2D: clockwise on screen)."
orthogonal(a::Vector2) = Vector2(a.y, -a.x)

"Spherical interpolation: rotates toward `to` while interpolating the length."
function slerp(a::Vector2, to::Vector2, weight::Real)
    start_sq = length_squared(a)
    end_sq = length_squared(to)
    (start_sq == 0 || end_sq == 0) && return lerp(a, to, weight)
    start_len = sqrt(start_sq)
    result_len = lerp(start_len, sqrt(end_sq), _rt(weight))
    return rotated(a, angle_to(a, to) * weight) * (result_len / start_len)
end

cross(a::Vector3, b::Vector3) = Vector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
"Unsigned angle between `a` and `b`, in radians."
angle_to(a::Vector3, b::Vector3) = atan(length(cross(a, b)), dot(a, b))
"Angle between `a` and `b`, negative when the rotation is clockwise around `axis`."
function signed_angle_to(a::Vector3, b::Vector3, axis::Vector3)
    c = cross(a, b)
    unsigned = atan(length(c), dot(a, b))
    return dot(c, axis) < 0 ? -unsigned : unsigned
end
"Outer product, as a `Basis` whose rows are `a.x * b`, `a.y * b`, `a.z * b`."
outer(a::Vector3, b::Vector3) = Basis(Internals.ROWS, a.x * b, a.y * b, a.z * b)
"`a` rotated around the normalized `axis` by `angle` radians."
rotated(a::Vector3, axis::Vector3, angle::Real) = Basis(axis, angle) * a

function slerp(a::Vector3, to::Vector3, weight::Real)
    start_sq = length_squared(a)
    end_sq = length_squared(to)
    (start_sq == 0 || end_sq == 0) && return lerp(a, to, weight)
    axis = cross(a, to)
    axis_sq = length_squared(axis)
    axis_sq == 0 && return lerp(a, to, weight)
    axis /= sqrt(axis_sq)
    start_len = sqrt(start_sq)
    result_len = lerp(start_len, sqrt(end_sq), _rt(weight))
    return rotated(a, axis, angle_to(a, to) * weight) * (result_len / start_len)
end

"Octahedral encoding of a normalized vector into `[0, 1]²`."
function octahedron_encode(a::Vector3)
    n = a / (abs(a.x) + abs(a.y) + abs(a.z))
    if n.z >= 0
        ox, oy = n.x, n.y
    else
        ox = (1 - abs(n.y)) * (n.x >= 0 ? 1 : -1)
        oy = (1 - abs(n.x)) * (n.y >= 0 ? 1 : -1)
    end
    return Vector2(ox * 0.5f0 + 0.5f0, oy * 0.5f0 + 0.5f0)
end

"Inverse of `octahedron_encode` (C#: `Vector3.OctahedronDecode`)."
function octahedron_decode(::Type{Vector3}, uv::Vector2)
    fx = uv.x * 2 - 1
    fy = uv.y * 2 - 1
    nz = 1 - abs(fx) - abs(fy)
    t = _clamp(-nz, zero(nz), one(nz))
    return normalized(Vector3(fx + (fx >= 0 ? -t : t), fy + (fy >= 0 ? -t : t), nz))
end

# Vector3::get_any_perpendicular (engine-internal).
_any_perpendicular(a::Vector3) =
    normalized(cross(a, abs(a.x) <= abs(a.y) && abs(a.x) <= abs(a.z) ? Vector3(1, 0, 0) : Vector3(0, 1, 0)))
