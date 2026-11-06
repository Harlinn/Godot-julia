using Godot.FFI: FFI

function fake_method_ptrcall(::Ptr{Cvoid}, obj::Ptr{Cvoid}, args::Ptr{Ptr{Cvoid}}, ret::Ptr{Cvoid})
    a = unsafe_load(Ptr{Int64}(unsafe_load(args, 1)))
    b = unsafe_load(Ptr{Float64}(unsafe_load(args, 2)))
    c = unsafe_load(Ptr{Bool}(unsafe_load(args, 3)))
    unsafe_store!(Ptr{Int64}(ret), a + round(Int64, b) + c + Int64(UInt(obj)))
    return nothing
end

const NOARG_CALLS = Ref(0)
function fake_noarg_ptrcall(::Ptr{Cvoid}, ::Ptr{Cvoid}, args::Ptr{Ptr{Cvoid}}, ret::Ptr{Cvoid})
    (args == C_NULL && ret == C_NULL) && (NOARG_CALLS[] += 1)
    return nothing
end

function fake_builtin(base::Ptr{Cvoid}, args::Ptr{Ptr{Cvoid}}, ret::Ptr{Cvoid}, n::Cint)
    unsafe_store!(Ptr{Int64}(ret), unsafe_load(Ptr{Int64}(base)) * n + unsafe_load(Ptr{Int64}(unsafe_load(args, 1))))
    return nothing
end

function fake_utility(ret::Ptr{Cvoid}, args::Ptr{Ptr{Cvoid}}, ::Cint)
    unsafe_store!(Ptr{Float64}(ret), sin(unsafe_load(Ptr{Float64}(unsafe_load(args, 1)))))
    return nothing
end

function fake_interface(; overrides...)
    ptrs = [get(overrides, name, C_NULL) for name in fieldnames(FFI.InterfaceTable)]
    return FFI.InterfaceTable(ptrs...)
end

function ptrcall_loop(n)
    s = 0
    for i in 1:n
        s += FFI.ptrcall(Int64, C_NULL, Ptr{Cvoid}(1), i, 2.0, true)
    end
    return s
end

@testset "FFI" begin
    @testset "generated layout" begin
        @test FFI.real_t === Float32
        @test FFI.BUILD_CONFIGURATION == "float_64"
        @test sizeof(FFI.RawVariant) == FFI.BUILTIN_SIZES["Variant"]
        for T in FFI.RAW_BUILTINS
            name = String(nameof(T))[4:end]
            @test isbitstype(T)
            @test sizeof(T) == FFI.BUILTIN_SIZES[name]
            @test FFI.variant_type(T) == FFI.BUILTIN_VARIANT_TYPES[name]
        end
        @test FFI.constructor_index(FFI.RawString, FFI.RawStringName) == 2
        @test !FFI.has_destructor(FFI.RawRID)
        @test fieldnames(FFI.GDExtensionCallError) == (:error, :argument, :expected)
    end

    @testset "method hashes" begin
        @test FFI.method_hash(:OS, :get_name) == 201670096
        @test FFI.utility_hash(:sin) == 2140049587
        @test FFI.builtin_method_hash(:String, :length) isa Int64
        @test_throws KeyError FFI.method_hash(:OS, :no_such_method)
    end

    @testset "ptrcall machinery" begin
        saved = FFI.INTERFACE[]
        try
            FFI.INTERFACE[] = fake_interface(;
                object_method_bind_ptrcall = @cfunction(fake_method_ptrcall, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Ptr{Cvoid})))
            @test FFI.ptrcall(Int64, C_NULL, Ptr{Cvoid}(5), Int64(10), 2.4, true) == 10 + 2 + 1 + 5
            ptrcall_loop(10)
            @test (@allocated ptrcall_loop(1_000_000)) == 0

            FFI.INTERFACE[] = fake_interface(;
                object_method_bind_ptrcall = @cfunction(fake_noarg_ptrcall, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Ptr{Cvoid})))
            NOARG_CALLS[] = 0
            @test FFI.ptrcall(Nothing, C_NULL, C_NULL) === nothing
            @test NOARG_CALLS[] == 1
        finally
            FFI.INTERFACE[] = saved
        end

        builtin = @cfunction(fake_builtin, Cvoid, (Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Ptr{Cvoid}, Cint))
        base = Ref(Int64(7))
        @test GC.@preserve(base, FFI.builtin_ptrcall(Int64, builtin, Base.unsafe_convert(Ptr{Cvoid}, base), Int64(3))) == 7 * 1 + 3

        utility = @cfunction(fake_utility, Cvoid, (Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, Cint))
        @test FFI.utility_ptrcall(Float64, utility, 0.5) ≈ sin(0.5)
    end

    @testset "GodotCallError" begin
        msg = sprint(showerror, FFI.GodotCallError(FFI.GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT, 1, 4))
        @test occursin("invalid argument", msg)
        @test occursin("argument 2", msg)
    end
end
