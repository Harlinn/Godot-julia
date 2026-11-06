# Basis: stored as rows (memory layout); `b.x`, `b.y`, `b.z` and `Basis(x, y, z)` are the columns, as in GDScript and C#.
# Ported from Godot's core/math/basis.h/.cpp and GodotSharp/Core/Basis.cs (MIT, Godot contributors).

"Basis from its column vectors (the X, Y and Z axes)."
Basis(x::Vector3, y::Vector3, z::Vector3) = Basis(Internals.ROWS, Vector3(x.x, y.x, z.x), Vector3(x.y, y.y, z.y), Vector3(x.z, y.z, z.z))
Basis() = Basis(Internals.ROWS, Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1))
Base.one(::Type{Basis}) = Basis()

@inline _r(b::Basis, i::Int) = getfield(b, i)
"Column `i` (1-based) of `b`."
get_column(b::Basis, i::Integer) = Vector3(b.row0[i], b.row1[i], b.row2[i])
"Row `i` (1-based) of `b`."
get_row(b::Basis, i::Integer) = getfield(b, Int(i))

@inline function Base.getproperty(b::Basis, s::Symbol)
    s === :x && return Vector3(getfield(b, :row0).x, getfield(b, :row1).x, getfield(b, :row2).x)
    s === :y && return Vector3(getfield(b, :row0).y, getfield(b, :row1).y, getfield(b, :row2).y)
    s === :z && return Vector3(getfield(b, :row0).z, getfield(b, :row1).z, getfield(b, :row2).z)
    s === :scale && return get_scale(b)
    return getfield(b, s)
end
Base.propertynames(::Basis) = (:x, :y, :z, :row0, :row1, :row2, :scale)
"`b[i, j]`: row `i`, column `j` (1-based, matrix convention)."
Base.@propagate_inbounds Base.getindex(b::Basis, i::Integer, j::Integer) = getfield(b, Int(i))[j]

Base.:(==)(a::Basis, b::Basis) = a.row0 == b.row0 && a.row1 == b.row1 && a.row2 == b.row2
Base.show(io::IO, b::Basis) = print(io, "Basis(", b.x, ", ", b.y, ", ", b.z, ")")

"Column 1 of `b` dotted with `v`."
tdotx(b::Basis, v::Vector3) = b.row0.x * v.x + b.row1.x * v.y + b.row2.x * v.z
"Column 2 of `b` dotted with `v`."
tdoty(b::Basis, v::Vector3) = b.row0.y * v.x + b.row1.y * v.y + b.row2.y * v.z
"Column 3 of `b` dotted with `v`."
tdotz(b::Basis, v::Vector3) = b.row0.z * v.x + b.row1.z * v.y + b.row2.z * v.z

_xform(b::Basis, v::Vector3) = Vector3(dot(b.row0, v), dot(b.row1, v), dot(b.row2, v))
_xform_inv(b::Basis, v::Vector3) = Vector3(tdotx(b, v), tdoty(b, v), tdotz(b, v))
Base.:*(b::Basis, v::Vector3) = _xform(b, v)
Base.:*(v::Vector3, b::Basis) = _xform_inv(b, v)
function Base.:*(a::Basis, m::Basis)
    r(row) = Vector3(tdotx(m, row), tdoty(m, row), tdotz(m, row))
    return Basis(Internals.ROWS, r(a.row0), r(a.row1), r(a.row2))
end
Base.:*(b::Basis, s::Real) = Basis(Internals.ROWS, b.row0 * s, b.row1 * s, b.row2 * s)
Base.:*(s::Real, b::Basis) = b * s
Base.:/(b::Basis, s::Real) = Basis(Internals.ROWS, b.row0 / s, b.row1 / s, b.row2 / s)

"Rotation of `angle` radians around the normalized `axis`."
function Basis(axis::Vector3, angle::Real)
    sq = Vector3(axis.x * axis.x, axis.y * axis.y, axis.z * axis.z)
    s, c = sincos(_rt(angle))
    t = 1 - c
    xyzt = axis.x * axis.y * t
    zyxs = axis.z * s
    r01, r10 = xyzt - zyxs, xyzt + zyxs
    xyzt = axis.x * axis.z * t
    zyxs = axis.y * s
    r02, r20 = xyzt + zyxs, xyzt - zyxs
    xyzt = axis.y * axis.z * t
    zyxs = axis.x * s
    r12, r21 = xyzt - zyxs, xyzt + zyxs
    return Basis(Internals.ROWS, Vector3(sq.x + c * (1 - sq.x), r01, r02), Vector3(r10, sq.y + c * (1 - sq.y), r12),
                 Vector3(r20, r21, sq.z + c * (1 - sq.z)))
