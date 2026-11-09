# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Transform2D (columns x, y and origin).
# Ported from Godot's core/math/transform_2d.h/.cpp and GodotSharp/Core/Transform2D.cs (MIT, Godot contributors).

Transform2D() = Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(0, 0))
Base.one(::Type{Transform2D}) = Transform2D()
"Transform rotating by `rotation` radians and translating by `position`."
function Transform2D(rotation::Real, position::Vector2)
    s, c = sincos(_rt(rotation))
    return Transform2D(Vector2(c, s), Vector2(-s, c), position)
end
"Transform from rotation, scale, skew (radians) and position."
function Transform2D(rotation::Real, scale::Vector2, skew::Real, position::Vector2)
    r = _rt(rotation)
    k = _rt(skew)
    return Transform2D(Vector2(cos(r) * scale.x, sin(r) * scale.x), Vector2(-sin(r + k) * scale.y, cos(r + k) * scale.y),
                       position)
end

Base.:(==)(a::Transform2D, b::Transform2D) = a.x == b.x && a.y == b.y && a.origin == b.origin
Base.show(io::IO, t::Transform2D) =
    print(io, "Transform2D(", t.x.x, ", ", t.x.y, ", ", t.y.x, ", ", t.y.y, ", ", t.origin.x, ", ", t.origin.y, ")")
Base.@propagate_inbounds Base.getindex(t::Transform2D, i::Integer) =
    (@boundscheck 1 <= i <= 3 || throw(BoundsError(t, i)); getfield(t, Int(i)))

@inline _tdotx(t::Transform2D, v::Vector2) = t.x.x * v.x + t.y.x * v.y
@inline _tdoty(t::Transform2D, v::Vector2) = t.x.y * v.x + t.y.y * v.y

"`v` transformed by the basis of `t` only (no translation)."
basis_xform(t::Transform2D, v::Vector2) = Vector2(_tdotx(t, v), _tdoty(t, v))
"`v` transformed by the inverse basis of `t`, assuming the basis is orthonormal."
basis_xform_inv(t::Transform2D, v::Vector2) = Vector2(dot(t.x, v), dot(t.y, v))
_xform(t::Transform2D, v::Vector2) = basis_xform(t, v) + t.origin
_xform_inv(t::Transform2D, v::Vector2) = (d = v - t.origin; Vector2(dot(t.x, d), dot(t.y, d)))

function _xform(t::Transform2D, r::Rect2)
    x = t.x * r.size.x
    y = t.y * r.size.y
    pos = _xform(t, r.position)
    nr = Rect2(pos, Vector2())
    nr = expand(nr, pos + x)
    nr = expand(nr, pos + y)
    return expand(nr, pos + x + y)
end
function _xform_inv(t::Transform2D, r::Rect2)
    p, s = r.position, r.size
    nr = Rect2(_xform_inv(t, p), Vector2())
    nr = expand(nr, _xform_inv(t, Vector2(p.x, p.y + s.y)))
    nr = expand(nr, _xform_inv(t, Vector2(p.x + s.x, p.y + s.y)))
    return expand(nr, _xform_inv(t, Vector2(p.x + s.x, p.y)))
end

Base.:*(t::Transform2D, v::Vector2) = _xform(t, v)
Base.:*(v::Vector2, t::Transform2D) = _xform_inv(t, v)
Base.:*(t::Transform2D, r::Rect2) = _xform(t, r)
Base.:*(r::Rect2, t::Transform2D) = _xform_inv(t, r)
function Base.:*(a::Transform2D, b::Transform2D)
    return Transform2D(Vector2(_tdotx(a, b.x), _tdoty(a, b.x)), Vector2(_tdotx(a, b.y), _tdoty(a, b.y)), _xform(a, b.origin))
end
Base.:*(t::Transform2D, s::Real) = Transform2D(t.x * s, t.y * s, t.origin * s)
Base.:*(s::Real, t::Transform2D) = t * s
Base.:/(t::Transform2D, s::Real) = Transform2D(t.x / s, t.y / s, t.origin / s)

"Determinant of the basis."
determinant(t::Transform2D) = t.x.x * t.y.y - t.x.y * t.y.x
det(t::Transform2D) = determinant(t)
"Inverse assuming an orthonormal basis (rotation and translation only); see `affine_inverse`."
function inverse(t::Transform2D)
    b = Transform2D(Vector2(t.x.x, t.y.x), Vector2(t.x.y, t.y.y), Vector2())
    return Transform2D(b.x, b.y, basis_xform(b, -t.origin))
