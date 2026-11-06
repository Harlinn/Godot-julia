# Projection (4×4, columns x, y, z, w).
# Ported from Godot's core/math/projection.h/.cpp and GodotSharp/Core/Projection.cs (MIT, Godot contributors).

Projection() = Projection(Vector4(1, 0, 0, 0), Vector4(0, 1, 0, 0), Vector4(0, 0, 1, 0), Vector4(0, 0, 0, 1))
Base.one(::Type{Projection}) = Projection()
"Projection matrix of the affine transform `t`."
function Projection(t::Transform3D)
    b = t.basis
    return Projection(Vector4(b.x.x, b.x.y, b.x.z, 0), Vector4(b.y.x, b.y.y, b.y.z, 0), Vector4(b.z.x, b.z.y, b.z.z, 0),
                      Vector4(t.origin.x, t.origin.y, t.origin.z, 1))
end

# Element (column c, row r), both 0-based like Godot's columns[c][r]; m(k) is the flat column-major element k.
@inline _c(p::Projection, c::Int, r::Int) = getfield(getfield(p, c + 1), r + 1)
@inline _m(p::Projection, k::Int) = _c(p, k ÷ 4, k % 4)
_from_cols(f) = Projection(Vector4(f(0, 0), f(0, 1), f(0, 2), f(0, 3)), Vector4(f(1, 0), f(1, 1), f(1, 2), f(1, 3)),
                           Vector4(f(2, 0), f(2, 1), f(2, 2), f(2, 3)), Vector4(f(3, 0), f(3, 1), f(3, 2), f(3, 3)))
_set(p::Projection, c::Int, r::Int, v) = _from_cols((i, j) -> i == c && j == r ? _rt(v) : _c(p, i, j))

"`p[i, j]`: row `i`, column `j` (1-based, matrix convention)."
Base.@propagate_inbounds Base.getindex(p::Projection, i::Integer, j::Integer) = getfield(p, Int(j))[i]
Base.@propagate_inbounds Base.getindex(p::Projection, i::Integer) =
    (@boundscheck 1 <= i <= 4 || throw(BoundsError(p, i)); getfield(p, Int(i)))
Base.:(==)(a::Projection, b::Projection) = a.x == b.x && a.y == b.y && a.z == b.z && a.w == b.w
Base.show(io::IO, p::Projection) = print(io, "Projection(", p.x, ", ", p.y, ", ", p.z, ", ", p.w, ")")
is_equal_approx(a::Projection, b::Projection) =
    is_equal_approx(a.x, b.x) && is_equal_approx(a.y, b.y) && is_equal_approx(a.z, b.z) && is_equal_approx(a.w, b.w)
Base.isapprox(a::Projection, b::Projection; kwargs...) = isapprox(a.x, b.x; kwargs...) && isapprox(a.y, b.y; kwargs...) &&
                                                         isapprox(a.z, b.z; kwargs...) && isapprox(a.w, b.w; kwargs...)
is_finite(p::Projection) = is_finite(p.x) && is_finite(p.y) && is_finite(p.z) && is_finite(p.w)

Base.:*(a::Projection, b::Projection) = _from_cols((j, i) -> sum(_c(a, k, i) * _c(b, j, k) for k in 0:3))
Base.:*(p::Projection, v::Vector4) = Vector4(p.x.x * v.x + p.y.x * v.y + p.z.x * v.z + p.w.x * v.w,
                                             p.x.y * v.x + p.y.y * v.y + p.z.y * v.z + p.w.y * v.w,
                                             p.x.z * v.x + p.y.z * v.y + p.z.z * v.z + p.w.z * v.w,
                                             p.x.w * v.x + p.y.w * v.y + p.z.w * v.z + p.w.w * v.w)
Base.:*(v::Vector4, p::Projection) = Vector4(dot(p.x, v), dot(p.y, v), dot(p.z, v), dot(p.w, v))

function determinant(p::Projection)
    m(c, r) = Float64(_c(p, c, r))
    s0 = m(0, 0) * m(1, 1) - m(1, 0) * m(0, 1)
    s1 = m(0, 0) * m(1, 2) - m(1, 0) * m(0, 2)
    s2 = m(0, 0) * m(1, 3) - m(1, 0) * m(0, 3)
    s3 = m(0, 1) * m(1, 2) - m(1, 1) * m(0, 2)
    s4 = m(0, 1) * m(1, 3) - m(1, 1) * m(0, 3)
    s5 = m(0, 2) * m(1, 3) - m(1, 2) * m(0, 3)
    c5 = m(2, 2) * m(3, 3) - m(3, 2) * m(2, 3)
    c4 = m(2, 1) * m(3, 3) - m(3, 1) * m(2, 3)
    c3 = m(2, 1) * m(3, 2) - m(3, 1) * m(2, 2)
    c2 = m(2, 0) * m(3, 3) - m(3, 0) * m(2, 3)
    c1 = m(2, 0) * m(3, 2) - m(3, 0) * m(2, 2)
    c0 = m(2, 0) * m(3, 1) - m(3, 0) * m(2, 1)
    return real_t(s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0)
