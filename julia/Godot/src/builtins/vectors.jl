# Operations shared by Vector2/3/4 and Vector2i/3i/4i, generated per type.
# Ported from Godot's core/math/vector*.h/.cpp and GodotSharp/Core/Vector*.cs (MIT, Godot contributors).

const _FLOAT_VECTORS = ((:Vector2, (:x, :y), :Vector2_Axis, :Vector2i), (:Vector3, (:x, :y, :z), :Vector3_Axis, :Vector3i),
                        (:Vector4, (:x, :y, :z, :w), :Vector4_Axis, :Vector4i))
const _INT_VECTORS = ((:Vector2i, (:x, :y), :Vector2i_Axis, :Vector2), (:Vector3i, (:x, :y, :z), :Vector3i_Axis, :Vector3),
                      (:Vector4i, (:x, :y, :z, :w), :Vector4i_Axis, :Vector4))

_each(V, fs, f) = Expr(:call, V, (f(c) for c in fs)...)
_all(fs, f) = foldl((a, b) -> :($a && $b), (f(c) for c in fs))
_sum(fs, f) = foldl((a, b) -> :($a + $b), (f(c) for c in fs))
"`print` arguments rendering `T(a.x, a.y, ...)`."
_show_args(T, fs) = vcat(Any["$T("], collect(Iterators.flatten(i == 1 ? (:(a.$c),) : (", ", :(a.$c)) for (i, c) in enumerate(fs))), Any[")"])

# Godot's lexicographic comparison operators.
function _less(fs, op)
    c = fs[end]
    ex = :($op(a.$c, b.$c))
    for c in reverse(fs[1:(end - 1)])
        ex = :(a.$c == b.$c ? $ex : a.$c < b.$c)
    end
    return ex
end

for (V, fs, Axis, _) in (_FLOAT_VECTORS..., _INT_VECTORS...)
    n = length(fs)
    @eval begin
        $V() = $(_each(V, fs, _ -> 0))
        Base.zero(::Type{$V}) = $V()
        Base.one(::Type{$V}) = $(_each(V, fs, _ -> 1))
        Base.:+(a::$V) = a
        Base.:-(a::$V) = $(_each(V, fs, c -> :(-a.$c)))
        Base.:+(a::$V, b::$V) = $(_each(V, fs, c -> :(a.$c + b.$c)))
        Base.:-(a::$V, b::$V) = $(_each(V, fs, c -> :(a.$c - b.$c)))
        Base.:(==)(a::$V, b::$V) = $(_all(fs, c -> :(a.$c == b.$c)))
        Base.:<(a::$V, b::$V) = $(_less(fs, :<))
        Base.:(<=)(a::$V, b::$V) = $(_less(fs, :<=))
        Base.isless(a::$V, b::$V) = a < b
        Base.abs(a::$V) = $(_each(V, fs, c -> :(abs(a.$c))))
        Base.sign(a::$V) = $(_each(V, fs, c -> :(_sign(a.$c))))
        Base.min(a::$V, b::$V) = $(_each(V, fs, c -> :(_min(a.$c, b.$c))))
        Base.max(a::$V, b::$V) = $(_each(V, fs, c -> :(_max(a.$c, b.$c))))
        Base.clamp(a::$V, lo::$V, hi::$V) = $(_each(V, fs, c -> :(_clamp(a.$c, lo.$c, hi.$c))))
        "Componentwise remainder of `a / b` with the sign of the divisor."
        posmod(a::$V, b::$V) = $(_each(V, fs, c -> :(posmod(a.$c, b.$c))))
        Base.@propagate_inbounds Base.getindex(a::$V, i::Integer) = (@boundscheck 1 <= i <= $n || throw(BoundsError(a, i)); getfield(a, Int(i)))
        Base.getindex(a::$V, axis::$Axis) = getfield(a, axis.value + 1)
        "Squared distance between two points."
        distance_squared_to(a::$V, b::$V) = length_squared(b - a)
        Base.show(io::IO, a::$V) = print(io, $(_show_args(V, fs)...))
    end
end

