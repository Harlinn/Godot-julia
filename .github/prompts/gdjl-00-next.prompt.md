---
name: gdjl-00-next
description: "Resume the Godot+Julia implementation: find the next incomplete phase in the C# parity matrix and execute it."
agent: agent
---
Determine where the Godot+Julia (Godot-julia) implementation stands and continue it.

1. Read [project instructions](../copilot-instructions.md) and the [parity matrix](../../docs/csharp-parity-matrix.md).
2. Inspect the repository to verify the matrix is accurate (a row marked `DONE` must have code and a passing test). Correct any stale statuses.
3. Pick the lowest-numbered phase prompt (`gdjl-NN-*.prompt.md` in this folder) that still owns `TODO` or `PARTIAL` rows and whose predecessors are complete.
4. Read that prompt file and carry out its instructions fully.
5. Finish by reporting: phase executed, rows changed, tests run, and remaining blockers.
