// Copyright 2026 Espen Harlinn
// SPDX-License-Identifier: Apache-2.0

#include "register_types.h"

#include "julia_editor.h"
#include "julia_host.h"
#include "julia_runtime.h"
#include "julia_script.h"

#include <gdextension_interface.h>

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/core/memory.hpp>
#include <godot_cpp/godot.hpp>

using namespace godot;

static JuliaRuntime *julia_runtime_singleton = nullptr;

void initialize_godot_julia_module(ModuleInitializationLevel p_level) {
	if (p_level == MODULE_INITIALIZATION_LEVEL_EDITOR) {
		// Editor binaries also reach this level when running a game; like GodotSharpEditor, load only in the editor.
		if (Engine::get_singleton()->is_editor_hint()) {
			gdjl::JuliaHost::get_singleton().load_editor_api();
			gdjl::register_editor_types();
		}
		return;
	}
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(JuliaRuntime);
	julia_runtime_singleton = memnew(JuliaRuntime);
	Engine::get_singleton()->register_singleton("JuliaRuntime", julia_runtime_singleton);

	gdjl::JuliaHost::get_singleton().initialize();
	// Registered even when Julia is unavailable so .jl resources still load (as invalid scripts) instead of failing.
	gdjl::register_script_language();
}

void uninitialize_godot_julia_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	gdjl::unregister_script_language();
	gdjl::JuliaHost::get_singleton().shutdown();

	Engine::get_singleton()->unregister_singleton("JuliaRuntime");
	memdelete(julia_runtime_singleton);
	julia_runtime_singleton = nullptr;
}

extern "C" {
GDExtensionBool GDE_EXPORT godot_julia_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_godot_julia_module);
	init_obj.register_terminator(uninitialize_godot_julia_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