end
det(p::Projection) = determinant(p)

function inverse(p::Projection)
    m(c, r) = Float64(_c(p, c, r))
    s0 = m(0, 0) * m(1, 1) - m(1, 0) * m(0, 1)
    s1 = m(0, 0) * m(1, 2) - m(1, 0) * m(0, 2)
    s2 = m(0, 0) * m(1, 3) - m(1, 0) * m(0, 3)
    s3 = m(0, 1) * m(1, 2) - m(1, 1) * m(0, 2)
    s4 = m(0, 1) * m(1, 3) - m(1, 1) * m(0, 3)
    s5 = m(0, 2) * m(1, 3) - m(1, 2) * m(0, 3)
    c5 = m(2, 2) * m(3, 3) - m(3, 2) * m(2, 3)
    c4 = m(2, 1) * m(3, 3) - m(3, 1) * m(2, 3)
    c3 = m(2, 1) * m(3, 2) - m(3, 1) * m(2, 2)
    c2 = m(2, 0) * m(3, 3) - m(3, 0) * m(2, 3)
    c1 = m(2, 0) * m(3, 2) - m(3, 0) * m(2, 2)
    c0 = m(2, 0) * m(3, 1) - m(3, 0) * m(2, 1)
    id = 1 / (s0 * c5 - s1 * c4 + s2 * c3 + s3 * c2 - s4 * c1 + s5 * c0)
    # Adjugate of the column-major matrix m(c, r); result element (c, r).
    inv = ((m(1, 1) * c5 - m(1, 2) * c4 + m(1, 3) * c3) * id, (-m(0, 1) * c5 + m(0, 2) * c4 - m(0, 3) * c3) * id,
           (m(3, 1) * s5 - m(3, 2) * s4 + m(3, 3) * s3) * id, (-m(2, 1) * s5 + m(2, 2) * s4 - m(2, 3) * s3) * id,
           (-m(1, 0) * c5 + m(1, 2) * c2 - m(1, 3) * c1) * id, (m(0, 0) * c5 - m(0, 2) * c2 + m(0, 3) * c1) * id,
           (-m(3, 0) * s5 + m(3, 2) * s2 - m(3, 3) * s1) * id, (m(2, 0) * s5 - m(2, 2) * s2 + m(2, 3) * s1) * id,
           (m(1, 0) * c4 - m(1, 1) * c2 + m(1, 3) * c0) * id, (-m(0, 0) * c4 + m(0, 1) * c2 - m(0, 3) * c0) * id,
           (m(3, 0) * s4 - m(3, 1) * s2 + m(3, 3) * s0) * id, (-m(2, 0) * s4 + m(2, 1) * s2 - m(2, 3) * s0) * id,
           (-m(1, 0) * c3 + m(1, 1) * c1 - m(1, 2) * c0) * id, (m(0, 0) * c3 - m(0, 1) * c1 + m(0, 2) * c0) * id,
           (-m(3, 0) * s3 + m(3, 1) * s1 - m(3, 2) * s0) * id, (m(2, 0) * s3 - m(2, 1) * s1 + m(2, 2) * s0) * id)
    # Standard 2×2-minor inverse applied to A[i][j] = m(i, j) = Mᵀ, so inv[4i + j + 1] is element (column i, row j).
    return _from_cols((c, r) -> inv[4c + r + 1])
end
Base.inv(p::Projection) = inverse(p)

_plane(a, b, c, d) = Plane(a, b, c, d)
_negnorm(p::Plane) = normalized(Plane(-p.normal, p.d))

"One of the six clipping planes (`Projection_Planes`)."
function get_projection_plane(p::Projection, plane::Union{Projection_Planes, Integer})
    m(k) = _m(p, k)
    i = Internals.enum_value(plane)
    i == 0 && return _negnorm(_plane(m(3) + m(2), m(7) + m(6), m(11) + m(10), m(15) + m(14)))
    i == 1 && return _negnorm(_plane(m(3) - m(2), m(7) - m(6), m(11) - m(10), m(15) - m(14)))
    i == 2 && return _negnorm(_plane(m(3) + m(0), m(7) + m(4), m(11) + m(8), m(15) + m(12)))
    i == 3 && return _negnorm(_plane(m(3) - m(1), m(7) - m(5), m(11) - m(9), m(15) - m(13)))
    i == 4 && return _negnorm(_plane(m(3) - m(0), m(7) - m(4), m(11) - m(8), m(15) - m(12)))
    i == 5 && return _negnorm(_plane(m(3) + m(1), m(7) + m(5), m(11) + m(9), m(15) + m(13)))
    return Plane()