end

"Rotation basis of the quaternion `q`."
function Basis(q::Quaternion)
    d = length_squared(q)
    s = 2 / d
    xs, ys, zs = q.x * s, q.y * s, q.z * s
    wx, wy, wz = q.w * xs, q.w * ys, q.w * zs
    xx, xy, xz = q.x * xs, q.x * ys, q.x * zs
    yy, yz, zz = q.y * ys, q.y * zs, q.z * zs
    return Basis(Internals.ROWS, Vector3(1 - (yy + zz), xy - wz, xz + wy), Vector3(xy + wz, 1 - (xx + zz), yz - wx),
                 Vector3(xz - wy, yz + wx, 1 - (xx + yy)))
end

"Diagonal scale basis (C#: `Basis.FromScale`)."
from_scale(::Type{Basis}, s::Vector3) = Basis(Internals.ROWS, Vector3(s.x, 0, 0), Vector3(0, s.y, 0), Vector3(0, 0, s.z))

function determinant(b::Basis)
    m = b
    return m[1, 1] * (m[2, 2] * m[3, 3] - m[3, 2] * m[2, 3]) - m[2, 1] * (m[1, 2] * m[3, 3] - m[3, 2] * m[1, 3]) +
           m[3, 1] * (m[1, 2] * m[2, 3] - m[2, 2] * m[1, 3])
end
det(b::Basis) = determinant(b)

function inverse(b::Basis)
    m = b
    cofac(r1, c1, r2, c2) = m[r1, c1] * m[r2, c2] - m[r1, c2] * m[r2, c1]
    co = (cofac(2, 2, 3, 3), cofac(2, 3, 3, 1), cofac(2, 1, 3, 2))
    d = m[1, 1] * co[1] + m[1, 2] * co[2] + m[1, 3] * co[3]
    s = 1 / d
    return Basis(Internals.ROWS, Vector3(co[1] * s, cofac(1, 3, 3, 2) * s, cofac(1, 2, 2, 3) * s),
                 Vector3(co[2] * s, cofac(1, 1, 3, 3) * s, cofac(1, 3, 2, 1) * s),
                 Vector3(co[3] * s, cofac(1, 2, 3, 1) * s, cofac(1, 1, 2, 2) * s))
end
Base.inv(b::Basis) = inverse(b)
"Transpose of `b`."
transposed(b::Basis) = Basis(b.row0, b.row1, b.row2)
Base.transpose(b::Basis) = transposed(b)

"`b` with orthonormal columns (Gram-Schmidt)."
function orthonormalized(b::Basis)
    x = normalized(b.x)
    y = normalized(b.y - x * dot(x, b.y))
    z = normalized(b.z - x * dot(x, b.z) - y * dot(y, b.z))
    return Basis(x, y, z)
end
"`true` if the columns are orthogonal unit vectors."
function is_orthonormal(b::Basis)
    x, y, z = b.x, b.y, b.z
    return is_equal_approx(length_squared(x), 1) && is_equal_approx(length_squared(y), 1) &&
           is_equal_approx(length_squared(z), 1) && is_zero_approx(dot(x, y)) && is_zero_approx(dot(x, z)) &&
           is_zero_approx(dot(y, z))
end
"`true` if the columns are orthogonal and equally long (rotation with uniform scale)."
function is_conformal(b::Basis)
    x, y, z = b.x, b.y, b.z
    lx = length_squared(x)
    return is_equal_approx(lx, length_squared(y)) && is_equal_approx(lx, length_squared(z)) &&
           is_zero_approx(dot(x, y)) && is_zero_approx(dot(x, z)) && is_zero_approx(dot(y, z))
end

