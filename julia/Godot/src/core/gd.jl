# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Hand-written additions to `GD` (C#'s GD class has these as conveniences over the engine API).

"""
    GD.load(path) -> Union{Nothing, Resource}
    GD.load(T, path) -> T

Load a resource through `ResourceLoader` (C#'s `GD.Load<T>`). The typed form throws if the resource is missing or not a `T`.
"""
load(path::AbstractString) = Godot.load(Godot.ResourceLoader, path)

function load(::Type{T}, path::AbstractString) where {T <: Godot.Resource}
    r = load(path)
    r isa T || throw(ArgumentError("resource at $path is $(r === nothing ? "missing" : Godot.class_name(r)), not $T"))
    return r
end
