# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot

# Fails in its first three frames; the game must keep running and report each error at this file's line.
@godot_class mutable struct Faulty <: Node
    count::Int = 0
end

function Godot._process(self::Faulty, delta::Float64)
    self.count >= 3 && return
    self.count += 1
    error("faulty frame $(self.count)")
end
