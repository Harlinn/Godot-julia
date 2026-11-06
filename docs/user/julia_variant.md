# Variant

Counterpart of Godot's [C# Variant](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_variant.html). `Variant` is Godot's dynamic value type. In Julia most code never sees it: engine methods convert arguments and results to Julia types automatically. Use `Variant` explicitly when a value's type is only known at runtime.

```julia
v = Variant(42)                        # C#: Variant v = 42;
@test variant_type(v) == TYPE_INT      # C#: v.VariantType == Variant.Type.Int
@test convert(Int, v) == 42            # C#: v.AsInt32()
@test Float64(v) == 42.0
@test variant_type(Variant()) == TYPE_NIL
@test String(Variant(:abc)) == "abc"
@test Vector2(Variant(Vector2(1, 2))) == Vector2(1, 2)
@test_throws InexactError Int8(Variant(1000))     # range-checked, like C#'s checked conversions
```

## Which Julia types are Variant-compatible

`isvarianttype(T)` tells whether a type can be stored in a Variant (C#: the `[MustBeVariant]` rule). Exported fields, signal parameters and typed collections require such types.

| Godot | Julia |
|-------|-------|
| `bool`, `int`, `float` | `Bool`, any `Integer` (stored as `Int64`), any `AbstractFloat` (stored as `Float64`) |
| `String`, `StringName`, `NodePath` | `String`/`AbstractString`, `Symbol`, `NodePath` |
| math types | `Vector2`, `Vector3`, `Color`, `Transform2D`, ... |
| `Object` | any engine object (`Node`, `Resource`, script instances) or `nothing` |
| `Callable`, `Signal`, `RID` | `Callable`, `Signal`, `RID`; Julia functions convert to `Callable` |
| `Array`, `Dictionary` | `GDArray`, `GDDictionary`; `Vector`s and `Dict`s convert |
| packed arrays | `Packed*Array`, `Vector{Float32}`, `Vector{Vector2}`, ... |

```julia
@test isvarianttype(Int) && isvarianttype(Vector2) && isvarianttype(Node)
@test !isvarianttype(Complex{Float64})
@test_throws Exception Variant(1 + 2im)     # no Godot representation
```

## Dynamic values from the engine

Methods typed `Variant` in Godot's API return plain Julia values. Inspect them with `isa`:

```julia
node = Node()
set_meta(node, :anything, Vector3(1, 2, 3))
x = get_meta(node, :anything)
@test x isa Vector3
set_meta(node, :anything, "text")
@test get_meta(node, :anything) isa String
free(node)
```

Conversions between Variant and engine objects check the class: `Node(Variant(n))` works for any node, while `Node2D(Variant(n))` throws an `ArgumentError` when `n` is not a `Node2D`.
