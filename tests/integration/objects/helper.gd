extends Node
# GDScript side of the object-model tests.

var score := 5


func add(x: int) -> int:
	return score + x


func free_it(o: Object) -> void:
	o.free()


func keep(o: Object) -> Object:
	set_meta("kept", o)
	return o


func drop() -> void:
	remove_meta("kept")