"`b` rotated by `angle` radians around `axis` in parent space."
rotated(b::Basis, axis::Vector3, angle::Real) = Basis(axis, angle) * b
"`b` scaled in parent space (each row scaled)."
scaled(b::Basis, s::Vector3) = Basis(Internals.ROWS, b.row0 * s.x, b.row1 * s.y, b.row2 * s.z)
"`b` scaled in local space."
scaled_local(b::Basis, s::Vector3) = b * from_scale(Basis, s)
_scale_abs(b::Basis) = Vector3(length(b.x), length(b.y), length(b.z))
"Scale along each axis; negative when the basis is flipped."
get_scale(b::Basis) = _sign(determinant(b)) * _scale_abs(b)

"Quaternion of `b`, which may be scaled but not sheared."
function _get_quaternion(m::Basis)
    trace = m[1, 1] + m[2, 2] + m[3, 3]
    if trace > 0
        s = sqrt(trace + 1)
        w = s * 0.5f0
        s = 0.5f0 / s
        return Quaternion((m[3, 2] - m[2, 3]) * s, (m[1, 3] - m[3, 1]) * s, (m[2, 1] - m[1, 2]) * s, w)
    end
    i = m[1, 1] < m[2, 2] ? (m[2, 2] < m[3, 3] ? 3 : 2) : (m[1, 1] < m[3, 3] ? 3 : 1)
    j = i % 3 + 1
    k = j % 3 + 1
    s = sqrt(m[i, i] - m[j, j] - m[k, k] + 1)
    temp = ntuple(_ -> zero(real_t), 4)
    temp = Base.setindex(temp, s * 0.5f0, i)
    s = 0.5f0 / s
    temp = Base.setindex(temp, (m[k, j] - m[j, k]) * s, 4)
    temp = Base.setindex(temp, (m[j, i] + m[i, j]) * s, j)
    temp = Base.setindex(temp, (m[k, i] + m[i, k]) * s, k)
    return Quaternion(temp...)
end
Quaternion(b::Basis) = _get_quaternion(b)

"Rotation part of `b` as a quaternion (scale removed; flips folded into the scale, see `get_scale`)."
function get_rotation_quaternion(b::Basis)
    m = orthonormalized(b)
    determinant(m) < 0 && (m = scaled(m, Vector3(-1, -1, -1)))
    return _get_quaternion(m)
end

"""
    get_euler(b::Basis, order = EULER_ORDER_YXZ) -> Vector3

Euler angles (radians) of the rotation of `b` for the given `EulerOrder`.
"""
function get_euler(b::Basis, order::Union{EulerOrder, Integer} = EULER_ORDER_YXZ)
    m = b
    o = Internals.enum_value(order)
    ϵ = real_t(0.00000025)
    half_pi = real_t(π) / 2
    if o == 0 # XYZ
        sy = m[1, 3]
        sy >= 1 - ϵ && return Vector3(atan(m[3, 2], m[2, 2]), half_pi, 0)
        sy <= -(1 - ϵ) && return Vector3(atan(m[3, 2], m[2, 2]), -half_pi, 0)
        if m[2, 1] == 0 && m[1, 2] == 0 && m[2, 3] == 0 && m[3, 2] == 0 && m[2, 2] == 1
            return Vector3(0, atan(m[1, 3], m[1, 1]), 0)
        end
        return Vector3(atan(-m[2, 3], m[3, 3]), _asin(sy), atan(-m[1, 2], m[1, 1]))
    elseif o == 1 # XZY
        sz = m[1, 2]
        sz >= 1 - ϵ && return Vector3(-atan(m[2, 3], m[3, 3]), 0, -half_pi)
        sz <= -(1 - ϵ) && return Vector3(-atan(m[2, 3], m[3, 3]), 0, half_pi)
        return Vector3(atan(m[3, 2], m[2, 2]), atan(m[1, 3], m[1, 1]), _asin(-sz))
    elseif o == 2 # YXZ
        m12 = m[2, 3]
        m12 >= 1 - ϵ && return Vector3(-half_pi, -atan(m[1, 2], m[1, 1]), 0)
        m12 <= -(1 - ϵ) && return Vector3(half_pi, atan(m[1, 2], m[1, 1]), 0)
        if m[2, 1] == 0 && m[1, 2] == 0 && m[1, 3] == 0 && m[3, 1] == 0 && m[1, 1] == 1
            return Vector3(atan(-m12, m[2, 2]), 0, 0)
        end
        return Vector3(_asin(-m12), atan(m[1, 3], m[3, 3]), atan(m[2, 1], m[2, 2]))
    elseif o == 3 # YZX
        sz = m[2, 1]
        sz >= 1 - ϵ && return Vector3(atan(m[3, 2], m[3, 3]), 0, half_pi)
        sz <= -(1 - ϵ) && return Vector3(atan(m[3, 2], m[3, 3]), 0, -half_pi)
        return Vector3(atan(-m[2, 3], m[2, 2]), atan(-m[3, 1], m[1, 1]), _asin(sz))
    elseif o == 4 # ZXY
        sx = m[3, 2]
        sx >= 1 - ϵ && return Vector3(half_pi, atan(m[1, 3], m[1, 1]), 0)
        sx <= -(1 - ϵ) && return Vector3(-half_pi, atan(m[1, 3], m[1, 1]), 0)
        return Vector3(_asin(sx), atan(-m[3, 1], m[3, 3]), atan(-m[1, 2], m[2, 2]))
    elseif o == 5 # ZYX
        sy = m[3, 1]
        sy >= 1 - ϵ && return Vector3(0, -half_pi, -atan(m[1, 2], m[2, 2]))
        sy <= -(1 - ϵ) && return Vector3(0, half_pi, -atan(m[1, 2], m[2, 2]))
        return Vector3(atan(m[3, 2], m[3, 3]), _asin(-sy), atan(m[2, 1], m[1, 1]))
    end
    throw(ArgumentError("invalid EulerOrder $o"))
