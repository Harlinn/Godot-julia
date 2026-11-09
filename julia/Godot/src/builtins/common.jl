# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Scalar math shared by the builtin types and `Mathf`.
# Ported from Godot's core/math/math_funcs.h and GodotSharp/Core/Mathf.cs, MathfEx.cs (MIT, Godot contributors).

"Godot's `real_t`: `Float32` or `Float64` depending on the engine build the bindings were generated for."
const real_t = FFI.real_t

# Engine tolerances (core/math/math_defs.h). `is_equal_approx` uses CMP_EPSILON, like GDScript and the engine.
const CMP_EPSILON = 1e-5
const UNIT_EPSILON = 1e-3

@inline _rt(x) = convert(real_t, x)
@inline _round(x) = round(x, RoundNearestTiesAway)
@inline _sign(x) = x > 0 ? one(x) : x < 0 ? -one(x) : zero(x)
@inline _min(a, b) = a < b ? a : b
@inline _max(a, b) = a > b ? a : b
@inline _clamp(x, lo, hi) = x < lo ? lo : (x > hi ? hi : x)
# Math::acos/asin clamp out-of-range input.
@inline _acos(x) = x < -1 ? oftype(float(x), π) : x > 1 ? zero(float(x)) : acos(x)
@inline _asin(x) = x < -1 ? -oftype(float(x), π) / 2 : x > 1 ? oftype(float(x), π) / 2 : asin(x)
@inline _fposmod(x::Real, y::Real) = (v = rem(x, y); ((v < 0 && y > 0) || (v > 0 && y < 0)) && (v += y); v + zero(v))
@inline _posmod(x::Integer, y::Integer) = (v = rem(x, y); ((v < 0 && y > 0) || (v > 0 && y < 0)) && (v += y); v)

"""
    is_equal_approx(a, b[, tolerance])

`true` if `a` and `b` are approximately equal (Godot semantics: relative tolerance `1e-5`, at least `1e-5` absolute).
Defined for numbers and every builtin math type; `isapprox` without keywords forwards to it for builtins.
"""
function is_equal_approx(a::Real, b::Real)
    a == b && return true
    tolerance = CMP_EPSILON * abs(a)
    tolerance < CMP_EPSILON && (tolerance = CMP_EPSILON)
    return abs(a - b) < tolerance
end
is_equal_approx(a::Real, b::Real, tolerance::Real) = a == b || abs(a - b) < tolerance

"`true` if `x` is within `1e-5` of zero (for builtins: every component)."
is_zero_approx(x::Real) = abs(x) < CMP_EPSILON

"`true` if `x` is neither infinite nor NaN (for builtins: every component)."
is_finite(x::Real) = isfinite(x)

"Linear interpolation: `from + (to - from) * weight`."
lerp(from::Real, to::Real, weight::Real) = from + (to - from) * weight

"Move `from` toward `to` by at most `delta`."
move_toward(from::Real, to::Real, delta::Real) = abs(to - from) <= delta ? to : from + _sign(to - from) * delta

"Snap `value` to the nearest multiple of `step` (unchanged when `step` is zero)."
snapped(value::AbstractFloat, step::Real) = step != 0 ? floor(value / step + 0.5) * step : value
snapped(value::Integer, step::Integer) = step != 0 ? Int64(floor(value / step + 0.5)) * step : Int64(value)
snapped(value::Real, step::Real) = snapped(float(value), step)

"Positive modulo: like `rem`, but the result has the sign of `y`."
posmod(x::Integer, y::Integer) = _posmod(x, y)
posmod(x::Real, y::Real) = _fposmod(promote(float(x), float(y))...)

"Cubic interpolation between `from` and `to` using the neighbors `pre` and `post`."
function cubic_interpolate(from::Real, to::Real, pre::Real, post::Real, weight::Real)
    return 0.5 * ((from * 2.0) + (-pre + to) * weight + (2.0 * pre - 5.0 * from + 4.0 * to - post) * (weight * weight) +
                  (-pre + 3.0 * from - 3.0 * to + post) * (weight * weight * weight))
end

"Cubic interpolation with explicit time values for the points (Barry-Goldman)."
function cubic_interpolate_in_time(from::Real, to::Real, pre::Real, post::Real, weight::Real, to_t::Real, pre_t::Real,
                                   post_t::Real)
    t = lerp(0.0, to_t, weight)
    a1 = lerp(pre, from, pre_t == 0 ? 0.0 : (t - pre_t) / -pre_t)
    a2 = lerp(from, to, to_t == 0 ? 0.5 : t / to_t)
    a3 = lerp(to, post, post_t - to_t == 0 ? 1.0 : (t - to_t) / (post_t - to_t))
    b1 = lerp(a1, a2, to_t - pre_t == 0 ? 0.0 : (t - pre_t) / (to_t - pre_t))
    b2 = lerp(a2, a3, post_t == 0 ? 1.0 : t / post_t)
    return lerp(b1, b2, to_t == 0 ? 0.5 : t / to_t)
end

"Point at `t` on the cubic Bézier curve defined by `start`, two control points and `end_`."
function bezier_interpolate(start::Real, control_1::Real, control_2::Real, end_::Real, t::Real)
    omt = 1.0 - t
    omt2 = omt * omt
    omt3 = omt2 * omt
    t2 = t * t
    t3 = t2 * t
    return start * omt3 + control_1 * omt2 * t * 3.0 + control_2 * omt * t2 * 3.0 + end_ * t3
end

"Derivative at `t` of the cubic Bézier curve defined by `start`, two control points and `end_`."
function bezier_derivative(start::Real, control_1::Real, control_2::Real, end_::Real, t::Real)
    omt = 1.0 - t
    omt2 = omt * omt
    t2 = t * t
    return (control_1 - start) * 3.0 * omt2 + (control_2 - control_1) * 6.0 * omt * t + (end_ - control_2) * 3.0 * t2
end

# Angle helpers used by both Mathf and the builtins.
_angle_difference(from, to) = (d = rem(to - from, 2π); rem(2d, 2π) - d)
_lerp_angle(from, to, weight) = from + _angle_difference(from, to) * weight

function _wrap_angles(from, to, pre, post)
    from_rot = rem(from, 2π)
    pre_diff = rem(pre - from_rot, 2π)
    pre_rot = from_rot + rem(2.0 * pre_diff, 2π) - pre_diff
    to_diff = rem(to - from_rot, 2π)
    to_rot = from_rot + rem(2.0 * to_diff, 2π) - to_diff
    post_diff = rem(post - to_rot, 2π)
    post_rot = to_rot + rem(2.0 * post_diff, 2π) - post_diff
    return from_rot, to_rot, pre_rot, post_rot
end
