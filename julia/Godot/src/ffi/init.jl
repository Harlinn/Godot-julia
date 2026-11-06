const INITIALIZED = Ref(false)
"`GDExtensionClassLibraryPtr` of the native host (needed by some interface functions)."
const LIBRARY = Ref{Ptr{Cvoid}}(C_NULL)

"""
    init!(get_proc_address, library, real_t_size)

Resolve the interface table and builtin function pointers. `real_t_size` is `sizeof(real_t)` of the Godot build
the native host was compiled for; it must match the generated bindings.
"""
function init!(get_proc_address::Ptr{Cvoid}, library::Ptr{Cvoid}, real_t_size::Integer)
    real_t_size == sizeof(real_t) ||
        error("Godot uses $(8 * real_t_size)-bit real_t but bindings were generated for $BUILD_CONFIGURATION; " *
              "regenerate them with `julia scripts/generate_bindings.jl --precision=$(real_t_size == 8 ? "double" : "single")`")
    sizeof(Ptr{Cvoid}) * 8 == Sys.WORD_SIZE == parse(Int, BUILD_CONFIGURATION[(end - 1):end]) ||
        error("bindings were generated for $BUILD_CONFIGURATION on a $(Sys.WORD_SIZE)-bit Julia")
    missing_functions = load_interface!(get_proc_address)
    for name in (:object_method_bind_ptrcall, :variant_get_ptr_constructor, :string_new_with_utf8_chars_and_len2)
        name in missing_functions && error("Godot does not provide required interface function $name")
    end
    init_builtins!()
    LIBRARY[] = library
    INITIALIZED[] = true
    return missing_functions
end

"Release cached Godot resources; must run while Godot is still alive."
function shutdown!()
    INITIALIZED[] || return nothing
    destroy_string_names!()
    reset_calls!()
    reset_builtins!()
    INITIALIZED[] = false
    return nothing
end
