# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

using Godot
using Test

const REPO_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))

@testset "Godot" begin
    @testset "version pin" begin
        pin_file = joinpath(REPO_ROOT, "GODOT_VERSION")
        if isfile(pin_file)
            tag = strip(read(pin_file, String))
            @test VersionNumber(replace(tag, "-stable" => "")) == Godot.GODOT_VERSION
        end
        @test Godot.GODOT_API_VERSION == VersionNumber(Godot.GODOT_VERSION.major, Godot.GODOT_VERSION.minor)
    end

    include("ffi.jl")
    include("bindings.jl")
    include("builtins.jl")
    include("variant.jl")
    include("runtime.jl")
    include("debugging.jl")
    include("scripts.jl")
    include("export.jl")
    include("async.jl")
    include("reload.jl")
end
