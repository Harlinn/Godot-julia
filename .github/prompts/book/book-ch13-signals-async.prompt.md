---
name: book-ch13-signals-async
description: "Book chapter 13: the logic behind gdjl-10-signals-async — signals, Julia Callables, and await on Godot signals via a main-thread scheduler."
agent: agent
---
Write chapter 13 of the book, `docs/book/13-signals-async.md`, following the [book guide](book-guide.md) and its phase chapter template.

Source prompt: [gdjl-10-signals-async](../gdjl-10-signals-async.prompt.md).

## Focus

- **Translating a concurrency model.** C#'s `SynchronizationContext`/`TaskScheduler`/`SignalAwaiter` map to Julia `Task`s resumed on the main thread during `JuliaLanguage::_frame`. Explain why the prompt names the C# classes instead of describing the behavior abstractly.
- **Edge cases as requirements**: freed targets auto-disconnect, awaiting a signal on a freed object neither leaks nor hangs, and unhandled task exceptions are reported. Without these, agents tend to implement only the happy path.
- **"Document the rule for capture-less closures."** Asking the agent to write down a policy where no reference behavior exists.
- **Worker threads** (`WorkerThreadPool`, `Threads.@spawn` with `Godot.post`), and following ADR 0007's threading rules.

## Leads to Verify

- `pump_frame!()` (posted jobs, then yield to the main workqueue) runs in `_frame` before `flush_releases!`.
- Script methods must not return a `Task`. C# `async void` handlers map to returning `nothing` (discovered while porting demos).
- `@breakpoint` inside a `godot_task` pauses only the task; `Godot.post` is used for a whole-game pause (cross-reference chapter 16).
- How the GC-safety issue with adopted engine threads led to the guarded trampolines (ABI v4), and how it shows up here.
- Leak checks on pin counts must be monotonic (`<=`) because earlier releases land asynchronously. This is flaky-test avoidance.

## Artifacts to Inspect

`julia/Godot/src/signals/`, `julia/Godot/src/async/` (or wherever the scheduler lives), `docs/adr/0010-signals-async.md`, `docs/user/julia_signals.md`, `docs/user/julia_async.md`, `tests/integration/signals/`.

## Try It Yourself

Ask the agent to write a small script that awaits a timer three times and logs the thread id each time, then explain why every line prints the main thread.

Parity rows: 3.10, 3.11, 4.10, 6.1–6.6. Navigation: previous chapter 12, next chapter 14.
