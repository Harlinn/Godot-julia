# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Mathf: Godot's scalar math helpers (C#: `Godot.Mathf`, `MathfEx`).
# Ported from Godot's core/math/math_funcs.h and GodotSharp/Core/Mathf.cs, MathfEx.cs (MIT, Godot contributors).
# Functions that Julia's Base already provides (sin, sqrt, clamp, sign, abs, floor, ...) are not duplicated.

"""
    Godot.Mathf

Scalar math helpers matching C#'s `Mathf`: `lerp`, `inverse_lerp`, `remap`, `smoothstep`, `wrap`, `pingpong`,
`snapped`, `move_toward`, `deg_to_rad`, `ease`, ... and the constants `TAU`, `PI`, `INF`, `NAN`, `E`, `SQRT2`,
`EPSILON`. Use Base for the rest (`sin`, `clamp`, `sign`, `sincos`, `isfinite`, ...).
"""
module Mathf

using ..Godot: Godot, CMP_EPSILON, _sign, _clamp, _angle_difference, _lerp_angle, _wrap_angles, _round
import ..Godot: lerp, move_toward, snapped, posmod, cubic_interpolate, cubic_interpolate_in_time, bezier_interpolate,
                bezier_derivative, is_equal_approx, is_zero_approx, is_finite

const TAU = 2π
const PI = Float64(π)
const INF = Inf
const NAN = NaN
const E = Float64(ℯ)
const SQRT2 = sqrt(2.0)
"Tolerance of `is_equal_approx` / `is_zero_approx` (the engine's CMP_EPSILON)."
const EPSILON = CMP_EPSILON

"Degrees to radians."
deg_to_rad(deg::Real) = deg * (π / 180)
"Radians to degrees."
rad_to_deg(rad::Real) = rad * (180 / π)
"Decibels to linear energy."
db_to_linear(db::Real) = exp(db * 0.11512925464970228420089957273422)
"Linear energy to decibels."
linear_to_db(lin::Real) = log(lin) * 8.6858896380650365530225783783321
"Interpolation factor of `weight` between `from` and `to` (inverse of `lerp`)."
inverse_lerp(from::Real, to::Real, weight::Real) = (weight - from) / (to - from)
"Map `value` from `[istart, istop]` to `[ostart, ostop]`."
remap(value::Real, istart::Real, istop::Real, ostart::Real, ostop::Real) =
    lerp(ostart, ostop, inverse_lerp(istart, istop, value))
"Smooth Hermite interpolation of `s` between `from` and `to` (0 below, 1 above)."
function smoothstep(from::Real, to::Real, s::Real)
    if is_equal_approx(from, to)
        return from <= to ? (s <= from ? 0.0 : 1.0) : (s <= to ? 1.0 : 0.0)
    end
    t = _clamp((s - from) / (to - from), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)
end
"Shortest signed difference between two angles (radians)."
angle_difference(from::Real, to::Real) = _angle_difference(from, to)
"Interpolate between two angles (radians) along the shortest path."
lerp_angle(from::Real, to::Real, weight::Real) = _lerp_angle(from, to, weight)
"Rotate angle `from` toward `to` by at most `delta` radians."
function rotate_toward(from::Real, to::Real, delta::Real)
    diff = _angle_difference(from, to)
    adiff = abs(diff)
    return from + _clamp(delta, adiff - π, adiff) * (diff >= 0 ? 1.0 : -1.0)
end
"`cubic_interpolate` for angles, taking the shortest path."
cubic_interpolate_angle(from::Real, to::Real, pre::Real, post::Real, weight::Real) =
    cubic_interpolate(_wrap_angles(from, to, pre, post)..., weight)
"`cubic_interpolate_in_time` for angles, taking the shortest path."
cubic_interpolate_angle_in_time(from::Real, to::Real, pre::Real, post::Real, weight::Real, to_t::Real, pre_t::Real,
                                post_t::Real) =
    cubic_interpolate_in_time(_wrap_angles(from, to, pre, post)..., weight, to_t, pre_t, post_t)
"Wrap `value` into `[min, max)`."
function wrap(value::Integer, lo::Integer, hi::Integer)
    range = hi - lo
    return range == 0 ? lo : lo + Godot._posmod(value - lo, range)
end
function wrap(value::Real, lo::Real, hi::Real)
    range = hi - lo
    is_zero_approx(range) && return float(lo)
    result = value - range * floor((value - lo) / range)
    return is_equal_approx(result, hi) ? float(lo) : result
end
"Bounce `value` back and forth between 0 and `length`."
function pingpong(value::Real, length::Real)
    length == 0 && return zero(float(value))
    x = (value - length) / (length * 2)
    return abs((x - floor(x)) * length * 2 - length)
end
"Easing curve: `curve > 1` ease in, `0 < curve < 1` ease out, `curve < 0` ease in-out."
function ease(x::Real, curve::Real)
    x = _clamp(float(x), 0.0, 1.0)
    if curve > 0
        return curve < 1 ? 1 - (1 - x)^(1 / curve) : x^curve
    elseif curve < 0
        return x < 0.5 ? (x * 2)^(-curve) * 0.5 : (1 - (1 - (x - 0.5) * 2)^(-curve)) * 0.5 + 0.5
    end
    return 0.0
end
"Number of decimal places of `step` (up to 10)."
function step_decimals(step::Real)
    a = abs(Float64(step))
    decs = a - trunc(a)
    for i in 0:9
        decs >= 0.9999 / 10.0^i && return i
    end
    return 0
end
"Smallest power of two `>= x` (0 for 0)."
function nearest_po2(x::Integer)
    v = UInt32(x % UInt32) - 0x1
    v |= v >> 1
    v |= v >> 2
    v |= v >> 4
    v |= v >> 8
    v |= v >> 16
    return Int64(v + 0x1)
end
"`floor` as an `Int`."
floor_to_int(x::Real) = floor(Int, x)
"`ceil` as an `Int`."
ceil_to_int(x::Real) = ceil(Int, x)
"Round half away from zero, as an `Int`."
round_to_int(x::Real) = Int(_round(x))

export TAU, PI, INF, NAN, E, SQRT2, EPSILON, deg_to_rad, rad_to_deg, db_to_linear, linear_to_db, inverse_lerp, remap,
       smoothstep, angle_difference, lerp_angle, rotate_toward, cubic_interpolate_angle, cubic_interpolate_angle_in_time,
       wrap, pingpong, ease, step_decimals, nearest_po2, floor_to_int, ceil_to_int, round_to_int, lerp, move_toward,
       snapped, posmod, cubic_interpolate, cubic_interpolate_in_time, bezier_interpolate, bezier_derivative,
       is_equal_approx, is_zero_approx, is_finite

end # module Mathf
