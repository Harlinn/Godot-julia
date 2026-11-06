using Base.CoreLogging: CoreLogging, AbstractLogger, LogLevel, Info, Warn, Error

"Line-buffered `IO` that forwards complete lines to Godot's `print`/`printerr`."
mutable struct GodotStream <: IO
    kind::Int32
    buffer::Vector{UInt8}
    lock::ReentrantLock
end

GodotStream(kind::Int32) = GodotStream(kind, UInt8[], ReentrantLock())

function emit_lines!(io::GodotStream)
    while (i = findfirst(==(UInt8('\n')), io.buffer)) !== nothing
        stop = (i > 1 && io.buffer[i - 1] == UInt8('\r')) ? i - 2 : i - 1
        line = String(io.buffer[1:stop])
        deleteat!(io.buffer, 1:i)
        host_print(io.kind, line)
    end
    return nothing
end

function Base.unsafe_write(io::GodotStream, p::Ptr{UInt8}, n::UInt)
    @lock io.lock begin
        append!(io.buffer, unsafe_wrap(Array, p, n))
        emit_lines!(io)
    end
    return Int(n)
end

function Base.write(io::GodotStream, b::UInt8)
    @lock io.lock begin
        push!(io.buffer, b)
        b == UInt8('\n') && emit_lines!(io)
    end
    return 1
end

function Base.flush(io::GodotStream)
    @lock io.lock begin
        if !isempty(io.buffer)
            host_print(io.kind, String(copy(io.buffer)))
            empty!(io.buffer)
        end
    end
    return nothing
end

Base.isopen(::GodotStream) = true
Base.iswritable(::GodotStream) = true
Base.displaysize(::GodotStream) = (24, 120)

"Logger mapping `@info`/`@debug` to Godot's Output panel and `@warn`/`@error` to Godot warnings/errors."
struct GodotLogger <: AbstractLogger
    min_level::LogLevel
end

GodotLogger() = GodotLogger(Info)

CoreLogging.min_enabled_level(logger::GodotLogger) = logger.min_level
CoreLogging.shouldlog(::GodotLogger, args...) = true
CoreLogging.catch_exceptions(::GodotLogger) = true

function format_log_message(message, kwargs)
    return sprint() do io
        print(io, message)
        for (key, value) in kwargs
            if key === :exception && value isa Tuple{Exception, Any}
                print(io, "\n")
                showerror(io, value[1], value[2])
            else
                print(io, "\n  ", key, " = ")
                show(IOContext(io, :limit => true), value)
            end
        end
    end
end

function CoreLogging.handle_message(logger::GodotLogger, level, message, _module, group, id, file, line; kwargs...)
    msg = format_log_message(message, kwargs)
    lvl = convert(LogLevel, level)
    if lvl >= Warn
        host_report_error(lvl < Error, string(_module), something(file, ""), something(line, 0), msg)
    else
        host_print(PRINT_STDOUT, lvl < Info ? "Debug: " * msg : msg)
    end
    return nothing
end

const SAVED_OUTPUT = Ref{Any}(nothing)

function install_output!()
    SAVED_OUTPUT[] === nothing || return nothing
    SAVED_OUTPUT[] = (stdout, stderr, CoreLogging.global_logger())
    setglobal!(Base, :stdout, GodotStream(PRINT_STDOUT))
    setglobal!(Base, :stderr, GodotStream(PRINT_STDERR))
    CoreLogging.global_logger(GodotLogger())
    return nothing
end

function restore_output!()
    saved = SAVED_OUTPUT[]
    saved === nothing && return nothing
    flush(stdout)
    flush(stderr)
    out, err, logger = saved
    setglobal!(Base, :stdout, out)
    setglobal!(Base, :stderr, err)
    CoreLogging.global_logger(logger)
    SAVED_OUTPUT[] = nothing
    return nothing
end
