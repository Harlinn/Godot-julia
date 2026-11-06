---
name: gdjl-07-object-model
description: "Phase 7: Julia object model for Godot objects — wrappers, identity, RefCounted/GC integration, free/dispose, casting, weak refs, cross-language calls."
agent: agent
---
Implement the object model in `julia/Godot/src/object/`. Follow the [project instructions](../copilot-instructions.md). Behavioral references: `GodotSharp/Core/GodotObject.base.cs`, `DisposablesTracker.cs`, `Bridge/ScriptManagerBridge.cs`, `NativeInterop/InteropUtils.cs`, and in C++ `csharp_script.cpp` (`CSharpLanguage::get_instance_binding`, `_instance_binding_*_callback`, `CSharpInstance` refcount handling `refcount_incremented`/`refcount_decremented`, strong/weak GCHandle switching).

## Requirements

1. **Handle**: every wrapper (native or user script) stores the native `GDExtensionObjectPtr` and an "alive" flag. `godot_ptr(obj)` accessor used by bindings.
2. **Identity**: one Julia object per native object, via `object_get_instance_binding` / `object_set_instance_binding` with `GDExtensionInstanceBindingCallbacks`. When the native object has a Julia script, the binding returns the user's script struct (C# parity: engine-returned objects are the script instance). Unknown concrete class → most-derived generated wrapper via `object_get_class_name` lookup (cached).
3. **Lifetime** (mirror C# exactly):
   - Non-`RefCounted` objects: Julia wrapper is held *weakly*; native object lives until `free()`/`queue_free()`. After free, wrapper is marked dead; any call raises `ObjectDisposedError`-like exception; `is_instance_valid(obj)` returns `false`.
   - `RefCounted`: Julia holds one reference. Switch the pin between strong and weak when refcount crosses 1 (C#'s strong/weak GCHandle trick) so cycles through the engine are collectable. Finalizer releases the reference on the main thread (queue it; never call into Godot from a finalizer on a GC thread).
   - `Base.finalize(obj)` / `close(obj)` as `Dispose` equivalent.
4. **Construction**: `Node()` (native) and user script construction from Julia (`Player()` creates native base object, attaches the script, runs Julia field initializers) and from the engine (`ClassDB.instantiate`, scene instancing) — both paths produce identical state.
5. **Casting**: `obj isa Node2D`, `convert(Node2D, obj)` (throws on mismatch), `tryconvert`-style `as(Node2D, obj)` returning `nothing`; `get_node(T, self, path)` and `get_node_or_null(T, ...)` matching C# `GetNode<T>`.
6. **Weak refs**: `weakref(obj)` returning Godot `WeakRef` (C# `GodotObject.WeakRef`).
7. **Cross-language dynamic access**: `call(obj, :method, args...)`, `get(obj, :prop)`, `set!(obj, :prop, v)`, `has_method`, plus `getproperty` fallback to dynamic `get` for properties defined by GDScript scripts. Returns `Variant`-converted Julia values.
8. **Threads**: document which operations are thread-safe, mirroring Godot's thread-safety guidelines; assert main thread in debug builds where Godot requires it.

## Tests

- Identity: `get_node("A") === get_node("A")`; script instance returned from `get_parent()`.
- Freed-object access raises and does not crash.
- RefCounted cycle Julia→Resource→Julia closure is collected.
- No leaked objects at exit (`--verbose` leak report empty) in integration tests.

Update parity rows 4.1–4.8, 4.10.