end

"Rotation basis from Euler angles (radians) in the given `EulerOrder` (C#: `Basis.FromEuler`)."
function from_euler(::Type{Basis}, euler::Vector3, order::Union{EulerOrder, Integer} = EULER_ORDER_YXZ)
    s, c = sincos(euler.x)
    xmat = Basis(Internals.ROWS, Vector3(1, 0, 0), Vector3(0, c, -s), Vector3(0, s, c))
    s, c = sincos(euler.y)
    ymat = Basis(Internals.ROWS, Vector3(c, 0, s), Vector3(0, 1, 0), Vector3(-s, 0, c))
    s, c = sincos(euler.z)
    zmat = Basis(Internals.ROWS, Vector3(c, -s, 0), Vector3(s, c, 0), Vector3(0, 0, 1))
    o = Internals.enum_value(order)
    o == 0 && return xmat * (ymat * zmat)
    o == 1 && return xmat * zmat * ymat
    o == 2 && return ymat * xmat * zmat
    o == 3 && return ymat * zmat * xmat
    o == 4 && return zmat * xmat * ymat
    o == 5 && return zmat * ymat * xmat
    throw(ArgumentError("invalid EulerOrder $o"))
end

"Spherical interpolation of rotation (and linear interpolation of row lengths) toward `to`."
function slerp(a::Basis, to::Basis, weight::Real)
    b = Basis(slerp(_get_quaternion(a), _get_quaternion(to), weight))
    w = _rt(weight)
    return Basis(Internals.ROWS, b.row0 * lerp(length(a.row0), length(to.row0), w),
                 b.row1 * lerp(length(a.row1), length(to.row1), w), b.row2 * lerp(length(a.row2), length(to.row2), w))
end

"""
    looking_at(Basis, target, up = Vector3(0, 1, 0), use_model_front = false) -> Basis

Rotation whose -Z axis (or +Z with `use_model_front`) points along `target`, with Y as close to `up` as possible.
"""
function looking_at(::Type{Basis}, target::Vector3, up::Vector3 = Vector3(0, 1, 0), use_model_front::Bool = false)
    v_z = normalized(target)
    use_model_front || (v_z = -v_z)
    v_x = cross(up, v_z)
    is_zero_approx(v_x) && (v_x = _any_perpendicular(up))
    v_x = normalized(v_x)
    return Basis(v_x, cross(v_z, v_x), v_z)
end

is_equal_approx(a::Basis, b::Basis) =
    is_equal_approx(a.row0, b.row0) && is_equal_approx(a.row1, b.row1) && is_equal_approx(a.row2, b.row2)
Base.isapprox(a::Basis, b::Basis; kwargs...) =
    isapprox(a.row0, b.row0; kwargs...) && isapprox(a.row1, b.row1; kwargs...) && isapprox(a.row2, b.row2; kwargs...)
is_finite(b::Basis) = is_finite(b.row0) && is_finite(b.row1) && is_finite(b.row2)
