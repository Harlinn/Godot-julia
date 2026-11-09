# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Builtin math golden tests against Godot. parity: 3.1–3.3
using Godot: GodotEnum, MATH_TYPES
using LinearAlgebra: LinearAlgebra

# --- Golden tests: GDScript expressions evaluated by Godot (scripts/make_math_golden.jl) ------------------------------

const GD_FUNCTIONS = Dict(:lerpf => :lerp, :fposmod => :posmod, :snappedf => :snapped, :snappedi => :snapped,
                          :wrapf => :(Mathf.wrap), :wrapi => :(Mathf.wrap), :inverse_lerp => :(Mathf.inverse_lerp),
                          :remap => :(Mathf.remap), :smoothstep => :(Mathf.smoothstep),
                          :rotate_toward => :(Mathf.rotate_toward), :angle_difference => :(Mathf.angle_difference),
                          :lerp_angle => :(Mathf.lerp_angle), :pingpong => :(Mathf.pingpong), :ease => :(Mathf.ease),
                          :deg_to_rad => :(Mathf.deg_to_rad), :rad_to_deg => :(Mathf.rad_to_deg),
                          :db_to_linear => :(Mathf.db_to_linear), :linear_to_db => :(Mathf.linear_to_db),
                          :nearest_po2 => :(Mathf.nearest_po2), :step_decimals => :(Mathf.step_decimals),
                          :cubic_interpolate_angle => :(Mathf.cubic_interpolate_angle),
                          :cubic_interpolate_angle_in_time => :(Mathf.cubic_interpolate_angle_in_time))
const GD_CONSTANTS = Dict(:PI => :(Mathf.PI), :TAU => :(Mathf.TAU), :INF => :(Mathf.INF), :NAN => :(Mathf.NAN))
const TYPE_NAMES = Set(nameof.(MATH_TYPES))

"Translate a GDScript expression (parsed by Julia) to the Julia API (ADR 0003 naming)."
function translate(ex)
    ex isa Symbol && return get(GD_CONSTANTS, ex, ex)
    ex isa Expr || return ex
    if ex.head === :call
        f = ex.args[1]
        args = map(translate, ex.args[2:end])
        if f isa Expr && f.head === :.
            return Expr(:call, f.args[2].value, translate(f.args[1]), args...)   # recv.m(args) / Type.static(args)
        end
        return Expr(:call, get(GD_FUNCTIONS, f, f), args...)
    elseif ex.head === :. && ex.args[2] isa QuoteNode
        recv = ex.args[1]
        recv in TYPE_NAMES && return Symbol(recv, "_", ex.args[2].value)        # Type.CONSTANT
        return Expr(:., translate(recv), ex.args[2])
    end
    return Expr(ex.head, map(translate, ex.args)...)
end

"Evaluate Godot's `var_to_str` output (only literals and math constructors are accepted)."
function golden_value(ex)
    ex isa Number && return ex
    ex isa String && return ex
    ex === :inf && return Inf
    ex === :nan && return NaN
    ex === :null && return nothing
    if ex isa Expr && ex.head === :call
        f = ex.args[1]
        f === :- && length(ex.args) == 2 && return -golden_value(ex.args[2])
        f in TYPE_NAMES && return getglobal(Godot, f)(map(golden_value, ex.args[2:end])...)
    end
    error("unexpected golden value: $ex")
end

flat(x::Real) = (Float64(x),)
flat(x::GodotEnum) = (Float64(Int(x)),)
flat(x) = reduce((a, f) -> (a..., flat(getfield(x, f))...), fieldnames(typeof(x)); init = ())
close_to(a::Real, b::Real) = (isnan(a) && isnan(b)) || a == b || abs(a - b) <= 2e-4 + 2e-4 * abs(b)
matches(actual::Bool, expected::Bool) = actual == expected
matches(actual::Union{Real, GodotEnum}, expected::Real) = !(actual isa Bool) && close_to(flat(actual)[1], expected)
matches(actual::AbstractString, expected::AbstractString) = actual == expected
matches(::Nothing, ::Nothing) = true
matches(actual, expected) = typeof(actual) == typeof(expected) && typeof(expected) in MATH_TYPES &&
                            all(close_to.(flat(actual), flat(expected)))

