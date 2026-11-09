---
name: book-ch10-object-model
description: "Book chapter 10: the logic behind gdjl-07-object-model — identity, lifetime and GC integration between Julia and Godot objects."
agent: agent
---
Write chapter 10 of the book, `docs/book/10-object-model.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-07-object-model](../gdjl-07-object-model.prompt.md).

## Focus

- **"Mirror C# exactly."** For the hardest subsystem (two garbage collectors, refcounting, weak/strong handle switching), the prompt names exact functions in `csharp_script.cpp` and C#'s strong/weak GCHandle trick. Discuss when to give an agent freedom and when to demand a faithful port.
- **Threading rules as a deliverable**: "document which operations are thread-safe". Finalizers must never call into Godot from a GC thread; releases are queued to the main thread.
- **Tests aimed at the scary cases**: identity (`===`), access after free, collection of a RefCounted cycle, and no leaks at exit.

## Leads to Verify

- Instance bindings use a Julia-owned token (`BINDING_TOKEN`), not the library token. godot-cpp binds its own wrappers under the library token, which caused KeyErrors and foreign pointers. This is a subtle integration bug the agent had to diagnose.
- The binding pointer is the address of the `InstanceBinding` (rooted in `BINDINGS`). Lock discipline: create/free take the leaf `REGISTRY_LOCK`; reference takes no lock, because Godot holds the object's binding mutex.
- GC tests allocate in `@noinline` helpers, because testset temporaries keep wrappers rooted. Test design pitfalls are as instructive as product bugs.
- A bug found later: `construct_object` must send `NOTIFICATION_POSTINITIALIZE` like godot-cpp's `memnew`. It was fixed in phase 12, after Controls created from Julia crashed editor docks. Use it as an example of a later phase exposing an earlier gap, and of why matrix rows record such history.
- `Base.WeakRef` vs Godot `WeakRef` shadowing (cross-reference chapter 7).

## Artifacts to Inspect

`julia/Godot/src/object/` (`lifetime.jl`, `objects.jl`, `nodes.jl`), `docs/adr/0007-object-model.md`, `tests/integration/objects/` (note `julia/runtime/threads=4` in its project settings).

## Try It Yourself

Ask the Ask agent to draw (as Mermaid) the lifetime state machine of a RefCounted wrapper from the code, then compare it with the ADR.

Parity rows: 4.1–4.8, 4.10. Navigation: previous chapter 9, next chapter 11.
