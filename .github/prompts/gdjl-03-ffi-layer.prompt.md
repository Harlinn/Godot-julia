---
name: gdjl-03-ffi-layer
description: "Phase 3: low-level Julia FFI over the GDExtension C interface (function table, Variant ABI, method binds, StringName cache)."
agent: agent
---
Build the low-level interop layer in `julia/Godot/src/ffi/` that lets Julia call the GDExtension C interface directly via `ccall` on function pointers. Follow the [project instructions](../copilot-instructions.md). Behavioral reference: `modules/mono/glue/runtime_interop.cpp` and `GodotSharp/Core/NativeInterop/` (`NativeFuncs`, `InteropStructs`, `Marshaling`, `VariantUtils`).

## Requirements

1. **Interface table**: on `__init_runtime__`, resolve every needed function from `gdextension_interface.h` via `get_proc_address` into a `const` struct of `Ptr{Cvoid}` fields populated once (`Ref` filled at init). Wrap each in a typed `@inline` Julia function. Generate this table from the parsed header (`GodotBindgen` helper) rather than writing it by hand.
2. **Build configuration**: read `builtin_class_sizes` / `builtin_class_member_offsets` for the active configuration (`float_32`, `float_64`, `double_32`, `double_64`) and define `const real_t`. Assert at init that Julia struct sizes match.
3. **Opaque builtins**: `isbits` structs of the correct size for `Variant`, `String`, `StringName`, `NodePath`, `Array`, `Dictionary`, `Callable`, `Signal`, `Packed*Array` with constructors/destructors obtained via `variant_get_ptr_constructor`/`_destructor`. Ownership rules documented (who destroys what).
4. **Method calls**: `ptrcall` path (`object_method_bind_ptrcall`) for fixed-arity methods with stack-allocated argument arrays (no heap allocation for isbits args), and `call` path (`object_method_bind_call`) for varargs. Builtin-type methods via `variant_get_ptr_builtin_method`. Utility functions via `variant_get_ptr_utility_function`.
5. **Caches**: method binds by `(class, method, hash)` and `StringName`s created lazily once and kept for process lifetime — equivalent to C#'s static readonly caches. Provide `@sn_str` macro for compile-time-constant StringNames.
6. **Callbacks**: all `@cfunction` entry points (instance binding callbacks, script instance callbacks, custom callable callbacks) are top-level functions taking a userdata pointer — no closures.
7. **Error reporting**: thin wrappers over `print_error_with_message`, `print_warning_with_message`, `print_script_error` that accept Julia `LineNumberNode`/stack frames.

## Tests

- Unit tests (run in-engine via the integration harness) for String/StringName round-trips, Variant construct/destroy with no leaks (check `Performance.OBJECT_COUNT` / memory stats), ptrcall on `OS.get_name()`.
- Benchmark: 1M calls of a trivial ptrcall method report allocations = 0 (`@allocated`).

Update parity row 1.7 (partial).