end

# These assume a projection along Z with a rectangular projection plane, as in Godot 4.7.
"Far clipping distance."
get_z_far(p::Projection) = (_c(p, 3, 3) - _c(p, 3, 2)) / (_c(p, 2, 3) - _c(p, 2, 2))
"Near clipping distance."
get_z_near(p::Projection) = (_c(p, 3, 3) + _c(p, 3, 2)) / (_c(p, 2, 3) + _c(p, 2, 2))
_half_extents(p::Projection, z) = (w = -z * _c(p, 2, 3) + _c(p, 3, 3); Vector2(w / _c(p, 0, 0), w / _c(p, 1, 1)))
"Half width and height of the viewport at the near plane."
get_viewport_half_extents(p::Projection) = _half_extents(p, get_z_near(p))
"Half width and height of the viewport at the far plane."
get_far_plane_half_extents(p::Projection) = _half_extents(p, get_z_far(p))
"Width/height ratio of the viewport."
get_aspect(p::Projection) = _c(p, 1, 1) / _c(p, 0, 0)
"Horizontal field of view in degrees."
function get_fov(p::Projection)
    _c(p, 2, 0) == 0 && return rad2deg(2 * atan(one(real_t), _c(p, 0, 0)))
    return rad2deg(atan(_c(p, 2, 0) + 1, _c(p, 0, 0)) - atan(_c(p, 2, 0) - 1, _c(p, 0, 0)))
end
"`true` for orthogonal (non-perspective) projections."
is_orthogonal(p::Projection) = _c(p, 2, 3) == 0
"Pixels per meter at depth 1 for a viewport `for_pixel_width` pixels wide."
get_pixels_per_meter(p::Projection, for_pixel_width::Integer) =
    trunc(Int64, for_pixel_width / (2 * (-get_z_near(p) * _c(p, 2, 3) + _c(p, 3, 3)) / _c(p, 0, 0)))
"Factor for converting distances to level-of-detail thresholds."
get_lod_multiplier(p::Projection) = 2 / _c(p, 0, 0)

"`p` with the near plane moved to `new_znear`."
function perspective_znear_adjusted(p::Projection, new_znear::Real)
    zfar = get_z_far(p)
    dz = zfar - new_znear
    q = _set(p, 2, 2, -(zfar + new_znear) / dz)
    return _set(q, 3, 2, -2 * new_znear * zfar / dz)
end
"`p` with its Y axis negated."
flipped_y(p::Projection) = Projection(p.x, -p.y, p.z, p.w)
"`p` translated in clip space by `offset` (for TAA jitter)."
jitter_offseted(p::Projection, offset::Vector2) = _set(_set(p, 3, 0, _c(p, 3, 0) + offset.x), 3, 1, _c(p, 3, 1) + offset.y)

"Vertical FOV (degrees) matching horizontal FOV `fovx` at `aspect` (C#: `Projection.GetFovy`)."
get_fovy(::Type{Projection}, fovx::Real, aspect::Real) = rad2deg(atan(aspect * tan(deg2rad(fovx) * 0.5)) * 2)

"Projection converting OpenGL clip space to Godot's reverse-Z [0, 1] depth, optionally flipping Y."
create_depth_correction(::Type{Projection}, flip_y::Bool) =
    Projection(Vector4(1, 0, 0, 0), Vector4(0, flip_y ? -1 : 1, 0, 0), Vector4(0, 0, -0.5, 0), Vector4(0, 0, 0.5, 1))
"Projection mapping the unit square onto `rect` of a light atlas."
create_light_atlas_rect(::Type{Projection}, r::Rect2) = Projection(Vector4(r.size.x, 0, 0, 0), Vector4(0, r.size.y, 0, 0),
                                                                   Vector4(0, 0, 1, 0), Vector4(r.position.x, r.position.y, 0, 1))

"Perspective projection from vertical FOV `fovy` (degrees)."
function create_perspective(::Type{Projection}, fovy::Real, aspect::Real, z_near::Real, z_far::Real, flip_fov::Bool = false)
    flip_fov && (fovy = get_fovy(Projection, fovy, 1 / aspect))
    radians = deg2rad(fovy / 2)
    dz = z_far - z_near
    s = sin(radians)
    (dz == 0 || s == 0 || aspect == 0) && return Projection()
    cot = cos(radians) / s
    return Projection(Vector4(cot / aspect, 0, 0, 0), Vector4(0, cot, 0, 0), Vector4(0, 0, -(z_far + z_near) / dz, -1),
                      Vector4(0, 0, -2 * z_near * z_far / dz, 0))
end

