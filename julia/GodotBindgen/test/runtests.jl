# Bindings generator. parity: 2.1, 2.8, 2.12
using GodotBindgen
using GodotBindgen: Context, julia_default, method_function, type_spec, bbcode_to_markdown
using JSON
using Test

const BUNDLED = joinpath(GodotBindgen.REPO_ROOT, "native", "godot-cpp", "gdextension")
const FIXTURE_CLASSES = ["Object", "RefCounted", "Resource", "Node", "CanvasItem", "Node2D", "Engine", "FileAccess",
                         "EditorPlugin"]

"A trimmed extension_api.json: a handful of classes, one singleton, two utility functions."
function trimmed_api()
    api = JSON.parsefile(joinpath(BUNDLED, "extension_api-4-7.json"); dicttype = Dict{String, Any})
    api["classes"] = filter(c -> c["name"] in FIXTURE_CLASSES, api["classes"])
    api["singletons"] = filter(s -> s["name"] == "Engine", api["singletons"])
    api["utility_functions"] = filter(f -> f["name"] in ("sin", "print"), api["utility_functions"])
    # Classes registered by other GDExtensions, as in a dump made with `fetch_api.jl --project=...`.
    push!(api["classes"], Dict{String, Any}(
        "name" => "ThirdPartyNode", "inherits" => "Node2D", "api_type" => "extension", "is_refcounted" => false,
        "is_instantiable" => true,
        "methods" => Any[Dict{String, Any}("name" => "boost", "is_const" => false, "is_vararg" => false,
                                           "is_static" => false, "is_virtual" => false, "hash" => 12345,
                                           "arguments" => Any[Dict{String, Any}("name" => "amount", "type" => "float")],
                                           "return_value" => Dict{String, Any}("type" => "float"))]))
    push!(api["classes"], Dict{String, Any}(
        "name" => "ThirdPartyEditorTool", "inherits" => "EditorPlugin", "api_type" => "editor_extension",
        "is_refcounted" => false, "is_instantiable" => true))
    return api
end

