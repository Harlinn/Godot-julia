# Quaternion.
# Ported from Godot's core/math/quaternion.h/.cpp and GodotSharp/Core/Quaternion.cs (MIT, Godot contributors).

Quaternion() = Quaternion(0, 0, 0, 1)
Base.one(::Type{Quaternion}) = Quaternion()

"Rotation of `angle` radians around `axis` (normalized)."
function Quaternion(axis::Vector3, angle::Real)
    d = length(axis)
    d == 0 && return Quaternion(0, 0, 0, 0)
    s, c = sincos(_rt(angle) * 0.5f0)
    s /= d
    return Quaternion(axis.x * s, axis.y * s, axis.z * s, c)
end

"Shortest-arc rotation taking direction `arc_from` to `arc_to`."
function Quaternion(arc_from::Vector3, arc_to::Vector3)
    n0 = normalized(arc_from)
    n1 = normalized(arc_to)
    d = dot(n0, n1)
    if abs(d) > 1 - CMP_EPSILON
        d >= 0 && return Quaternion()
        axis = _any_perpendicular(n0)
        return Quaternion(axis.x, axis.y, axis.z, 0)
    end
    c = cross(n0, n1)
    s = sqrt((1 + d) * 2)
    rs = 1 / s
    return normalized(Quaternion(c.x * rs, c.y * rs, c.z * rs, s * 0.5f0))
end

const _QF = (:x, :y, :z, :w)
Base.:+(q::Quaternion) = q
Base.:-(q::Quaternion) = Quaternion(-q.x, -q.y, -q.z, -q.w)
Base.:+(a::Quaternion, b::Quaternion) = Quaternion(a.x + b.x, a.y + b.y, a.z + b.z, a.w + b.w)
Base.:-(a::Quaternion, b::Quaternion) = Quaternion(a.x - b.x, a.y - b.y, a.z - b.z, a.w - b.w)
Base.:*(q::Quaternion, s::Real) = (s = _rt(s); Quaternion(q.x * s, q.y * s, q.z * s, q.w * s))
Base.:*(s::Real, q::Quaternion) = q * s
Base.:/(q::Quaternion, s::Real) = q * (1 / _rt(s))
Base.:(==)(a::Quaternion, b::Quaternion) = a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w
Base.show(io::IO, q::Quaternion) = print(io, "Quaternion(", q.x, ", ", q.y, ", ", q.z, ", ", q.w, ")")
Base.@propagate_inbounds Base.getindex(q::Quaternion, i::Integer) =
    (@boundscheck 1 <= i <= 4 || throw(BoundsError(q, i)); getfield(q, Int(i)))
