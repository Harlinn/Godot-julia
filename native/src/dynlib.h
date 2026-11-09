// Copyright 2026 Espen Harlinn
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <string>

// Thin platform wrappers kept free of Godot headers (windows.h conflicts with godot-cpp macros).
namespace gdjl {

void *dynlib_open(const std::string &p_utf8_path, std::string &r_error);
void *dynlib_symbol(void *p_handle, const char *p_name);

} // namespace gdjl
