# Behavior shared by all generated enum and bitfield types.

Base.Integer(x::GodotEnum) = x.value
Base.Int64(x::GodotEnum) = x.value
Base.convert(::Type{T}, x::GodotEnum) where {T <: Integer} = convert(T, x.value)
Base.isless(a::T, b::T) where {T <: GodotEnum} = isless(a.value, b.value)

function enum_name(x::GodotEnum)
    for (name, value) in Internals.enum_values(typeof(x))
        value == x.value && return name
    end
    return nothing
end

function Base.show(io::IO, x::GodotEnum)
    name = enum_name(x)
    name === nothing ? print(io, nameof(typeof(x)), "(", x.value, ")") : print(io, name)
end

function Base.show(io::IO, x::GodotBitfield)
    name = enum_name(x)
    name === nothing || return print(io, name)
    parts = [String(n) for (n, v) in Internals.enum_values(typeof(x)) if v != 0 && (x.value & v) == v]
    isempty(parts) ? print(io, nameof(typeof(x)), "(", x.value, ")") : print(io, join(parts, " | "))
end

Base.:|(a::T, b::T) where {T <: GodotBitfield} = T(a.value | b.value)
Base.:&(a::T, b::T) where {T <: GodotBitfield} = T(a.value & b.value)
Base.xor(a::T, b::T) where {T <: GodotBitfield} = T(xor(a.value, b.value))
Base.:~(a::T) where {T <: GodotBitfield} = T(~a.value)
Base.iszero(a::GodotBitfield) = iszero(a.value)
"`flag in flags` tests whether all bits of `flag` are set in `flags`."
Base.in(flag::T, flags::T) where {T <: GodotBitfield} = (flags.value & flag.value) == flag.value
