# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Mapping of GDExtension C types (as spelled in gdextension_interface.json) to Julia `ccall` types.

const C_SCALARS = Dict(
    "void" => "Cvoid",
    "int8_t" => "Int8", "uint8_t" => "UInt8",
    "int16_t" => "Int16", "uint16_t" => "UInt16",
    "int32_t" => "Int32", "uint32_t" => "UInt32",
    "int64_t" => "Int64", "uint64_t" => "UInt64",
    "size_t" => "Csize_t",
    "char" => "UInt8", "char16_t" => "UInt16", "char32_t" => "UInt32", "wchar_t" => "Cwchar_t",
    "float" => "Cfloat", "double" => "Cdouble",
    "bool" => "Bool",
)

# Pointers to character data keep their element type so Julia `String`s can be passed directly.
const C_CHAR_POINTEES = Dict("char" => "Ptr{UInt8}", "char16_t" => "Ptr{UInt16}", "char32_t" => "Ptr{UInt32}",
                             "wchar_t" => "Ptr{Cwchar_t}")

strip_const(t::AbstractString) = strip(replace(strip(t), r"^const\s+" => ""))

"""
    julia_ctype(ctype, named) -> String

Julia spelling of a C type. `named` holds every type name defined by the interface JSON (emitted as Julia
aliases or structs). Pointers other than character pointers become `Ptr{Cvoid}` so callers can pass any
`Ref`/`Ptr` without conversions.
"""
function julia_ctype(ctype::AbstractString, named::AbstractSet{<:AbstractString})
    t = strip_const(ctype)
    if endswith(t, "*")
        pointee = strip_const(t[1:(end - 1)])
        return get(C_CHAR_POINTEES, pointee, "Ptr{Cvoid}")
    end
    haskey(C_SCALARS, t) && return C_SCALARS[t]
    t in named && return String(t)
    error("unsupported C type: $ctype")
end

const JULIA_KEYWORDS = Set(["begin", "end", "function", "type", "module", "global", "local", "let", "quote",
                            "do", "for", "while", "if", "else", "elseif", "try", "catch", "finally", "return",
                            "break", "continue", "macro", "struct", "mutable", "abstract", "primitive", "import",
                            "using", "export", "const", "baremodule", "where", "in", "isa"])

"Escape identifiers that collide with Julia keywords by appending an underscore."
safe_name(name::AbstractString) = name in JULIA_KEYWORDS ? string(name, "_") : String(name)