end
"Inverse of any invertible transform (including scale and skew)."
function affine_inverse(t::Transform2D)
    idet = 1 / determinant(t)
    b = Transform2D(Vector2(t.y.y * idet, -t.x.y * idet), Vector2(-t.y.x * idet, t.x.x * idet), Vector2())
    return Transform2D(b.x, b.y, basis_xform(b, -t.origin))
end
Base.inv(t::Transform2D) = affine_inverse(t)

"Rotation in radians."
get_rotation(t::Transform2D) = atan(t.x.y, t.x.x)
"Translation."
get_origin(t::Transform2D) = t.origin
"Scale (negative Y when the basis is flipped)."
get_scale(t::Transform2D) = Vector2(length(t.x), _sign(determinant(t)) * length(t.y))
"Skew in radians."
get_skew(t::Transform2D) =
    _acos(dot(normalized(t.x), _sign(determinant(t)) * normalized(t.y))) - real_t(π) * 0.5f0

@inline function Base.getproperty(t::Transform2D, s::Symbol)
    s === :rotation && return get_rotation(t)
    s === :scale && return get_scale(t)
    s === :skew && return get_skew(t)
    return getfield(t, s)
end
Base.propertynames(::Transform2D) = (:x, :y, :origin, :rotation, :scale, :skew)

"`t` with an orthonormalized basis (Gram-Schmidt)."
function orthonormalized(t::Transform2D)
    x = normalized(t.x)
    y = normalized(t.y - x * dot(x, t.y))
    return Transform2D(x, y, t.origin)
end
"`t` rotated by `angle` radians in parent (global) space."
rotated(t::Transform2D, angle::Real) = Transform2D(angle, Vector2()) * t
"`t` rotated by `angle` radians in local space."
rotated_local(t::Transform2D, angle::Real) = t * Transform2D(angle, Vector2())
"`t` scaled in parent space (basis and origin)."
scaled(t::Transform2D, s::Vector2) = Transform2D(t.x * s, t.y * s, t.origin * s)
"`t` scaled in local space."
scaled_local(t::Transform2D, s::Vector2) = Transform2D(t.x * s.x, t.y * s.y, t.origin)
"`t` translated in parent space."
translated(t::Transform2D, offset::Vector2) = Transform2D(t.x, t.y, t.origin + offset)
"`t` translated in local space."
translated_local(t::Transform2D, offset::Vector2) = Transform2D(t.x, t.y, t.origin + basis_xform(t, offset))

"Interpolation of rotation, scale, skew and origin toward `b`."
interpolate_with(a::Transform2D, b::Transform2D, weight::Real) =
    Transform2D(_lerp_angle(get_rotation(a), get_rotation(b), weight), lerp(get_scale(a), get_scale(b), weight),
                _lerp_angle(get_skew(a), get_skew(b), weight), lerp(get_origin(a), get_origin(b), weight))

"`true` if the basis is a uniform scale combined with a rotation (possibly flipped)."
function is_conformal(t::Transform2D)
    is_equal_approx(t.x.x, t.y.y) && is_equal_approx(t.x.y, -t.y.x) && return true
    is_equal_approx(t.x.x, -t.y.y) && is_equal_approx(t.x.y, t.y.x) && return true
    return false
end
is_equal_approx(a::Transform2D, b::Transform2D) =
    is_equal_approx(a.x, b.x) && is_equal_approx(a.y, b.y) && is_equal_approx(a.origin, b.origin)
Base.isapprox(a::Transform2D, b::Transform2D; kwargs...) =
    isapprox(a.x, b.x; kwargs...) && isapprox(a.y, b.y; kwargs...) && isapprox(a.origin, b.origin; kwargs...)
is_finite(t::Transform2D) = is_finite(t.x) && is_finite(t.y) && is_finite(t.origin)

"`t` rotated so its X axis points toward `target`, keeping origin and dropping scale/skew."
function looking_at(t::Transform2D, target::Vector2 = Vector2())
    target_position = _xform(affine_inverse(t), target)
    return Transform2D(get_rotation(t) + angle(target_position * get_scale(t)), get_origin(t))
end
