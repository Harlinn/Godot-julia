# ADR 0007: Object identity, lifetime and threading

- Status: Accepted
- Date: 2026-11-05

## Context

Phase 07 ports C#'s object model: one managed object per native object (`InstanceBindings`), `RefCounted` integrated with the GC (strong/weak `GCHandle` switching in `csharp_script.cpp`), `Dispose`/`Free`/`QueueFree`/`IsInstanceValid`, `GodotObject.WeakRef`, casting and `GetNode<T>`, and dynamic `Call`/`Get`/`Set`.

## Decision

- **Instance bindings** (`object/lifetime.jl`) keep at most one Julia wrapper per native object. Bindings are keyed by a **Julia-owned token**, not the GDExtension library pointer, because godot-cpp (the native host) binds its own wrappers under the library token. C# similarly keys its bindings by the `CSharpLanguage` singleton. The binding callbacks are minimal: Godot calls them with its binding mutex held, so they never call back into the object.
- **Non-RefCounted objects**: the binding holds the wrapper weakly. If Julia drops it, a fresh wrapper is created the next time the object is seen (`===` identity holds while any Julia reference exists). User script structs are registered with `bind_wrapper!`, held strongly while the object lives, and freed with the object (phase 08).
- **RefCounted objects**: the wrapper owns one reference. While the engine holds other references (`refcount > 1`), the binding holds the wrapper strongly, so Julia-side state survives. When only the wrapper's reference remains, the binding holds it weakly and Julia's GC decides. The finalizer only queues the release. The queue is flushed at safe points (runtime entry points now, every frame from phase 10). This ports the C# strong/weak `GCHandle` switching.
- **Freed objects**: freeing (`free`, `queue_free`, the engine, or GDScript) clears the wrapper's pointer through the binding's free callback. Any later call throws `FreedObjectError` (C#'s `ObjectDisposedException`). `is_instance_valid(x)` is false for `nothing` and for freed or disposed wrappers.
- **Dispose is `finalize(obj)`**: it releases the wrapper's reference immediately and invalidates the wrapper, while the engine object stays alive if others reference it. `close` is not used, because engine classes such as `FileAccess` have their own `close` method.
- **Equality is identity**: `==` is `===` for objects, consistent with the unique wrapper.
- **Casting**: `obj isa T` (C# `is`), `convert(T, obj)` (C# cast, `TypeError` on mismatch), `as(T, obj)` (C# `as`, `nothing` on mismatch), and `get_node(T, node, path)` / `get_node_or_null(T, node, path)` (C# `GetNode<T>`).
- **Dynamic access**: `obj.name` uses the generated property if one exists, and otherwise falls back to the engine `get`/`set` for properties defined by scripts in any language. `set!(obj, name, value)`, `Godot.call(obj, method, args...)` and `has_property(obj, name)` cover the explicit forms (C#'s `Call`/`Get`/`Set`).

## Threading rules

- Julia wrappers can be passed between threads. Engine thread-safety rules apply exactly as in C# (see Godot's "Thread-safe APIs" documentation): the scene tree is main-thread only unless a node uses group/thread processing; resources and servers follow their documented rules.
- Binding bookkeeping is guarded by a lock, so wrapping, binding and finalizing from several Julia threads is safe.
- Finalizers can run on any thread, so they never call into Godot: they only queue releases, which run on the main thread at safe points.
- Calls arriving from Godot threads that Julia doesn't know are adopted (`jl_adopt_thread`, phase 02).

## Consequences

- Wrapper identity and engine state agree, and `RefCounted` cycles that pass through Julia closures (e.g. a Resource holding a `Callable` that captures Julia state) are collected (`tests/integration/objects`).
- A non-script, non-RefCounted wrapper that Julia drops loses any Julia-side identity (`objectid`). Plain native wrappers have no fields beyond the pointer, so nothing else is lost.
- Lock ordering: Julia never holds the binding lock while calling into Godot APIs that might take Godot's binding mutex and then call back into Julia, except `object_get_instance_binding`, which is called before the lock is taken.
