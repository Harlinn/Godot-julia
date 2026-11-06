# Engine-free checks for the Variant layer (marshalling itself is tested in tests/integration/variant).
using Godot: isvarianttype, typed_info, element_type, packed_for, godot_class_name, VariantConversionError, FFI

@testset "Variant layer (no engine)" begin
    @test isvarianttype(Bool) && isvarianttype(Int8) && isvarianttype(UInt64) && isvarianttype(Float32)
    @test isvarianttype(String) && isvarianttype(SubString{String}) && isvarianttype(Symbol) && isvarianttype(NodePath)
    @test isvarianttype(Vector2) && isvarianttype(Projection) && isvarianttype(Node) && isvarianttype(Node_ProcessMode)
    @test isvarianttype(GDArray{Int64}) && isvarianttype(GDDictionary{String, Node}) && isvarianttype(PackedByteArray)
    @test isvarianttype(Vector{Float32}) && isvarianttype(Vector{Node}) && isvarianttype(Union{Nothing, Node})
    @test !isvarianttype(BigInt) && !isvarianttype(Dict{Int, Int}) && !isvarianttype(Vector{BigInt}) && !isvarianttype(Tuple{Int})
    @test packed_for(Float32) === PackedFloat32Array && packed_for(Color) === PackedColorArray && packed_for(Int16) === nothing
    @test typed_info(Int32) == (FFI.GDEXTENSION_VARIANT_TYPE_INT, Symbol(""))
    @test typed_info(Node) == (FFI.GDEXTENSION_VARIANT_TYPE_OBJECT, :Node)
    @test typed_info(GodotObject)[2] === :Object && godot_class_name(Godot.Native.Node2D) === :Node2D
    @test typed_info(PackedVector2Array)[1] == FFI.GDEXTENSION_VARIANT_TYPE_PACKED_VECTOR2_ARRAY
    @test element_type(FFI.GDEXTENSION_VARIANT_TYPE_OBJECT, :Node2D) === Node2D
    @test element_type(FFI.GDEXTENSION_VARIANT_TYPE_OBJECT, :NoSuchClass) === GodotObject
    @test element_type(FFI.GDEXTENSION_VARIANT_TYPE_VECTOR3, Symbol("")) === Vector3
    @test element_type(FFI.GDEXTENSION_VARIANT_TYPE_PACKED_STRING_ARRAY, Symbol("")) === PackedStringArray
    @test StringName === Symbol
    @test sprint(showerror, VariantConversionError(String, FFI.GDEXTENSION_VARIANT_TYPE_INT)) ==
          "VariantConversionError: cannot convert a Variant holding TYPE_INT to String"
    @test hasmethod(capitalize, Tuple{String}) && hasmethod(begins_with, Tuple{Symbol, String})
    @test hasmethod(get_name_count, Tuple{NodePath}) && hasmethod(push_back, Tuple{GDArray{Any}, Int})
    @test hasmethod(Godot.call, Tuple{Callable, Int}) && hasmethod(emit, Tuple{Signal, Int})
    @test hasmethod(num, Tuple{Type{String}, Float64})
end
