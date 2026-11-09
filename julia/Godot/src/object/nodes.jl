# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Typed node lookups (need the generated `Node` class).
# Ported from GodotSharp/Core/Extensions/NodeExtensions.cs (MIT, Godot contributors).

"""
    get_node(T, node, path) -> T

`get_node(node, path)` cast to `T`; throws if the node is missing or not a `T` (C#'s `GetNode<T>`).
"""
function get_node(::Type{T}, node::Node, path::Internals.NodePathLike) where {T <: GodotObject}
    n = get_node_or_null(node, path)
    n === nothing && throw(ArgumentError("node not found: $(path isa NodePath ? path.path : path)"))
    return convert(T, n)
end

"`get_node_or_null(node, path)` as a `T`, or `nothing` (C#'s `GetNodeOrNull<T>`)."
get_node_or_null(::Type{T}, node::Node, path::Internals.NodePathLike) where {T <: GodotObject} =
    as(T, get_node_or_null(node, path))

"`get_child(node, idx)` (0-based, negative counts from the end) cast to `T` (C#'s `GetChild<T>`)."
get_child(::Type{T}, node::Node, idx::Integer, include_internal::Bool = false) where {T <: GodotObject} =
    convert(T, get_child(node, idx, include_internal))

"""
    get_child_or_null(T, node, idx, include_internal = false)

The child at `idx` as a `T`, or `nothing` when `idx` is out of range or the child is not a `T` (C#'s
`GetChildOrNull<T>`).
"""
function get_child_or_null(::Type{T}, node::Node, idx::Integer, include_internal::Bool = false) where {T <: GodotObject}
    n = get_child_count(node, include_internal)
    return -n <= idx < n ? as(T, get_child(node, idx, include_internal)) : nothing
end

"The node's owner cast to `T`; throws if it has none (C#'s `GetOwner<T>`)."
function get_owner(::Type{T}, node::Node) where {T <: GodotObject}
    o = get_owner(node)
    o === nothing && throw(ArgumentError("node has no owner"))
    return convert(T, o)
end
"The node's owner as a `T`, or `nothing` (C#'s `GetOwnerOrNull<T>`)."
get_owner_or_null(::Type{T}, node::Node) where {T <: GodotObject} = as(T, get_owner(node))

"The node's parent cast to `T`; throws if it has none (C#'s `GetParent<T>`)."
function get_parent(::Type{T}, node::Node) where {T <: GodotObject}
    p = get_parent(node)
    p === nothing && throw(ArgumentError("node has no parent"))
    return convert(T, p)
end
"The node's parent as a `T`, or `nothing` (C#'s `GetParentOrNull<T>`)."
get_parent_or_null(::Type{T}, node::Node) where {T <: GodotObject} = as(T, get_parent(node))

# Ported from GodotSharp/Core/Extensions/PackedSceneExtensions.cs (MIT, Godot contributors).

"""
    instantiate(T, scene, edit_state = PackedScene_GEN_EDIT_STATE_DISABLED) -> T

`instantiate(scene)` as a `T` (C#'s `PackedScene.Instantiate<T>`). Throws an `ArgumentError` when the root is not a
`T`; the instance is freed first, so nothing leaks.
"""
function instantiate(::Type{T}, scene::PackedScene, edit_state = PackedScene_GEN_EDIT_STATE_DISABLED) where {T <: GodotObject}
    n = instantiate(scene, edit_state)
    n isa T && return n
    what = n === nothing ? "nothing" : string(godot_class_name(typeof(n)))
    n === nothing || free(n)
    throw(ArgumentError("scene root is $what, not a $T"))
end
"`instantiate(scene)` as a `T`, or `nothing` (the instance is freed) when the root is not a `T` (C#'s `InstantiateOrNull<T>`)."
function instantiate_or_null(::Type{T}, scene::PackedScene, edit_state = PackedScene_GEN_EDIT_STATE_DISABLED) where {T <: GodotObject}
    n = instantiate(scene, edit_state)
    n isa T && return n
    n === nothing || free(n)
    return nothing
end
