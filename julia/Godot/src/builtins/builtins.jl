# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Hand-written builtin math types (analog of GodotSharp/Core/*.cs). Layouts come from generated/builtin_structs.jl.

include("common.jl")
include("vectors.jl")
include("vector_extras.jl")
include("rect2.jl")
include("transform2d.jl")
include("basis.jl")
include("quaternion.jl")
include("transform3d.jl")
include("plane_aabb.jl")
include("projection.jl")
include("okcolor.jl")
include("color.jl")
include("mathf.jl")

export real_t, Mathf, dot, cross, is_equal_approx, is_zero_approx, is_finite, lerp, move_toward, snapped, posmod,
       cubic_interpolate, cubic_interpolate_in_time, bezier_interpolate, bezier_derivative, posmodv, length_squared,
       distance_squared_to, minf, maxf, clampf, snappedf, mini, maxi, clampi, snappedi, distance_to, direction_to,
       is_normalized, normalized, inverse, limit_length, project, slide, bounce, reflect, max_axis_index, min_axis_index,
       aspect, from_angle, angle_to, angle_to_point, rotated, orthogonal, slerp, signed_angle_to, outer,
       octahedron_encode, octahedron_decode, get_end, get_area, has_area, encloses, intersection, expand, grow,
       grow_individual, grow_side, get_center, has_point, intersects, get_support, basis_xform, basis_xform_inv,
       determinant, affine_inverse, get_rotation, get_origin, get_scale, get_skew, orthonormalized, rotated_local,
       scaled, scaled_local, translated, translated_local, interpolate_with, is_conformal, looking_at, get_column,
       get_row, tdotx, tdoty, tdotz, from_scale, transposed, is_orthonormal, get_rotation_quaternion, get_euler,
       from_euler, get_axis, get_angle, slerpni, spherical_cubic_interpolate, spherical_cubic_interpolate_in_time,
       is_point_over, intersect_3, intersects_ray, intersects_segment, get_volume, has_volume, has_surface,
       intersects_plane, get_longest_axis, get_longest_axis_index, get_longest_axis_size, get_shortest_axis,
       get_shortest_axis_index, get_shortest_axis_size, get_endpoint, get_projection_plane, get_z_far, get_z_near,
       get_viewport_half_extents, get_far_plane_half_extents, get_aspect, get_fov, is_orthogonal, get_pixels_per_meter,
       get_lod_multiplier, perspective_znear_adjusted, flipped_y, jitter_offseted, get_fovy, create_depth_correction,
       create_light_atlas_rect, create_perspective, create_perspective_hmd, create_for_hmd, create_orthogonal,
       create_orthogonal_aspect, create_frustum, create_frustum_aspect, create_fit_aabb, to_hsv, to_argb32, to_abgr32,
       to_rgba32, to_argb64, to_abgr64, to_rgba64, to_html, inverted, lightened, darkened, blend, get_luminance,
       srgb_to_linear, linear_to_srgb, hex, hex64, from_rgba8, from_rgbe9995, from_hsv, from_ok_hsl, html_is_valid, html,
       named, from_string