"Perspective projection for one eye of a stereo setup (`eye`: 1 = left, 2 = right)."
function create_perspective_hmd(::Type{Projection}, fovy::Real, aspect::Real, z_near::Real, z_far::Real, flip_fov::Bool,
                                eye::Integer, intraocular_dist::Real, convergence_dist::Real)
    flip_fov && (fovy = get_fovy(Projection, fovy, 1 / aspect))
    ymax = z_near * tan(deg2rad(fovy / 2))
    xmax = ymax * aspect
    shift = (intraocular_dist / 2) * z_near / convergence_dist
    left, right, translation = eye == 1 ? (-xmax + shift, xmax + shift, intraocular_dist / 2) :
                               eye == 2 ? (-xmax - shift, xmax - shift, -intraocular_dist / 2) : (-xmax, xmax, 0.0)
    p = create_frustum(Projection, left, right, -ymax, ymax, z_near, z_far)
    return p * _set(Projection(), 3, 0, translation)
end

"Projection for a head-mounted display lens (`eye`: 1 = left, 2 = right)."
function create_for_hmd(::Type{Projection}, eye::Integer, aspect::Real, intraocular_dist::Real, display_width::Real,
                        display_to_lens::Real, oversample::Real, z_near::Real, z_far::Real)
    f1 = (intraocular_dist * 0.5) / display_to_lens
    f2 = ((display_width - intraocular_dist) * 0.5) / display_to_lens
    f3 = (display_width / 4) / display_to_lens
    add = ((f1 + f2) * (oversample - 1)) / 2
    f1 += add
    f2 += add
    f3 = f3 * oversample / aspect
    eye == 1 && return create_frustum(Projection, -f2 * z_near, f1 * z_near, -f3 * z_near, f3 * z_near, z_near, z_far)
    eye == 2 && return create_frustum(Projection, -f1 * z_near, f2 * z_near, -f3 * z_near, f3 * z_near, z_near, z_far)
    return Projection()
end

"Orthogonal projection of the given box."
function create_orthogonal(::Type{Projection}, left::Real, right::Real, bottom::Real, top::Real, z_near::Real, z_far::Real)
    return Projection(Vector4(2 / (right - left), 0, 0, 0), Vector4(0, 2 / (top - bottom), 0, 0),
                      Vector4(0, 0, -2 / (z_far - z_near), 0),
                      Vector4(-((right + left) / (right - left)), -((top + bottom) / (top - bottom)),
                              -((z_far + z_near) / (z_far - z_near)), 1))
end
"Orthogonal projection of height `size` (width with `flip_fov`) and `aspect`."
function create_orthogonal_aspect(::Type{Projection}, size::Real, aspect::Real, z_near::Real, z_far::Real,
                                  flip_fov::Bool = false)
    flip_fov || (size *= aspect)
    return create_orthogonal(Projection, -size / 2, size / 2, -size / aspect / 2, size / aspect / 2, z_near, z_far)
end

"Perspective frustum projection."
function create_frustum(::Type{Projection}, left::Real, right::Real, bottom::Real, top::Real, z_near::Real, z_far::Real)
    (right <= left || top <= bottom || z_far <= z_near) && return Projection()
    x = 2 * z_near / (right - left)
    y = 2 * z_near / (top - bottom)
    a = (right + left) / (right - left)
    b = (top + bottom) / (top - bottom)
    c = -(z_far + z_near) / (z_far - z_near)
    d = -2 * z_far * z_near / (z_far - z_near)
    return Projection(Vector4(x, 0, 0, 0), Vector4(0, y, 0, 0), Vector4(a, b, c, -1), Vector4(0, 0, d, 0))
end
"Frustum projection of height `size` (width with `flip_fov`), `aspect` and `offset`."
function create_frustum_aspect(::Type{Projection}, size::Real, aspect::Real, offset::Vector2, z_near::Real, z_far::Real,
                               flip_fov::Bool = false)
    flip_fov || (size *= aspect)
    return create_frustum(Projection, -size / 2 + offset.x, size / 2 + offset.x, -size / aspect / 2 + offset.y,
                          size / aspect / 2 + offset.y, z_near, z_far)
end
"Projection scaling and translating `aabb` to the unit cube."
function create_fit_aabb(::Type{Projection}, aabb::AABB)
    lo = aabb.position
    hi = aabb.position + aabb.size
    return Projection(Vector4(2 / (hi.x - lo.x), 0, 0, 0), Vector4(0, 2 / (hi.y - lo.y), 0, 0),
                      Vector4(0, 0, 2 / (hi.z - lo.z), 0),
                      Vector4(-(hi.x + lo.x) / (hi.x - lo.x), -(hi.y + lo.y) / (hi.y - lo.y), -(hi.z + lo.z) / (hi.z - lo.z), 1))
end
