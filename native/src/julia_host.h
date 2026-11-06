#pragma once

#include "gdjl_abi.h"

#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>
#include <string>
#include <vector>

namespace gdjl {

// Subset of the Julia embedding API, resolved at runtime (docs/adr/0002-runtime-loading.md).
struct JuliaCAPI {
	void (*jl_parse_opts)(int *argcp, char ***argvp) = nullptr;
	void (*jl_init_with_image_file)(const char *julia_bindir, const char *image_path) = nullptr;
	void *(*jl_eval_string)(const char *str) = nullptr;
	void *(*jl_exception_occurred)() = nullptr;
	void (*jl_exception_clear)() = nullptr;
	const char *(*jl_typeof_str)(void *v) = nullptr;
	const char *(*jl_string_ptr)(void *s) = nullptr;
	void **(*jl_adopt_thread)() = nullptr;
	void **(*jl_get_pgcstack)() = nullptr;
	int (*jl_ver_major)() = nullptr;
	int (*jl_ver_minor)() = nullptr;
	const char *(*jl_ver_string)() = nullptr;
	const char *(*jl_get_libjulia_internal_path)() = nullptr;
	// Out-of-line versions exported by libjulia-internal; they act on the calling thread.
	int8_t (*jl_gc_safe_enter)() = nullptr;
	void (*jl_gc_safe_leave)(int8_t state) = nullptr;
	int8_t (*jl_gc_unsafe_enter)() = nullptr;
	void (*jl_gc_unsafe_leave)(int8_t state) = nullptr;
};

// RAII guard for every entry from Godot into Julia: adopts foreign threads and holds GC-unsafe state.
class JuliaThreadGuard {
	const JuliaCAPI &api;
	int8_t previous_state = 0;
	bool adopted = false;

public:
	explicit JuliaThreadGuard(const JuliaCAPI &p_api);
	~JuliaThreadGuard();
	JuliaThreadGuard(const JuliaThreadGuard &) = delete;
	JuliaThreadGuard &operator=(const JuliaThreadGuard &) = delete;
};

class JuliaHost {
public:
	static JuliaHost &get_singleton();

	bool initialize();
	void shutdown();

	// Julia is running and `Godot.Runtime` finished bootstrapping.
	bool is_ready() const { return ready; }
	const JuliaCAPI &get_api() const { return api; }
	godot::String get_home() const { return godot::String::utf8(home_utf8.c_str()); }
	godot::String get_version() const { return godot::String::utf8(version_utf8.c_str()); }

	bool eval_string(const godot::String &p_code, godot::String &r_result);
	// Calls handler `p_method` of Godot.Runtime's script bridge; returns nil when Julia is not ready.
	void script_call(const char *p_method, void *p_self, const godot::Variant *const *p_args, int64_t p_argc, godot::Variant &r_ret);
	// Loads the editor-only API (Julia package GodotEditor, bound as Godot.Editor).
	void load_editor_api();

private:
	JuliaCAPI api;
	GDJLHostAPI host_api{};
	GDJLJuliaAPI julia_api{};
	void *libjulia = nullptr;
	bool running = false;
	bool ready = false;
	int8_t main_gc_state = 0;
	// Plain std::string: this object is static, and godot::String destructors must not run after Godot shuts down.
	std::string home_utf8;
	std::string version_utf8;
	// jl_options keeps pointers into these.
	std::vector<std::string> args;
	std::vector<char *> argv;
	std::string bindir_utf8;
	std::string image_utf8;
	// data_<name>_<platform>_<arch>/ of an exported game (empty in the editor and in unexported runs).
	std::string export_dir_utf8;

	void define_settings();
	godot::String find_export_dir() const;
	godot::String export_dir() const { return godot::String::utf8(export_dir_utf8.c_str()); }
	godot::Variant export_config(const godot::String &p_key, const godot::Variant &p_default) const;
	godot::String locate_runtime(godot::String &r_source) const;
	godot::String locate_packages() const;
	bool load_library(const godot::String &p_home);
	bool start_julia(const godot::String &p_home);
	bool bootstrap(godot::String &r_error);
	bool eval_checked(const godot::String &p_code, godot::String &r_error);
};

} // namespace gdjl
