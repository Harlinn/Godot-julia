# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

"""
    @godot_entry default body

Wrap the body of a function called from C/C++ so that no Julia exception unwinds through native frames:
exceptions are reported to Godot (with the Julia stack trace) and `default` is returned instead.
"""
macro godot_entry(default, body)
    return quote
        try
            $(esc(body))
        catch err
            report_unhandled(err, catch_backtrace())
            $(esc(default))
        end
    end
end

"""
    @gcsafe_ccall f(args...)::T

`@ccall` that lets Julia's GC run on other threads while the (possibly long) native call executes.
"""
macro gcsafe_ccall(expr)
    return esc(Expr(:macrocall, GlobalRef(Base, Symbol("@ccall")), __source__, :(gc_safe = true), expr))
end

is_base_frame(frame::Base.StackFrame) = frame.from_c || (startswith(string(frame.file), ".") && !is_script_frame(frame))

"Most relevant user frame of a backtrace (skips C frames and Base/Core internals)."
function source_frame(bt)
    frames = stacktrace(bt)
    isempty(frames) && return nothing
    idx = findfirst(!is_base_frame, frames)
    return frames[something(idx, 1)]
end