for (V, fs, Axis, I) in _FLOAT_VECTORS
    @eval begin
        $V(v::$I) = $(_each(V, fs, c -> :(v.$c)))
        Base.:*(a::$V, b::$V) = $(_each(V, fs, c -> :(a.$c * b.$c)))
        Base.:/(a::$V, b::$V) = $(_each(V, fs, c -> :(a.$c / b.$c)))
        Base.:*(a::$V, s::Real) = (s = _rt(s); $(_each(V, fs, c -> :(a.$c * s))))
        Base.:*(s::Real, a::$V) = a * s
        Base.:/(a::$V, s::Real) = (s = _rt(s); $(_each(V, fs, c -> :(a.$c / s))))
        Base.floor(a::$V) = $(_each(V, fs, c -> :(floor(a.$c))))
        Base.ceil(a::$V) = $(_each(V, fs, c -> :(ceil(a.$c))))
        Base.round(a::$V) = $(_each(V, fs, c -> :(_round(a.$c))))
        "Componentwise `min` with a scalar."
        minf(a::$V, s::Real) = (s = _rt(s); $(_each(V, fs, c -> :(_min(a.$c, s)))))
        "Componentwise `max` with a scalar."
        maxf(a::$V, s::Real) = (s = _rt(s); $(_each(V, fs, c -> :(_max(a.$c, s)))))
        "Clamp every component to `[lo, hi]`."
        clampf(a::$V, lo::Real, hi::Real) = (lo = _rt(lo); hi = _rt(hi); $(_each(V, fs, c -> :(_clamp(a.$c, lo, hi)))))
        snapped(a::$V, step::$V) = $(_each(V, fs, c -> :(snapped(a.$c, step.$c))))
        "Snap every component to a multiple of `step`."
        snappedf(a::$V, step::Real) = $(_each(V, fs, c -> :(snapped(a.$c, step))))
        posmod(a::$V, m::Real) = (m = _rt(m); $(_each(V, fs, c -> :(posmod(a.$c, m)))))
        "Componentwise positive modulo by another vector (GDScript name; same as `posmod(a, b)`)."
        posmodv(a::$V, b::$V) = posmod(a, b)
        lerp(a::$V, b::$V, w::Real) = (w = _rt(w); $(_each(V, fs, c -> :(lerp(a.$c, b.$c, w)))))
        cubic_interpolate(a::$V, b::$V, pre_a::$V, post_b::$V, w::Real) =
            $(_each(V, fs, c -> :(cubic_interpolate(a.$c, b.$c, pre_a.$c, post_b.$c, w))))
        cubic_interpolate_in_time(a::$V, b::$V, pre_a::$V, post_b::$V, w::Real, b_t::Real, pre_a_t::Real, post_b_t::Real) =
            $(_each(V, fs, c -> :(cubic_interpolate_in_time(a.$c, b.$c, pre_a.$c, post_b.$c, w, b_t, pre_a_t, post_b_t))))
        bezier_interpolate(a::$V, control_1::$V, control_2::$V, end_::$V, t::Real) =
            $(_each(V, fs, c -> :(bezier_interpolate(a.$c, control_1.$c, control_2.$c, end_.$c, t))))
        bezier_derivative(a::$V, control_1::$V, control_2::$V, end_::$V, t::Real) =
            $(_each(V, fs, c -> :(bezier_derivative(a.$c, control_1.$c, control_2.$c, end_.$c, t))))
        is_equal_approx(a::$V, b::$V) = $(_all(fs, c -> :(is_equal_approx(a.$c, b.$c))))
        is_zero_approx(a::$V) = $(_all(fs, c -> :(is_zero_approx(a.$c))))
        is_finite(a::$V) = $(_all(fs, c -> :(isfinite(a.$c))))
        Base.isapprox(a::$V, b::$V; kwargs...) =
            isempty(kwargs) ? is_equal_approx(a, b) : $(_all(fs, c -> :(isapprox(a.$c, b.$c; kwargs...))))
        dot(a::$V, b::$V) = $(_sum(fs, c -> :(a.$c * b.$c)))
        "Squared length (avoids the square root of `length`)."
        length_squared(a::$V) = $(_sum(fs, c -> :(a.$c * a.$c)))
        "Euclidean length (also `LinearAlgebra.norm`)."
        Base.length(a::$V) = sqrt(length_squared(a))
        norm(a::$V) = length(a)
        "Distance between two points."
        distance_to(a::$V, b::$V) = length(b - a)
        "Normalized direction from `a` toward `b`."
        direction_to(a::$V, b::$V) = normalized(b - a)
        "`true` if the length is approximately 1."
        is_normalized(a::$V) = is_equal_approx(length_squared(a), 1, UNIT_EPSILON)
        normalize(a::$V) = normalized(a)
    end
end