@testset "GodotBindgen" begin
    @test isfile(joinpath(GodotBindgen.REPO_ROOT, "GODOT_VERSION"))
    @test endswith(GodotBindgen.api_dir(), joinpath("native", "api"))
    @test endswith(GodotBindgen.output_dir(), joinpath("Godot", "src", "generated"))

    @testset "C type mapping" begin
        named = Set(["GDExtensionBool", "GDExtensionVariantPtr", "GDExtensionCallError"])
        jt(t) = GodotBindgen.julia_ctype(t, named)
        @test jt("int32_t") == "Int32"
        @test jt("size_t") == "Csize_t"
        @test jt("const char*") == "Ptr{UInt8}"
        @test jt("char32_t*") == "Ptr{UInt32}"
        @test jt("const GDExtensionConstTypePtr*") == "Ptr{Cvoid}"
        @test jt("GDExtensionCallError*") == "Ptr{Cvoid}"
        @test jt("GDExtensionVariantPtr") == "GDExtensionVariantPtr"
        @test jt("GDExtensionCallError") == "GDExtensionCallError"
        @test_throws ErrorException jt("mystery_t")
        @test GodotBindgen.safe_name("end") == "end_"
        @test GodotBindgen.build_configuration("double") == "double_64"
    end

    @testset "BBCode to Markdown" begin
        md = bbcode_to_markdown("Use [method add_child] on a [Node]. [b]Bold[/b], [i]it[/i], [code]x = 1[/code].")
        @test md == "Use `add_child` on a `Node`. **Bold**, *it*, `x = 1`."
        @test bbcode_to_markdown("[Object]") == "`GodotObject`"
        @test bbcode_to_markdown("See [url=https://godotengine.org]docs[/url].") == "See [docs](https://godotengine.org)."
        blocks = bbcode_to_markdown("[codeblocks]\n[gdscript]\n\tprint(1)\n[/gdscript]\n[csharp]\n\tGD.Print(1);\n[/csharp]\n[/codeblocks]")
        @test occursin("```gdscript\nprint(1)\n```", blocks)
        @test occursin("```csharp\nGD.Print(1);\n```", blocks)
        @test bbcode_to_markdown("a[lb]0[rb]") == "a[0]"
    end

    if isfile(joinpath(BUNDLED, "extension_api-4-7.json"))
        @testset "merging extension classes from a project dump" begin
            core = Dict{String, Any}("classes" => Any[Dict("name" => "Node", "api_type" => "core")], "singletons" => Any[])
            project = Dict{String, Any}(
                "classes" => Any[Dict("name" => "Node", "api_type" => "core"), Dict("name" => "Ext", "api_type" => "extension"),
                                 Dict("name" => "ExtTool", "api_type" => "editor_extension")],
                "singletons" => Any[Dict("name" => "Ext", "type" => "Ext"), Dict("name" => "Engine", "type" => "Engine")])
            GodotBindgen.merge_extension_classes!(core, project)
            @test [c["name"] for c in core["classes"]] == ["Node", "Ext", "ExtTool"]
            @test core["singletons"] == Any[Dict("name" => "Ext", "type" => "Ext")]
        end
        api = trimmed_api()
        ctx = Context(api)
        fields = GodotBindgen.struct_fields(api, "float_64")

        @testset "naming and type mapping" begin
            @test method_function(ctx, "get_name") == "get_name"
            @test method_function(ctx, "close") == "Base.close"
            @test method_function(ctx, "eval") == "eval_"
            @test method_function(ctx, "end") == "end_"
            @test GodotBindgen.type_name("Object") == "GodotObject"
            @test type_spec(ctx, "Node").annot == "Union{Nothing, Node}"
            @test type_spec(ctx, "Resource").ret == "Internals.take_object(Resource, %, true)"
            @test type_spec(ctx, "enum::Node.ProcessMode").annot == "Union{Node_ProcessMode, Integer}"
            @test type_spec(ctx, "enum::Error").ret == "Error(%)"
            @test type_spec(ctx, "String").owned
            @test type_spec(ctx, "Vector2").native == "Vector2"
            @test type_spec(ctx, "SceneTree") === nothing
            @test type_spec(ctx, "typedarray::Node").ret == "Internals.take_array(GDArray{Node}, %)"
            @test type_spec(ctx, "typedarray::24/17:Resource").ret == "Internals.take_array(GDArray{Resource}, %)"
            @test type_spec(ctx, "typedarray::27/0:").ret == "Internals.take_array(GDArray{GDDictionary{Any, Any}}, %)"
            @test type_spec(ctx, "typedarray::StringName").ret == "Internals.take_array(GDArray{Symbol}, %)"
            @test type_spec(ctx, "typeddictionary::int;String").ret == "Internals.take_dictionary(GDDictionary{Int64, String}, %)"
            @test type_spec(ctx, "typedarray::Mystery").ret == "Internals.take_array(%)"

            ectx = Context(api; scope = :editor)
            @test method_function(ectx, "get_name") == "Godot.get_name"
            @test method_function(ectx, "close") == "Base.close"
            @test type_spec(ectx, "Node").annot == "Union{Nothing, Godot.Node}"
            @test type_spec(ectx, "EditorPlugin").annot == "Union{Nothing, EditorPlugin}"
            @test type_spec(ectx, "enum::Error").ret == "Godot.Error(%)"
            @test type_spec(ectx, "enum::EditorPlugin.DockSlot").annot == "Union{EditorPlugin_DockSlot, Integer}"
            @test type_spec(ctx, "EditorPlugin").annot == "Union{Nothing, GodotObject}"
            @test_throws ArgumentError Context(api; scope = :game)
        end

        @testset "default values" begin
            @test julia_default(ctx, "int", "-1", fields) == "-1"
            @test julia_default(ctx, "float", "1", fields) == "1.0"
            @test julia_default(ctx, "float", "inf", fields) == "Inf"
            @test julia_default(ctx, "bool", "false", fields) == "false"
            @test julia_default(ctx, "String", "\"*\"", fields) == "\"*\""
            @test julia_default(ctx, "StringName", "&\"\"", fields) == "Symbol(\"\")"
            @test julia_default(ctx, "StringName", "&\"Master\"", fields) == ":Master"
            @test julia_default(ctx, "NodePath", "NodePath(\"\")", fields) == "NodePath(\"\")"
            @test julia_default(ctx, "Color", "Color(1, 1, 1, 1)", fields) == "Color(1, 1, 1, 1)"
            @test julia_default(ctx, "Transform2D", "Transform2D(1, 0, 0, 1, 0, 0)", fields) == "Transform2D(1, 0, 0, 1, 0, 0)"
            @test julia_default(ctx, "Vector2", "Vector2(1, 2, 3)", fields) === nothing
            @test julia_default(ctx, "Node", "null", fields) == "nothing"
            @test julia_default(ctx, "typedarray::RID", "Array[RID]([])", fields) == "nothing"
            @test julia_default(ctx, "PackedStringArray", "PackedStringArray()", fields) == "nothing"
            @test julia_default(ctx, "Callable", "Callable()", fields) == "nothing"
            @test julia_default(ctx, "RID", "RID()", fields) == "RID()"
        end

        @testset "generate trimmed API" begin
            classes = sprint(io -> GodotBindgen.generate_classes(io, api))
            @test occursin("abstract type Node2D <: CanvasItem end", classes)
            @test occursin("mutable struct Node2D <: Godot.Node2D", classes)
            @test occursin("function set_position(self::Node2D, position::Vector2)", classes)
            @test occursin("s === :position && return get_position(self)", classes)
            @test occursin("Node2D() = Internals.construct_object(Native.Node2D, :Node2D)", classes)
            @test occursin("struct Node_ProcessMode <: GodotEnum", classes)
            @test occursin("const Node_PROCESS_MODE_INHERIT = Node_ProcessMode(0)", classes)
            @test occursin("get_version_info(::Type{Engine}, args...) = get_version_info(Internals.singleton(Engine), args...)", classes)
            @test occursin("function file_exists(::Type{FileAccess}, path::AbstractString)", classes)
            @test occursin("function Base.close(self::FileAccess)", classes)
            @test occursin("args...)", classes)  # Object.call / emit_signal are varargs
            @test occursin("function _ready end", classes)
            @test !occursin("abstract type EditorPlugin", classes)
            @test occursin("function add_tool_menu_item end", classes)  # generic functions are owned by Godot
            @test Meta.parseall(classes) isa Expr

            editor = sprint(io -> GodotBindgen.generate_editor_classes(io, api))
            @test occursin("abstract type EditorPlugin <: Godot.Node end", editor)
            @test occursin("mutable struct EditorPlugin <: GodotEditor.EditorPlugin", editor)
            @test occursin("function Godot.add_tool_menu_item(self::EditorPlugin, name::AbstractString, callable::Any)", editor)
            @test occursin(":EditorPlugin => Native.EditorPlugin", editor)
            @test occursin("export EditorPlugin", editor)
            @test !occursin("abstract type Node2D", editor)
            @test Meta.parseall(editor) isa Expr

            # Extension classes join the hierarchy like engine classes; editor-only ones go to GodotEditor.
            @test occursin("abstract type ThirdPartyNode <: Node2D end", classes)
            @test occursin("function boost(self::ThirdPartyNode, amount::Real)", classes)
            @test occursin(":ThirdPartyNode => Native.ThirdPartyNode", classes)
            @test occursin("export ThirdPartyNode", classes) || occursin(", ThirdPartyNode", classes)
            @test occursin("abstract type ThirdPartyEditorTool <: EditorPlugin end", editor)
            @test !occursin("ThirdPartyEditorTool", classes)

            report_ctx = Context(api)
            sprint(io -> GodotBindgen.generate_classes(io, api)) # warm
            sprint(io -> (report_ctx = GodotBindgen.generate_classes(io, api)))
            report = sprint(io -> GodotBindgen.generate_report(io, report_ctx))
            @test occursin("rename: Object -> GodotObject", report)
            @test occursin("skipped: Node.get_tree", report)

            iface = JSON.parsefile(joinpath(BUNDLED, "gdextension_interface.json"); dicttype = Dict{String, Any})
            structs = sprint(io -> GodotBindgen.generate_builtin_structs(io, api, iface))
            @test occursin("struct Vector2\n    x::Float32\n    y::Float32\nend", structs)
            @test occursin("Transform2D(a1::Real, a2::Real, a3::Real, a4::Real, a5::Real, a6::Real)", structs)
            @test occursin("struct Basis\n    row0::Vector3\n", structs)
            @test occursin("Basis(::Internals.Rows, row0::Vector3, row1::Vector3, row2::Vector3) = new(row0, row1, row2)", structs)
            @test occursin("= Transform3D(Basis(Internals.ROWS, Vector3(a1, a2, a3)", structs)
            @test occursin("const Vector2_ZERO = Vector2(0, 0)", structs)
            @test occursin("const Vector3_INF = Vector3(Inf, Inf, Inf)", structs)
            @test occursin("const Color_ALICE_BLUE = Color(240f0 / 255f0, 248f0 / 255f0, 255f0 / 255f0, 255f0 / 255f0)", structs)
            @test Meta.parseall(structs) isa Expr
            globals = sprint(io -> GodotBindgen.generate_globals(io, api, report_ctx))
            @test occursin("function sin(angle_rad::Real)", globals)
            @test occursin("function print(arg1::Any, args...)", globals)
            @test Meta.parseall(globals) isa Expr
            enums = sprint(io -> GodotBindgen.generate_global_enums(io, api))
            @test occursin("const OK = Error(0)", enums)
            local builtin_ctx
            builtins = sprint(io -> (builtin_ctx = GodotBindgen.generate_builtin_methods(io, api)))
            @test occursin("function begins_with(self::AbstractString, text::AbstractString)", builtins)
            @test occursin("function begins_with(self::Symbol, text::AbstractString)", builtins)
            @test occursin("function num(::Type{String}, number::Real, decimals::Integer = -1)", builtins)
            @test occursin("function push_back(self::GDArray, value::Any)", builtins)
            @test occursin("Internals.raw_ptr(self)", builtins)
            @test occursin("function emit(self::Signal, args...)", builtins)
            @test occursin("Internals.builtin_varcall(self, :call, args...)", builtins)
            @test !occursin("function Base.length(self::AbstractString", builtins)   # Base meaning wins
            @test "builtin method not bound (Julia equivalent in Base): String.length" in builtin_ctx.renames
            @test Meta.parseall(builtins) isa Expr
        end

        @testset "every builtin math method has a golden case" begin
            full = JSON.parsefile(joinpath(BUNDLED, "extension_api-4-7.json"); dicttype = Dict{String, Any})
            cases = readlines(joinpath(GodotBindgen.REPO_ROOT, "julia", "Godot", "test", "fixtures", "math_cases.txt"))
            missing_cases = String[]
            for b in full["builtin_classes"]
                b["name"] in GodotBindgen.MATH_BUILTINS || continue
                own = filter(l -> occursin(Regex("^-?" * b["name"] * "[(.]"), l), cases)
                for m in get(b, "methods", [])
                    any(l -> occursin("." * m["name"] * "(", l), own) || push!(missing_cases, "$(b["name"]).$(m["name"])")
                end
            end
            isempty(missing_cases) || @info "builtin methods without golden cases" missing_cases
            @test isempty(missing_cases)
        end

        @testset "full generation into a temporary directory" begin
            mktempdir() do dir
                apidir = joinpath(dir, "api")
                mkpath(apidir)
                cp(joinpath(BUNDLED, "extension_api-4-7.json"), joinpath(apidir, "extension_api.json"))
                cp(joinpath(BUNDLED, "gdextension_interface.json"), joinpath(apidir, "gdextension_interface.json"))
                out = joinpath(dir, "generated")
                editor_out = joinpath(dir, "editor")
                GodotBindgen.generate(; api_dir = apidir, out_dir = out, editor_out_dir = editor_out, precision = "double")
                @test occursin("const real_t = Float64", read(joinpath(out, "layout.jl"), String))
                @test occursin("x::Float64", read(joinpath(out, "builtin_structs.jl"), String))
                @test "class\tOS\tget_name\t201670096" in readlines(joinpath(out, "method_hashes.tsv"))
                for f in ("interface.jl", "layout.jl", "builtin_structs.jl", "global_enums.jl", "classes.jl", "globals.jl")
                    @test Meta.parseall(read(joinpath(out, f), String)) isa Expr
                end
                @test Meta.parseall(read(joinpath(editor_out, "classes.jl"), String)) isa Expr
            end
        end
    end
end