const GOLDEN = joinpath(@__DIR__, "fixtures", "math_golden.txt")

@testset "builtin math" begin
    @testset "golden values from Godot" begin
        failures = String[]
        n = 0
        for line in eachline(GOLDEN)
            (isempty(line) || startswith(line, "#")) && continue
            gd, expected_text = split(line, '\t')
            expected = golden_value(Meta.parse(expected_text))
            jl = translate(Meta.parse(replace(gd, r"\.end\b" => ".end_")))
            actual = try
                Core.eval(@__MODULE__, jl)
            catch err
                push!(failures, "$gd\n    julia: $jl\n    error: $(sprint(showerror, err))")
                continue
            end
            n += 1
            matches(actual, expected) || push!(failures, "$gd\n    julia: $jl\n    got $(repr(actual)), Godot: $expected_text")
        end
        isempty(failures) || @error "golden mismatches ($(length(failures))):\n" * join(failures, "\n")
        @test isempty(failures)
        @test n > 600
    end

    @testset "construction, layout, conversions" begin
        @test isbitstype(Vector2) && isbitstype(Basis) && isbitstype(Projection) && isbitstype(Color)
        @test Vector2() == Vector2(0, 0) && Vector3i() == Vector3i(0, 0, 0)
        @test Basis() == Basis_IDENTITY && Transform3D() == Transform3D_IDENTITY && Quaternion() == Quaternion_IDENTITY
        @test Transform2D() == Transform2D_IDENTITY && Projection() == Projection_IDENTITY && Color() == Color(0, 0, 0, 1)
        b = Basis(Vector3(1, 2, 3), Vector3(4, 5, 6), Vector3(7, 8, 9))
        @test b.x == Vector3(1, 2, 3) && b.z == Vector3(7, 8, 9)          # columns, as in GDScript and C#
        @test b.row0 == Vector3(1, 4, 7) && b[1, 3] == 7 && get_column(b, 2) == Vector3(4, 5, 6)
        @test Vector2i(Vector2(1.9, -1.9)) == Vector2i(1, -1) && Vector2(Vector2i(2, 3)) == Vector2(2, 3)
        @test Rect2(Rect2i(1, 2, 3, 4)) == Rect2(1, 2, 3, 4)
        @test Vector2(3, 4)[1] == 3 && Vector2(3, 4)[Vector2_AXIS_Y] == 4 && Vector4(1, 2, 3, 4)[4] == 4
        @test_throws BoundsError Vector2(1, 2)[3]
        @test Color("aliceblue") == Color_ALICE_BLUE && Color("Alice Blue") == Color_ALICE_BLUE
        @test Color(0xff0000ff) == Color(1, 0, 0, 1)
        @test_throws ArgumentError html(Color, "zz")
        @test Rect2(1, 2, 3, 4).end_ == Vector2(4, 6) && :end_ in propertynames(Rect2())
        @test Transform2D(0.5, Vector2()).rotation ≈ 0.5
        @test Color(1, 0, 0).h == 0 && Color(1, 0.5, 0).r8 == 255
        @test zero(Vector3) == Vector3_ZERO && one(Basis) == Basis_IDENTITY
    end

    @testset "show round-trips" begin
        for x in (Vector2(1.5, -2), Vector3i(1, 2, 3), Rect2(1, 2, 3, 4), Transform2D(0.3, Vector2(1, 2)),
                  from_euler(Basis, Vector3(0.1, 0.2, 0.3)), Quaternion(1, 2, 3, 4), Plane(1, 2, 3, 4),
                  AABB(Vector3(1, 2, 3), Vector3(4, 5, 6)), Color(0.1, 0.2, 0.3, 0.4), Projection_IDENTITY,
                  Transform3D(Basis(Vector3(0, 1, 0), 0.3), Vector3(1, 2, 3)))
            @test eval(Meta.parse(repr(x))) == x
        end
        @test repr(Vector2(1, 2)) == "Vector2(1.0, 2.0)"
    end

    @testset "Julia idioms" begin
        @test Vector2(1, 2) ≈ Vector2(1.000001, 2)
        @test !(Vector2(1, 2) ≈ Vector2(1.01, 2))
        @test isapprox(Vector2(1, 2), Vector2(1.01, 2); atol = 0.1)
        @test sort([Vector2(2, 0), Vector2(1, 5), Vector2(1, 2)]) == [Vector2(1, 2), Vector2(1, 5), Vector2(2, 0)]
        @test LinearAlgebra.norm(Vector3(2, 3, 6)) == 7 && LinearAlgebra.normalize(Vector2(3, 4)) == Vector2(0.6, 0.8)
        @test dot === LinearAlgebra.dot && LinearAlgebra.det(Basis()) == 1 && LinearAlgebra.cross(Vector3(1, 0, 0), Vector3(0, 1, 0)) == Vector3(0, 0, 1)
        @test inv(Transform2D(0.5, Vector2(2, 1.5), 0.2, Vector2(3, -1))) * Transform2D(0.5, Vector2(2, 1.5), 0.2, Vector2(3, -1)) ≈ Transform2D()
        @test hash(Vector2(1, 2)) == hash(Vector2(1, 2)) && Dict(Vector2i(1, 2) => 1)[Vector2i(1, 2)] == 1
        @test Mathf.TAU == 2π && Mathf.EPSILON == 1e-5 && Mathf.wrap(7, 0, 5) == 2 && Mathf.round_to_int(2.5) == 3
        @test lerp(1.0, 3.0, 0.5) == 2.0 && snapped(7, 5) == 5 && posmod(-1, 3) == 2
        # C#-only members found by scripts/api_diff.jl (phase 17).
        @test inverse(Vector2(2, 4)) == Vector2(0.5, 0.25)
        pl = Plane(Vector3(0, 1, 0), 3)
        @test (pl.x, pl.y, pl.z, pl.d) == (0, 1, 0, 3) && :x in propertynames(pl)
        @test Vector2i_MIN == Vector2i(typemin(Int32), typemin(Int32)) && Vector3i_MAX.z == typemax(Int32)
    end

    @testset "allocation-free" begin
        t2 = Transform2D(0.5, Vector2(2, 1.5), 0.2, Vector2(3, -1))
        b = from_euler(Basis, Vector3(0.3, -0.5, 1.1))
        t3 = Transform3D(b, Vector3(4, -2, 1))
        q = Quaternion(b)
        p = create_perspective(Projection, 70, 1.5, 0.1, 50)
        a = AABB(Vector3(1, 2, 3), Vector3(2, 1, 4))
        ops = (() -> rotated(Vector2(1, 2), 0.3), () -> normalized(Vector3(1, 2, 3)), () -> slerp(Vector3(1, 2, 3), Vector3(3, 1, 0), 0.4),
               () -> Vector2i(7, -8) / 3, () -> t2 * t2, () -> affine_inverse(t2), () -> t2 * Rect2(1, 2, 3, 4),
               () -> b * b, () -> inverse(b), () -> get_euler(b), () -> get_rotation_quaternion(b), () -> slerp(q, Quaternion(), 0.3),
               () -> spherical_cubic_interpolate(q, Quaternion(), q, Quaternion(), 0.3), () -> t3 * t3,
               () -> interpolate_with(t3, Transform3D(), 0.4), () -> t3 * a, () -> a * t3, () -> t3 * Plane(0, 1, 0, 2),
               () -> p * p, () -> inverse(p), () -> get_fov(p), () -> get_projection_plane(p, 2),
               () -> from_hsv(Color, 0.3, 0.5, 0.5), () -> from_ok_hsl(Color, 0.3, 0.5, 0.5), () -> lerp(Color(), Color(1, 1, 1), 0.5),
               () -> intersects_ray(a, Vector3(), Vector3(1, 1, 2.5)), () -> Mathf.smoothstep(0, 1, 0.3))
        for op in ops
            op()
            @test (@allocated op()) == 0
        end
    end
end
