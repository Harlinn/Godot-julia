# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# The only way native code may hold on to Julia values (see project conventions on GC safety).

const PINS = Dict{UInt64, Any}()
const PINS_LOCK = ReentrantLock()
const NEXT_PIN = Ref{UInt64}(0)

"Root `x` so the GC keeps it alive; returns a non-zero handle for native code."
function pin(@nospecialize(x))::UInt64
    @lock PINS_LOCK begin
        id = (NEXT_PIN[] += 1)
        PINS[id] = x
        return id
    end
end

"Release a handle returned by [`pin`](@ref). Unknown handles are ignored."
unpin(id::UInt64) = (@lock PINS_LOCK delete!(PINS, id); nothing)

"Look up the value behind a pinned handle."
deref(id::UInt64) = @lock PINS_LOCK PINS[id]

pin_count() = @lock PINS_LOCK length(PINS)
