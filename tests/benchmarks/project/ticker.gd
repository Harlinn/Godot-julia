extends Node

var n := 0


func _process(_delta: float) -> void:
	n += 1


func noop(x: int) -> int:
	return x
