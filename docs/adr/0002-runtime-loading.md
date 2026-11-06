# ADR 0002: Load libjulia at runtime instead of linking it

- Status: Accepted
- Date: 2026-11-02

## Context

The extension has to find the Julia runtime when it starts, not when it is built. Sources include a runtime bundled with an exported game, a project setting, `JULIA_BINDIR`, or `PATH` (phase 02). When .NET is missing, the C# editor shows an error but stays usable, and we want the same behavior when Julia is missing. On Windows, official Julia binaries are built with MinGW, while Godot builds are usually made with MSVC.

## Decision

- Do not link `libjulia` at build time. The native host loads it with `LoadLibraryExW`/`dlopen` and resolves only exported, layout-independent entry points into a function table (`native/src/julia_host.h`):
  - from `libjulia`: `jl_parse_opts`, `jl_init_with_image_file`, `jl_eval_string`, `jl_exception_occurred`, `jl_adopt_thread`, `jl_get_pgcstack`, `jl_atexit_hook`, `jl_ver_*`;
  - from `libjulia-internal`: the out-of-line `jl_gc_{safe,unsafe}_{enter,leave}`. In 1.13 these take no `ptls` argument and act on the calling thread; this was verified empirically, and the header macros of the same name do take `ptls`.
- Runtime options (threads, optimization level, signal handling, project) go through `jl_parse_opts` with a synthetic `argv`. We never write to the `jl_options` struct.
- Beyond that table, C++ calls Julia only through `@cfunction` pointers that Julia hands back during `__init_runtime__`.
- Julia headers are not used. Non-release builds bake in `GDJL_DEV_JULIA_DIR` and `GDJL_DEV_PACKAGES_DIR`, used as last-resort search locations.

## Consequences

- The same extension binary works with any Julia ≥ 1.12 that exports these symbols, and the editor stays usable when Julia is missing.
- No MSVC/MinGW import-library problems, and no dependency on the `jl_options_t` or `jl_tls_states_t` layouts.
- If a future Julia drops one of the resolved symbols, loading fails with a clear "missing Julia symbol" error instead of crashing.
- With signal handling enabled (the default, required by Julia's GC safepoints), Julia installs its own fault handlers, which take precedence over Godot's crash handler.
