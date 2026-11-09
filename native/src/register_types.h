// Copyright 2026 Espen Harlinn
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <godot_cpp/core/class_db.hpp>

void initialize_godot_julia_module(godot::ModuleInitializationLevel p_level);
void uninitialize_godot_julia_module(godot::ModuleInitializationLevel p_level);