function Base.:*(a::Quaternion, b::Quaternion)
    return Quaternion(a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y, a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z,
                      a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x, a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
end
function _xform(q::Quaternion, v::Vector3)
    u = Vector3(q.x, q.y, q.z)
    uv = cross(u, v)
    return v + ((uv * q.w) + cross(u, uv)) * 2
end
Base.:*(q::Quaternion, v::Vector3) = _xform(q, v)
Base.:*(v::Vector3, q::Quaternion) = _xform(inverse(q), v)

dot(a::Quaternion, b::Quaternion) = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
length_squared(q::Quaternion) = dot(q, q)
Base.length(q::Quaternion) = sqrt(length_squared(q))
norm(q::Quaternion) = length(q)
normalized(q::Quaternion) = q / length(q)
normalize(q::Quaternion) = normalized(q)
is_normalized(q::Quaternion) = is_equal_approx(length_squared(q), 1, UNIT_EPSILON)
"Inverse rotation (the conjugate; `q` must be normalized)."
inverse(q::Quaternion) = Quaternion(-q.x, -q.y, -q.z, q.w)
Base.inv(q::Quaternion) = inverse(q)
is_equal_approx(a::Quaternion, b::Quaternion) =
    is_equal_approx(a.x, b.x) && is_equal_approx(a.y, b.y) && is_equal_approx(a.z, b.z) && is_equal_approx(a.w, b.w)
Base.isapprox(a::Quaternion, b::Quaternion; kwargs...) =
    isempty(kwargs) ? is_equal_approx(a, b) : all(isapprox(getfield(a, f), getfield(b, f); kwargs...) for f in _QF)
is_finite(q::Quaternion) = isfinite(q.x) && isfinite(q.y) && isfinite(q.z) && isfinite(q.w)

"Rotation axis (unnormalized when the rotation is near zero)."
function get_axis(q::Quaternion)
    abs(q.w) > 1 - CMP_EPSILON && return Vector3(q.x, q.y, q.z)
    r = 1 / sqrt(1 - q.w * q.w)
    return Vector3(q.x * r, q.y * r, q.z * r)
end
"Rotation angle in radians."
get_angle(q::Quaternion) = 2 * _acos(q.w)
"Logarithm: the rotation as a pure quaternion `(axis * angle, 0)`."
Base.log(q::Quaternion) = (v = get_axis(q) * get_angle(q); Quaternion(v.x, v.y, v.z, 0))
"Exponential: inverse of `log`."
function Base.exp(q::Quaternion)
    v = Vector3(q.x, q.y, q.z)
    theta = length(v)
    v = normalized(v)
    (theta < CMP_EPSILON || !is_normalized(v)) && return Quaternion()
    return Quaternion(v, theta)
end
"Angle in radians between two rotations."
angle_to(a::Quaternion, b::Quaternion) = (d = dot(a, b); _acos(d * d * 2 - 1))

"Spherical linear interpolation toward `to` (both normalized)."
function slerp(a::Quaternion, to::Quaternion, weight::Real)
    cosom = dot(a, to)
    to1 = to
    if cosom < 0
        cosom = -cosom
        to1 = -to
    end
    if 1 - cosom > CMP_EPSILON
        omega = acos(cosom)
        sinom = sin(omega)
        scale0 = sin((1.0 - weight) * omega) / sinom
        scale1 = sin(weight * omega) / sinom
    else
        scale0 = 1.0 - weight
        scale1 = Float64(weight)
    end
    return Quaternion(scale0 * a.x + scale1 * to1.x, scale0 * a.y + scale1 * to1.y, scale0 * a.z + scale1 * to1.z,
                      scale0 * a.w + scale1 * to1.w)
end

"Spherical linear interpolation without the shortest-path check."
function slerpni(a::Quaternion, to::Quaternion, weight::Real)
    d = dot(a, to)
    abs(d) > 0.9999f0 && return a
    theta = acos(d)
    sin_t = 1 / sin(theta)
    new_factor = sin(weight * theta) * sin_t
    inv_factor = sin((1 - weight) * theta) * sin_t
    return Quaternion(inv_factor * a.x + new_factor * to.x, inv_factor * a.y + new_factor * to.y,
                      inv_factor * a.z + new_factor * to.z, inv_factor * a.w + new_factor * to.w)
end

function _squad_prepare(a::Quaternion, b::Quaternion, pre_a::Quaternion, post_b::Quaternion)
    from_q = get_rotation_quaternion(Basis(a))
    pre_q = get_rotation_quaternion(Basis(pre_a))
    to_q = get_rotation_quaternion(Basis(b))
    post_q = get_rotation_quaternion(Basis(post_b))
    signbit(dot(from_q, pre_q)) && (pre_q = -pre_q)
    flip2 = signbit(dot(from_q, to_q))
    flip2 && (to_q = -to_q)
    (flip2 ? dot(to_q, post_q) <= 0 : signbit(dot(to_q, post_q))) && (post_q = -post_q)
    return from_q, to_q, pre_q, post_q
end

function _squad(interp, a::Quaternion, b::Quaternion, pre_a::Quaternion, post_b::Quaternion, weight::Real)
    from_q, to_q, pre_q, post_q = _squad_prepare(a, b, pre_a, post_b)
    zero_q = Quaternion(0, 0, 0, 0)
    blend(f, t, p, o) = Quaternion(interp(f.x, t.x, p.x, o.x), interp(f.y, t.y, p.y, o.y), interp(f.z, t.z, p.z, o.z), 0)
    inv_from = inverse(from_q)
    q1 = from_q * exp(blend(zero_q, log(inv_from * to_q), log(inv_from * pre_q), log(inv_from * post_q)))
    inv_to = inverse(to_q)
    q2 = to_q * exp(blend(log(inv_to * from_q), zero_q, log(inv_to * pre_q), log(inv_to * post_q)))
    return slerp(q1, q2, weight)
end

"Spherical cubic interpolation toward `b` using the neighbors `pre_a` and `post_b`."
spherical_cubic_interpolate(a::Quaternion, b::Quaternion, pre_a::Quaternion, post_b::Quaternion, weight::Real) =
    _squad((f, t, p, o) -> cubic_interpolate(f, t, p, o, weight), a, b, pre_a, post_b, weight)

"Like `spherical_cubic_interpolate`, with explicit time values for the points."
function spherical_cubic_interpolate_in_time(a::Quaternion, b::Quaternion, pre_a::Quaternion, post_b::Quaternion,
                                             weight::Real, b_t::Real, pre_a_t::Real, post_b_t::Real)
    return _squad((f, t, p, o) -> cubic_interpolate_in_time(f, t, p, o, weight, b_t, pre_a_t, post_b_t), a, b, pre_a,
                  post_b, weight)
end

"Euler angles (radians) of the rotation for the given `EulerOrder`."
get_euler(q::Quaternion, order::Union{EulerOrder, Integer} = EULER_ORDER_YXZ) = get_euler(Basis(q), order)

"Rotation from YXZ Euler angles in radians (C#: `Quaternion.FromEuler`)."
function from_euler(::Type{Quaternion}, euler::Vector3)
    s1, c1 = sincos(euler.y * 0.5f0)
    s2, c2 = sincos(euler.x * 0.5f0)
    s3, c3 = sincos(euler.z * 0.5f0)
    return Quaternion(s1 * c2 * s3 + c1 * s2 * c3, s1 * c2 * c3 - c1 * s2 * s3, -s1 * s2 * c3 + c1 * c2 * s3,
                      s1 * s2 * s3 + c1 * c2 * c3)
end
