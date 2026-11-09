# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# OKLab / OKHSL conversions used by Color.from_ok_hsl and the ok_hsl_* properties.
# Ported from Godot's thirdparty/misc/ok_color.h (Björn Ottosson, MIT).

module OkColor

const K1 = 0.206f0
const K2 = 0.03f0
const K3 = (1f0 + K1) / (1f0 + K2)

srgb_transfer(a::Float32) = 0.0031308f0 >= a ? 12.92f0 * a : 1.055f0 * a^0.4166666666666667f0 - 0.055f0
srgb_transfer_inv(a::Float32) = 0.04045f0 < a ? ((a + 0.055f0) / 1.055f0)^2.4f0 : a / 12.92f0

function linear_srgb_to_oklab(r::Float32, g::Float32, b::Float32)
    l = cbrt(0.4122214708f0 * r + 0.5363325363f0 * g + 0.0514459929f0 * b)
    m = cbrt(0.2119034982f0 * r + 0.6806995451f0 * g + 0.1073969566f0 * b)
    s = cbrt(0.0883024619f0 * r + 0.2817188376f0 * g + 0.6299787005f0 * b)
    return (0.2104542553f0 * l + 0.7936177850f0 * m - 0.0040720468f0 * s,
            1.9779984951f0 * l - 2.4285922050f0 * m + 0.4505937099f0 * s,
            0.0259040371f0 * l + 0.7827717662f0 * m - 0.8086757660f0 * s)
end

function oklab_to_linear_srgb(L::Float32, a::Float32, b::Float32)
    l = (L + 0.3963377774f0 * a + 0.2158037573f0 * b)^3
    m = (L - 0.1055613458f0 * a - 0.0638541728f0 * b)^3
    s = (L - 0.0894841775f0 * a - 1.2914855480f0 * b)^3
    return (4.0767416621f0 * l - 3.3077115913f0 * m + 0.2309699292f0 * s,
            -1.2684380046f0 * l + 2.6097574011f0 * m - 0.3413193965f0 * s,
            -0.0041960863f0 * l - 0.7034186147f0 * m + 1.7076147010f0 * s)
end

function compute_max_saturation(a::Float32, b::Float32)
    if -1.88170328f0 * a - 0.80936493f0 * b > 1
        k0, k1, k2, k3, k4 = 1.19086277f0, 1.76576728f0, 0.59662641f0, 0.75515197f0, 0.56771245f0
        wl, wm, ws = 4.0767416621f0, -3.3077115913f0, 0.2309699292f0
    elseif 1.81444104f0 * a - 1.19445276f0 * b > 1
        k0, k1, k2, k3, k4 = 0.73956515f0, -0.45954404f0, 0.08285427f0, 0.12541070f0, 0.14503204f0
        wl, wm, ws = -1.2684380046f0, 2.6097574011f0, -0.3413193965f0
    else
        k0, k1, k2, k3, k4 = 1.35733652f0, -0.00915799f0, -1.15130210f0, -0.50559606f0, 0.00692167f0
        wl, wm, ws = -0.0041960863f0, -0.7034186147f0, 1.7076147010f0
    end
    S = k0 + k1 * a + k2 * b + k3 * a * a + k4 * a * b
    k_l = 0.3963377774f0 * a + 0.2158037573f0 * b
    k_m = -0.1055613458f0 * a - 0.0638541728f0 * b
    k_s = -0.0894841775f0 * a - 1.2914855480f0 * b
    l_ = 1f0 + S * k_l
    m_ = 1f0 + S * k_m
    s_ = 1f0 + S * k_s
    l, m, s = l_^3, m_^3, s_^3
    l_dS, m_dS, s_dS = 3f0 * k_l * l_ * l_, 3f0 * k_m * m_ * m_, 3f0 * k_s * s_ * s_
    l_dS2, m_dS2, s_dS2 = 6f0 * k_l * k_l * l_, 6f0 * k_m * k_m * m_, 6f0 * k_s * k_s * s_
    f = wl * l + wm * m + ws * s
    f1 = wl * l_dS + wm * m_dS + ws * s_dS
    f2 = wl * l_dS2 + wm * m_dS2 + ws * s_dS2
    return S - f * f1 / (f1 * f1 - 0.5f0 * f * f2)
end

function find_cusp(a::Float32, b::Float32)
    S_cusp = compute_max_saturation(a, b)
    r, g, bl = oklab_to_linear_srgb(1f0, S_cusp * a, S_cusp * b)
    L_cusp = cbrt(1f0 / max(max(r, g), bl))
    return L_cusp, L_cusp * S_cusp
end

