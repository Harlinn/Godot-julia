# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

extends Node
# parity: 1.2


func _ready() -> void:
	print('GDJL_TEST_RESULT {"name":"smoke","passed":1,"failed":0,"errored":0,"broken":0}')
	get_tree().quit()
