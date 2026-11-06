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