for (V, fs, Axis, F) in _INT_VECTORS
    @eval begin
        $V(v::$F) = $(_each(V, fs, c -> :(unsafe_trunc(Int32, v.$c))))
        Base.:*(a::$V, b::$V) = $(_each(V, fs, c -> :(a.$c * b.$c)))
        Base.:/(a::$V, b::$V) = $(_each(V, fs, c -> :(div(a.$c, b.$c))))
        Base.:%(a::$V, b::$V) = $(_each(V, fs, c -> :(rem(a.$c, b.$c))))
        Base.:*(a::$V, s::Integer) = (s = s % Int32; $(_each(V, fs, c -> :(a.$c * s))))
        Base.:*(s::Integer, a::$V) = a * s
        Base.:/(a::$V, s::Integer) = (s = s % Int32; $(_each(V, fs, c -> :(div(a.$c, s)))))
        Base.:%(a::$V, s::Integer) = (s = s % Int32; $(_each(V, fs, c -> :(rem(a.$c, s)))))
        Base.:*(a::$V, s::AbstractFloat) = $F(a) * s
        Base.:*(s::AbstractFloat, a::$V) = $F(a) * s
        Base.:/(a::$V, s::AbstractFloat) = $F(a) / s
        "Componentwise `min` with an integer."
        mini(a::$V, s::Integer) = $(_each(V, fs, c -> :(_min(a.$c, s))))
        "Componentwise `max` with an integer."
        maxi(a::$V, s::Integer) = $(_each(V, fs, c -> :(_max(a.$c, s))))
        "Clamp every component to `[lo, hi]`."
        clampi(a::$V, lo::Integer, hi::Integer) = $(_each(V, fs, c -> :(_clamp(a.$c, lo, hi))))
        snapped(a::$V, step::$V) = $(_each(V, fs, c -> :(snapped(a.$c, step.$c))))
        "Snap every component to a multiple of `step`."
        snappedi(a::$V, step::Integer) = $(_each(V, fs, c -> :(snapped(a.$c, step))))
        length_squared(a::$V) = $(_sum(fs, c -> :(Int64(a.$c) * a.$c)))
        Base.length(a::$V) = sqrt(Float64(length_squared(a)))
        distance_to(a::$V, b::$V) = length(b - a)
    end
end

# Axis queries return the typed axis enum, as C# does.
max_axis_index(a::Vector2) = a.x < a.y ? Vector2_AXIS_Y : Vector2_AXIS_X
min_axis_index(a::Vector2) = a.x < a.y ? Vector2_AXIS_X : Vector2_AXIS_Y
max_axis_index(a::Vector2i) = a.x < a.y ? Vector2i_AXIS_Y : Vector2i_AXIS_X
min_axis_index(a::Vector2i) = a.x < a.y ? Vector2i_AXIS_X : Vector2i_AXIS_Y
max_axis_index(a::Vector3) = Vector3_Axis(a.x < a.y ? (a.y < a.z ? 2 : 1) : (a.x < a.z ? 2 : 0))
min_axis_index(a::Vector3) = Vector3_Axis(a.x < a.y ? (a.x < a.z ? 0 : 2) : (a.y < a.z ? 1 : 2))
max_axis_index(a::Vector3i) = Vector3i_Axis(a.x < a.y ? (a.y < a.z ? 2 : 1) : (a.x < a.z ? 2 : 0))
min_axis_index(a::Vector3i) = Vector3i_Axis(a.x < a.y ? (a.x < a.z ? 0 : 2) : (a.y < a.z ? 1 : 2))
for (V, Axis) in ((:Vector4, :Vector4_Axis), (:Vector4i, :Vector4i_Axis))
    @eval function max_axis_index(a::$V)
        i, m = 0, a.x
        a.y > m && ((i, m) = (1, a.y))
        a.z > m && ((i, m) = (2, a.z))
        a.w > m && (i = 3)
        return $Axis(i)
    end
    @eval function min_axis_index(a::$V)
        i, m = 0, a.x
        a.y < m && ((i, m) = (1, a.y))
        a.z < m && ((i, m) = (2, a.z))
        a.w < m && (i = 3)
        return $Axis(i)
    end
end

aspect(a::Vector2) = a.x / a.y
aspect(a::Vector2i) = Float64(a.x) / a.y

# Float-vector operations shared by Vector2 and Vector3 (C# defines them on both).
for V in (:Vector2, :Vector3, :Vector4)
    @eval function normalized(a::$V)
        l = length_squared(a)
        return l == 0 ? a : a / sqrt(l)
    end
end
for V in (:Vector3, :Vector4)
    @eval begin
        "Componentwise reciprocal."
        inverse(a::$V) = one($V) / a
    end
end

for V in (:Vector2, :Vector3)
    @eval begin
        "`a` with its length limited to `len`."
        function limit_length(a::$V, len::Real = 1.0)
            l = length(a)
            return l > 0 && len < l ? a / l * len : a
        end
        "Move toward `to` by at most `delta`."
        function move_toward(a::$V, to::$V, delta::Real)
            vd = to - a
            len = length(vd)
            return len <= delta || len < CMP_EPSILON ? to : a + vd / len * delta
        end
        "Projection of `a` onto `b`."
        project(a::$V, b::$V) = b * (dot(a, b) / length_squared(b))
        "Component of `a` along the plane defined by `normal`."
        slide(a::$V, normal::$V) = a - normal * dot(a, normal)
        "Reflection of `a` off the plane defined by `normal` (\"bounce\")."
        bounce(a::$V, normal::$V) = -reflect(a, normal)
        "Mirror of `a` across the line/plane defined by `normal`."
        reflect(a::$V, normal::$V) = 2 * normal * dot(a, normal) - a
    end
end