function find_gamut_intersection(a::Float32, b::Float32, L1::Float32, C1::Float32, L0::Float32, cusp)
    cL, cC = cusp
    if ((L1 - L0) * cC - (cL - L0) * C1) <= 0f0
        return cC * L0 / (C1 * cL + cC * (L0 - L1))
    end
    t = cC * (L0 - 1f0) / (C1 * (cL - 1f0) + cC * (L0 - L1))
    dL = L1 - L0
    dC = C1
    k_l = 0.3963377774f0 * a + 0.2158037573f0 * b
    k_m = -0.1055613458f0 * a - 0.0638541728f0 * b
    k_s = -0.0894841775f0 * a - 1.2914855480f0 * b
    l_dt, m_dt, s_dt = dL + dC * k_l, dL + dC * k_m, dL + dC * k_s
    L = L0 * (1f0 - t) + t * L1
    C = t * C1
    l_, m_, s_ = L + C * k_l, L + C * k_m, L + C * k_s
    l, m, s = l_^3, m_^3, s_^3
    ldt, mdt, sdt = 3 * l_dt * l_ * l_, 3 * m_dt * m_ * m_, 3 * s_dt * s_ * s_
    ldt2, mdt2, sdt2 = 6 * l_dt * l_dt * l_, 6 * m_dt * m_dt * m_, 6 * s_dt * s_dt * s_
    function step(w1, w2, w3)
        f = w1 * l + w2 * m + w3 * s - 1
        f1 = w1 * ldt + w2 * mdt + w3 * sdt
        f2 = w1 * ldt2 + w2 * mdt2 + w3 * sdt2
        u = f1 / (f1 * f1 - 0.5f0 * f * f2)
        return u >= 0f0 ? -f * u : floatmax(Float32)
    end
    t_r = step(4.0767416621f0, -3.3077115913f0, 0.2309699292f0)
    t_g = step(-1.2684380046f0, 2.6097574011f0, -0.3413193965f0)
    t_b = step(-0.0041960863f0, -0.7034186147f0, 1.7076147010f0)
    return t + min(t_r, min(t_g, t_b))
end

toe(x::Float32) = 0.5f0 * (K3 * x - K1 + sqrt((K3 * x - K1) * (K3 * x - K1) + 4 * K2 * K3 * x))
toe_inv(x::Float32) = (x * x + K1 * x) / (K3 * (x + K2))

function get_ST_mid(a::Float32, b::Float32)
    S = 0.11516993f0 + 1f0 / (7.44778970f0 + 4.15901240f0 * b +
                              a * (-2.19557347f0 + 1.75198401f0 * b +
                                   a * (-2.13704948f0 - 10.02301043f0 * b +
                                        a * (-4.24894561f0 + 5.38770819f0 * b + 4.69891013f0 * a))))
    T = 0.11239642f0 + 1f0 / (1.61320320f0 - 0.68124379f0 * b +
                              a * (0.40370612f0 + 0.90148123f0 * b +
                                   a * (-0.27087943f0 + 0.61223990f0 * b +
                                        a * (0.00299215f0 - 0.45399568f0 * b - 0.14661872f0 * a))))
    return S, T
end

function get_Cs(L::Float32, a::Float32, b::Float32)
    cusp = find_cusp(a, b)
    C_max = find_gamut_intersection(a, b, L, 1f0, L, cusp)
    S_max, T_max = cusp[2] / cusp[1], cusp[2] / (1 - cusp[1])
    k = C_max / min(L * S_max, (1 - L) * T_max)
    S_mid, T_mid = get_ST_mid(a, b)
    C_a = L * S_mid
    C_b = (1f0 - L) * T_mid
    C_mid = 0.9f0 * k * sqrt(sqrt(1f0 / (1f0 / (C_a^4) + 1f0 / (C_b^4))))
    C_a = L * 0.4f0
    C_b = (1f0 - L) * 0.8f0
    C_0 = sqrt(1f0 / (1f0 / (C_a * C_a) + 1f0 / (C_b * C_b)))
    return C_0, C_mid, C_max
end

function okhsl_to_srgb(h::Float32, s::Float32, l::Float32)
    l == 1f0 && return (1f0, 1f0, 1f0)
    l == 0f0 && return (0f0, 0f0, 0f0)
    a_ = cos(2f0 * Float32(π) * h)
    b_ = sin(2f0 * Float32(π) * h)
    L = toe_inv(l)
    C_0, C_mid, C_max = get_Cs(L, a_, b_)
    mid, mid_inv = 0.8f0, 1.25f0
    if s < mid
        t = mid_inv * s
        k_1 = mid * C_0
        k_2 = 1f0 - k_1 / C_mid
        C = t * k_1 / (1f0 - k_2 * t)
    else
        t = (s - mid) / (1 - mid)
        k_0 = C_mid
        k_1 = (1f0 - mid) * C_mid * C_mid * mid_inv * mid_inv / C_0
        k_2 = 1f0 - k_1 / (C_max - C_mid)
        C = k_0 + t * k_1 / (1f0 - k_2 * t)
    end
    r, g, b = oklab_to_linear_srgb(L, C * a_, C * b_)
    return srgb_transfer(r), srgb_transfer(g), srgb_transfer(b)
end

function srgb_to_okhsl(r::Float32, g::Float32, b::Float32)
    L, la, lb = linear_srgb_to_oklab(srgb_transfer_inv(r), srgb_transfer_inv(g), srgb_transfer_inv(b))
    C = sqrt(la * la + lb * lb)
    a_ = la / C
    b_ = lb / C
    h = 0.5f0 + 0.5f0 * atan(-lb, -la) / Float32(π)
    C_0, C_mid, C_max = get_Cs(L, a_, b_)
    mid, mid_inv = 0.8f0, 1.25f0
    if C < C_mid
        k_1 = mid * C_0
        k_2 = 1f0 - k_1 / C_mid
        t = C / (k_1 + k_2 * C)
        s = t * mid
    else
        k_0 = C_mid
        k_1 = (1f0 - mid) * C_mid * C_mid * mid_inv * mid_inv / C_0
        k_2 = 1f0 - k_1 / (C_max - C_mid)
        t = (C - k_0) / (k_1 + k_2 * (C - k_0))
        s = mid + (1f0 - mid) * t
    end
    return h, s, toe(L)
end

end # module OkColor
