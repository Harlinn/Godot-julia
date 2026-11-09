// Copyright 2026 Espen Harlinn
// SPDX-License-Identifier: Apache-2.0

#pragma once

#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

// Engine singleton exposing the embedded Julia runtime's status to GDScript.
class JuliaRuntime : public Object {
	GDCLASS(JuliaRuntime, Object)

protected:
	static void _bind_methods();

public:
	bool is_available() const;
	String get_julia_version() const;
	String get_julia_home() const;
	void reload_scripts(const PackedStringArray &p_paths);
#ifdef DEBUG_ENABLED
	String eval_string(const String &p_code);
#endif
};

} // namespace godot
