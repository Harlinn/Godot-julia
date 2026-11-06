# ADR 0001: Build the native host with SCons

- Status: Accepted
- Date: 2026-11-02

## Context

`godot-cpp` supports both SCons and CMake. The Godot engine, the official `godot-cpp-template`, and godot-cpp's own test project all use SCons. They share the same option names (`target`, `platform`, `arch`, `precision`, `dev_build`) and the same library suffix convention (`.windows.template_debug.x86_64`, with `.double` added for double-precision builds). Starting with godot-cpp 10.x, the targeted Godot API is selected with `api_version`.

## Decision

- Use SCons. `native/SConstruct` calls `godot-cpp/SConstruct` with `api_version = "4.7"`.
- Pin `native/godot-cpp` to `10.0.0-stable` as a git submodule. godot-cpp is now versioned independently of Godot.
- Write build outputs straight into `addons/godot_julia/bin/` using godot-cpp's suffix convention, so the `.gdextension` file can list them without a copy step.
- Find the Julia installation from `julia_dir=`, then `JULIA_DIR`, then `julia` on `PATH`. Use it only for headers (see ADR 0002).

## Consequences

- Prerequisites are Python ≥ 3.8 and SCons ≥ 4.0, plus the same C++ toolchain that Godot requires (MSVC or MinGW on Windows).
- CMake users are not supported for now. If needed, a CMake wrapper can be added later without changing output names.
