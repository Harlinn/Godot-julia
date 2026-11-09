# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

extends Node
# GDScript side of the Variant tests: identity round trips, typed arrays, signals and Julia Callables.

signal ping(value)


func id(x):
	return x


func typed_ints() -> Array[int]:
	return [1, 2, 3]


func typed_nodes() -> Array[Node]:
	return [self]


func typed_dict() -> Dictionary[String, int]:
	return {"a": 1, "b": 2}


func call_it(c: Callable, arg):
	return c.call(arg)


func emit_ping(value) -> void:
	ping.emit(value)


func append_from_gdscript(a: Array) -> void:
	a.append("from gdscript")
