# Collections

Counterpart of Godot's [C# collections](https://docs.godotengine.org/en/stable/tutorials/scripting/c_sharp/c_sharp_collections.html). Godot's `Array` and `Dictionary` are `GDArray` and `GDDictionary` in Julia. They implement Julia's `AbstractVector` and `AbstractDict` interfaces, so indexing, iteration, `push!`, `haskey` and so on work. Julia's own `Vector` and `Dict` are often simpler and faster; they convert to Godot collections whenever a Godot method needs one.

## Choosing a collection

| Use | When |
|-----|------|
| `Vector{T}`, `Dict{K,V}` | Julia-only data, hot loops (no engine calls) |
| `GDArray{T}`, `GDDictionary{K,V}` | values shared with the engine or other languages without copying, typed exports |
| `Packed*Array` | large numeric or vector data passed to the engine (meshes, images) |

## Arrays

```julia
a = GDArray{Int}([1, 2, 3])           # C#: new Godot.Collections.Array<int> { 1, 2, 3 }
push!(a, 4)
@test a[1] == 1 && length(a) == 4      # Julia indexing is 1-based
@test collect(a) == [1, 2, 3, 4]
@test sum(a) == 10
@test_throws Exception push!(a, "text")   # typed arrays check their element type

untyped = GDArray([1, "two", Vector2(3, 3)])   # GDArray{Any}, like an untyped Godot Array
@test untyped[2] == "two"
```

Engine methods returning `Array[T]` return a typed `GDArray{T}`, and Julia vectors convert when passed in:

```julia
n = Node()
for i in 1:3
    add_child(n, Node())
end
kids = get_children(n)
@test kids isa GDArray{Node} && length(kids) == 3
free(n)
```

## Dictionaries

```julia
d = GDDictionary{String, Int}("apples" => 3)    # C#: new Dictionary<string, int> { ["apples"] = 3 }
d["pears"] = 5
@test haskey(d, "pears") && d["apples"] == 3
@test sort(collect(keys(d))) == ["apples", "pears"]
@test get(d, "plums", 0) == 0
delete!(d, "apples")
@test length(d) == 1
```

## Packed arrays

Packed arrays hold numbers, vectors or colors contiguously. `Vector{T}` converts to and from them with a single copy:

```julia
p = PackedFloat32Array(Float32[1, 2, 3])
@test p[2] == 2.0f0
s = PackedStringArray(["a", "b"])
@test collect(s) == ["a", "b"]
pts = PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])
@test length(pts) == 2
```

## Converting

```julia
@test convert(Vector{Int}, GDArray([1, 2])) == [1, 2]
@test GDArray{Float64}([1.5, 2.5]) == [1.5, 2.5]
@test Dict(GDDictionary{String, Int}("a" => 1)) == Dict("a" => 1)
```
