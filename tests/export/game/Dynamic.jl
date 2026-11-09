# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot

# Top-level code that needs the running engine cannot be compiled into the system image: the export ships this
# script as source and evaluates it at runtime.
const STARTED_FRAMES = Godot.get_process_frames(Godot.Engine)

@godot_class mutable struct Dynamic <: Node
    frames::Int = STARTED_FRAMES
end
