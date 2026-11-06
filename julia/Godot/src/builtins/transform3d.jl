# Transform3D (basis + origin).
# Ported from Godot's core/math/transform_3d.h/.cpp and GodotSharp/Core/Transform3D.cs (MIT, Godot contributors).

Transform3D() = Transform3D(Basis(), Vector3())
Base.one(::Type{Transform3D}) = Transform3D()
"Transform from the basis columns `x`, `y`, `z` and `origin`."
Transform3D(x::Vector3, y::Vector3, z::Vector3, origin::Vector3) = Transform3D(Basis(x, y, z), origin)
"Affine part of a projection matrix."
Transform3D(p::Projection) = Transform3D(Vector3(p.x.x, p.x.y, p.x.z), Vector3(p.y.x, p.y.y, p.y.z),
                                         Vector3(p.z.x, p.z.y, p.z.z), Vector3(p.w.x, p.w.y, p.w.z))

Base.:(==)(a::Transform3D, b::Transform3D) = a.basis == b.basis && a.origin == b.origin
function Base.show(io::IO, t::Transform3D)
    b = t.basis
    print(io, "Transform3D(", b.x, ", ", b.y, ", ", b.z, ", ", t.origin, ")")
end

_xform(t::Transform3D, v::Vector3) = _xform(t.basis, v) + t.origin
_xform_inv(t::Transform3D, v::Vector3) = _xform_inv(t.basis, v - t.origin)

function _xform(t::Transform3D, p::Plane)
    point = _xform(t, p.normal * p.d)
    normal = normalized(_xform(transposed(inverse(t.basis)), p.normal))
    return Plane(normal, dot(normal, point))
end
function _xform_inv(t::Transform3D, p::Plane)
    point = _xform(affine_inverse(t), p.normal * p.d)
    normal = normalized(_xform(transposed(t.basis), p.normal))
    return Plane(normal, dot(normal, point))
end

function _xform(t::Transform3D, a::AABB)
    lo = a.position
    hi = a.position + a.size
    tmin = _tup(t.origin)
    tmax = _tup(t.origin)
    for i in 1:3, j in 1:3
        e = t.basis[i, j] * lo[j]
        f = t.basis[i, j] * hi[j]
        if e < f
            tmin = _addat(tmin, i, e)
            tmax = _addat(tmax, i, f)
        else
            tmin = _addat(tmin, i, f)
            tmax = _addat(tmax, i, e)
        end
    end
    return AABB(Vector3(tmin...), Vector3(tmax...) - Vector3(tmin...))
end
@inline _tup(v::Vector3) = (v.x, v.y, v.z)
@inline _addat(t::NTuple{3}, i::Int, x) = Base.setindex(t, t[i] + x, i)

function _xform_inv(t::Transform3D, a::AABB)
    p, s = a.position, a.size
    r = AABB(_xform_inv(t, Vector3(p.x + s.x, p.y + s.y, p.z + s.z)), Vector3())
    for v in (Vector3(p.x + s.x, p.y + s.y, p.z), Vector3(p.x + s.x, p.y, p.z + s.z), Vector3(p.x + s.x, p.y, p.z),
              Vector3(p.x, p.y + s.y, p.z + s.z), Vector3(p.x, p.y + s.y, p.z), Vector3(p.x, p.y, p.z + s.z),
              Vector3(p.x, p.y, p.z))
        r = expand(r, _xform_inv(t, v))
    end
    return r
end

Base.:*(t::Transform3D, v::Vector3) = _xform(t, v)
Base.:*(v::Vector3, t::Transform3D) = _xform_inv(t, v)
Base.:*(t::Transform3D, p::Plane) = _xform(t, p)
Base.:*(p::Plane, t::Transform3D) = _xform_inv(t, p)
Base.:*(t::Transform3D, a::AABB) = _xform(t, a)
Base.:*(a::AABB, t::Transform3D) = _xform_inv(t, a)
Base.:*(a::Transform3D, b::Transform3D) = Transform3D(a.basis * b.basis, _xform(a, b.origin))
Base.:*(t::Transform3D, s::Real) = Transform3D(t.basis * s, t.origin * s)
Base.:*(s::Real, t::Transform3D) = t * s
Base.:/(t::Transform3D, s::Real) = Transform3D(t.basis / s, t.origin / s)

"Inverse of any invertible transform."
affine_inverse(t::Transform3D) = (b = inverse(t.basis); Transform3D(b, _xform(b, -t.origin)))
"Inverse assuming an orthonormal basis (rotation and translation only); see `affine_inverse`."
inverse(t::Transform3D) = (b = transposed(t.basis); Transform3D(b, _xform(b, -t.origin)))
Base.inv(t::Transform3D) = affine_inverse(t)
"`t` with an orthonormalized basis."
orthonormalized(t::Transform3D) = Transform3D(orthonormalized(t.basis), t.origin)
"`t` rotated around `axis` by `angle` radians in parent space."
rotated(t::Transform3D, axis::Vector3, angle::Real) = (b = Basis(axis, angle); Transform3D(b * t.basis, _xform(b, t.origin)))
"`t` rotated around `axis` by `angle` radians in local space."
rotated_local(t::Transform3D, axis::Vector3, angle::Real) = Transform3D(t.basis * Basis(axis, angle), t.origin)
scaled(t::Transform3D, s::Vector3) = Transform3D(scaled(t.basis, s), t.origin * s)
scaled_local(t::Transform3D, s::Vector3) = Transform3D(scaled_local(t.basis, s), t.origin)
translated(t::Transform3D, offset::Vector3) = Transform3D(t.basis, t.origin + offset)
translated_local(t::Transform3D, offset::Vector3) = Transform3D(t.basis, t.origin + _xform(t.basis, offset))

"`t` rotated so -Z (or +Z with `use_model_front`) points at `target`, keeping the origin."
looking_at(t::Transform3D, target::Vector3, up::Vector3 = Vector3(0, 1, 0), use_model_front::Bool = false) =
    Transform3D(looking_at(Basis, target - t.origin, up, use_model_front), t.origin)

"Interpolation of rotation (slerp), scale and origin toward `b`."
function interpolate_with(a::Transform3D, b::Transform3D, weight::Real)
    src_scale = get_scale(a.basis)
    src_rot = get_rotation_quaternion(a.basis)
    dst_scale = get_scale(b.basis)
    dst_rot = get_rotation_quaternion(b.basis)
    basis = Basis(normalized(slerp(src_rot, dst_rot, weight))) * from_scale(Basis, lerp(src_scale, dst_scale, weight))
    return Transform3D(basis, lerp(a.origin, b.origin, weight))
end

is_equal_approx(a::Transform3D, b::Transform3D) = is_equal_approx(a.basis, b.basis) && is_equal_approx(a.origin, b.origin)
Base.isapprox(a::Transform3D, b::Transform3D; kwargs...) =
    isapprox(a.basis, b.basis; kwargs...) && isapprox(a.origin, b.origin; kwargs...)
is_finite(t::Transform3D) = is_finite(t.basis) && is_finite(t.origin)
