# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Thin wrappers over Godot's error reporting that take Julia source locations.

const SourceLocation = Union{LineNumberNode, Base.StackFrame}

location_function(::LineNumberNode) = ""
location_function(frame::Base.StackFrame) = string(frame.func)
location_file(loc::SourceLocation) = loc.file === nothing ? "" : string(loc.file)
location_line(loc::SourceLocation) = Int32(loc.line)

"Report an error to Godot's debugger and terminal (`print_error_with_message`)."
function godot_error(message::AbstractString, loc::SourceLocation; description::AbstractString = message,
                     editor_notify::Bool = false)
    print_error_with_message(String(description), String(message), location_function(loc), location_file(loc),
                             location_line(loc), editor_notify)
    return nothing
end

"Report a warning to Godot's debugger and terminal (`print_warning_with_message`)."
function godot_warning(message::AbstractString, loc::SourceLocation; description::AbstractString = message,
                       editor_notify::Bool = false)
    print_warning_with_message(String(description), String(message), location_function(loc), location_file(loc),
                               location_line(loc), editor_notify)
    return nothing
end

"Report an error attributed to a script location (`print_script_error_with_message`)."
function godot_script_error(message::AbstractString, loc::SourceLocation; description::AbstractString = message,
                            editor_notify::Bool = false)
    print_script_error_with_message(String(description), String(message), location_function(loc),
                                    location_file(loc), location_line(loc), editor_notify)
    return nothing
end
