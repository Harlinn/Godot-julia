"""
    Godot.FFI

Low-level access to the GDExtension C interface (analog of GodotSharp's `NativeInterop`). Everything here deals
in raw pointers and opaque, ABI-sized values; the user-facing API is built on top of it.

Ownership rules:
- A `Raw*`/`RawVariant` value returned by a constructor, `ptrcall`, or conversion is owned by the caller, who must
  `destroy!` it exactly once (types without a destructor make that a no-op).
- Values passed as call arguments are borrowed; the callee copies whatever it keeps.
- Values handed out by caches (`sn"..."`, `string_name_ptr`) are borrowed for the life of the runtime: never destroy them.
"""
module FFI

const GENERATED_DIR = joinpath(@__DIR__, "..", "generated")
isfile(joinpath(GENERATED_DIR, "interface.jl")) ||
    error("Godot bindings have not been generated; run `julia scripts/generate_bindings.jl` in the GodotJL repository.")

"Supertype of the opaque, non-Variant builtin values (`RawString`, `RawArray`, ...)."
abstract type RawBuiltin end

include(joinpath(GENERATED_DIR, "interface.jl"))
include(joinpath(GENERATED_DIR, "layout.jl"))
include("builtins.jl")
include("strings.jl")
include("hashes.jl")
include("calls.jl")
include("errors.jl")
include("init.jl")

end # module FFI
