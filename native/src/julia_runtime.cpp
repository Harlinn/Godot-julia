#include "julia_runtime.h"

#include "julia_host.h"
#include "julia_script.h"

#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace godot {

void JuliaRuntime::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &JuliaRuntime::is_available);
	ClassDB::bind_method(D_METHOD("get_julia_version"), &JuliaRuntime::get_julia_version);
	ClassDB::bind_method(D_METHOD("get_julia_home"), &JuliaRuntime::get_julia_home);
	ClassDB::bind_method(D_METHOD("reload_scripts", "paths"), &JuliaRuntime::reload_scripts);
#ifdef DEBUG_ENABLED
	ClassDB::bind_method(D_METHOD("eval_string", "code"), &JuliaRuntime::eval_string);
#endif
}

// What the remote debugger's "reload_scripts" message does (RemoteDebugger in core/debugger/remote_debugger.cpp).
void JuliaRuntime::reload_scripts(const PackedStringArray &p_paths) {
	gdjl::JuliaLanguage *language = gdjl::JuliaLanguage::get_singleton();
	ERR_FAIL_NULL(language);
	Array scripts;
	for (const String &path : p_paths) {
		Ref<Script> script = ResourceLoader::get_singleton()->load(path, "", ResourceLoader::CACHE_MODE_REUSE);
		ERR_CONTINUE_MSG(script.is_null(), "Could not reload script '" + path + "'.");
		scripts.push_back(script);
	}
	language->_reload_scripts(scripts, true);
}

bool JuliaRuntime::is_available() const {
	return gdjl::JuliaHost::get_singleton().is_ready();
}

String JuliaRuntime::get_julia_version() const {
	return gdjl::JuliaHost::get_singleton().get_version();
}

String JuliaRuntime::get_julia_home() const {
	return gdjl::JuliaHost::get_singleton().get_home();
}

#ifdef DEBUG_ENABLED
// Debug-only test hook: evaluates code in Main and returns `repr(result)`, or "" after reporting an error.
String JuliaRuntime::eval_string(const String &p_code) {
	String result;
	if (!gdjl::JuliaHost::get_singleton().eval_string(p_code, result)) {
		return String();
	}
	return result;
}
#endif

} // namespace godot
