// Copyright 2026 Espen Harlinn
// SPDX-License-Identifier: Apache-2.0

#include "julia_host.h"

#include "dynlib.h"

#include <godot_cpp/classes/config_file.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <godot_cpp/classes/global_constants.hpp>

#include <algorithm>
#include <chrono>
#include <cstring>

using namespace godot;

namespace gdjl {

#if defined(_WIN32)
static const char *LIBJULIA_REL = "bin/libjulia.dll";
static const char *LIBJULIA_INTERNAL_REL = "bin/libjulia-internal.dll";
static const char *SYSIMAGE_REL = "lib/julia/sys.dll";
#elif defined(__APPLE__)
static const char *LIBJULIA_REL = "lib/libjulia.dylib";
static const char *LIBJULIA_INTERNAL_REL = "lib/julia/libjulia-internal.dylib";
static const char *SYSIMAGE_REL = "lib/julia/sys.dylib";
#else
static const char *LIBJULIA_REL = "lib/libjulia.so.1";
static const char *LIBJULIA_INTERNAL_REL = "lib/julia/libjulia-internal.so.1";
static const char *SYSIMAGE_REL = "lib/julia/sys.so";
#endif

static const int MIN_JULIA_MINOR = 12;
// Written by the export plugin into data_<name>_<platform>_<arch>/ (docs/adr/0014-export.md).
static const char *EXPORT_CONFIG = "godot_julia_export.cfg";

// --- Host callbacks handed to Julia -------------------------------------------------------

static void host_print(int32_t p_kind, const char *p_utf8, int64_t p_len) {
	String msg = String::utf8(p_utf8, p_len);
	if (p_kind == GDJL_PRINT_STDERR) {
		UtilityFunctions::printerr(msg);
	} else {
		UtilityFunctions::print(msg);
	}
}

static void host_report_error(int32_t p_is_warning, const char *p_function, const char *p_file, int32_t p_line, const char *p_utf8, int64_t p_len) {
	_err_print_error(p_function, p_file, p_line, String::utf8(p_utf8, p_len), false, p_is_warning != 0);
}

static void host_report_script_error(int32_t p_is_warning, const char *p_function, const char *p_file, int32_t p_line, const char *p_description, const char *p_message) {
	if (p_is_warning) {
		gdextension_interface::print_warning_with_message(p_description, p_message, p_function, p_file, p_line, false);
	} else {
		gdextension_interface::print_script_error_with_message(p_description, p_message, p_function, p_file, p_line, false);
	}
}

static void host_string_out(void *p_ctx, const char *p_utf8, int64_t p_len) {
	*static_cast<String *>(p_ctx) = String::utf8(p_utf8, p_len);
}

// --- Thread guard -------------------------------------------------------------------------

JuliaThreadGuard::JuliaThreadGuard(const JuliaCAPI &p_api) :
		api(p_api) {
	if (!api.jl_get_pgcstack()) {
		api.jl_adopt_thread();
		adopted = true;
	}
	previous_state = api.jl_gc_unsafe_enter();
}

JuliaThreadGuard::~JuliaThreadGuard() {
	api.jl_gc_unsafe_leave(previous_state);
	if (adopted) {
		// Adopted threads start GC-unsafe; park them in the safe state while they run Godot code.
		api.jl_gc_safe_enter();
	}
}

// --- Guarded callback trampolines ---------------------------------------------------------

static void *julia_callbacks[GDJL_CB_COUNT] = {};

template <int ID, typename R, typename... A>
struct CallbackTrampoline {
	static R call(A... p_args) {
		JuliaThreadGuard guard(JuliaHost::get_singleton().get_api());
		return reinterpret_cast<R (*)(A...)>(julia_callbacks[ID])(p_args...);
	}
};

#define GDJL_TRAMPOLINE(m_id, m_ret, ...) reinterpret_cast<void *>(&CallbackTrampoline<GDJL_CB_##m_id, m_ret, __VA_ARGS__>::call),
static void *const callback_trampolines[GDJL_CB_COUNT] = { GDJL_CALLBACKS(GDJL_TRAMPOLINE) };
#undef GDJL_TRAMPOLINE

static void *host_guard_callback(int32_t p_id, void *p_julia_fn) {
	ERR_FAIL_INDEX_V(p_id, int32_t(GDJL_CB_COUNT), nullptr);
	julia_callbacks[p_id] = p_julia_fn;
	return callback_trampolines[p_id];
}

// --- Helpers ------------------------------------------------------------------------------

static String normalize_dir(const String &p_dir) {
	String dir = p_dir.strip_edges().replace("\\", "/");
	while (dir.length() > 1 && dir.ends_with("/")) {
		dir = dir.substr(0, dir.length() - 1);
	}
	return dir;
}

// Accepts either the Julia install root or its bin/ directory.
static String home_from_dir(const String &p_dir) {
	String dir = normalize_dir(p_dir);
	if (dir.get_file() == "bin") {
		dir = dir.get_base_dir();
	}
	return dir;
}

static bool is_julia_home(const String &p_home) {
	return !p_home.is_empty() && FileAccess::file_exists(p_home.path_join(LIBJULIA_REL));
}

static Variant define_setting(const String &p_name, const Variant &p_default, Variant::Type p_type, PropertyHint p_hint = PROPERTY_HINT_NONE, const String &p_hint_string = "") {
	ProjectSettings *ps = ProjectSettings::get_singleton();
	if (!ps->has_setting(p_name)) {
		ps->set_setting(p_name, p_default);
	}
	ps->set_initial_value(p_name, p_default);
	Dictionary info;
	info["name"] = p_name;
	info["type"] = p_type;
	info["hint"] = p_hint;
	info["hint_string"] = p_hint_string;
	ps->add_property_info(info);
	return ps->get_setting(p_name);
}

static String get_library_dir() {
	String path;
	gdextension_interface::get_library_path(gdextension_interface::library, path._native_ptr());
	String dir = normalize_dir(ProjectSettings::get_singleton()->globalize_path(path)).get_base_dir();
	// macOS: the binary lives inside bin/<name>.framework/; report bin/ like on the other platforms.
	if (dir.ends_with(".framework")) {
		dir = dir.get_base_dir();
	}
	return dir;
}

template <typename T>
static bool resolve(void *p_handle, const char *p_name, T &r_fn) {
	r_fn = reinterpret_cast<T>(dynlib_symbol(p_handle, p_name));
	if (!r_fn) {
		ERR_PRINT(String("Godot-julia: missing Julia symbol ") + p_name);
		return false;
	}
	return true;
}

// --- JuliaHost ----------------------------------------------------------------------------

JuliaHost &JuliaHost::get_singleton() {
	static JuliaHost singleton;
	return singleton;
}

void JuliaHost::define_settings() {
	define_setting("julia/runtime/path", "", Variant::STRING, PROPERTY_HINT_GLOBAL_DIR);
	define_setting("julia/runtime/sysimage", "", Variant::STRING, PROPERTY_HINT_GLOBAL_FILE);
	define_setting("julia/runtime/depot_path", "", Variant::STRING, PROPERTY_HINT_GLOBAL_DIR);
	define_setting("julia/runtime/threads", 1, Variant::INT, PROPERTY_HINT_RANGE, "1,256,1");
	define_setting("julia/runtime/optimize", 2, Variant::INT, PROPERTY_HINT_RANGE, "0,3,1");
	define_setting("julia/runtime/handle_signals", true, Variant::BOOL);
	// Debugging (docs/debugging.md). The debug server only runs in debug builds and listens on localhost.
	define_setting("julia/debugger/port", 0, Variant::INT, PROPERTY_HINT_RANGE, "0,65535,1");
	define_setting("julia/debugger/wait_for_attach", false, Variant::BOOL);
	define_setting("julia/debugger/break_on_error", true, Variant::BOOL);
}

// Exported games keep the Julia payload in a data_*/ folder next to this library (like C#'s data_* folder); on macOS
// next to its .framework.
String JuliaHost::find_export_dir() const {
	String lib_dir = get_library_dir();
	for (const String &base : { lib_dir, lib_dir.get_base_dir() }) {
		for (const String &name : DirAccess::get_directories_at(base)) {
			String dir = base.path_join(name);
			if (name.begins_with("data_") && FileAccess::file_exists(dir.path_join(EXPORT_CONFIG))) {
				return dir;
			}
		}
	}
	return String();
}

Variant JuliaHost::export_config(const String &p_key, const Variant &p_default) const {
	Ref<ConfigFile> cfg;
	cfg.instantiate();
	if (export_dir_utf8.empty() || cfg->load(export_dir().path_join(EXPORT_CONFIG)) != OK) {
		return p_default;
	}
	return cfg->get_value("julia", p_key, p_default);
}

String JuliaHost::locate_runtime(String &r_source) const {
	if (!export_dir_utf8.empty()) {
		String home = export_dir().path_join("julia");
		r_source = "exported game";
		return is_julia_home(home) ? home : String();
	}

	String bundled = get_library_dir().path_join("julia");
	if (is_julia_home(bundled)) {
		r_source = "bundled runtime";
		return bundled;
	}

	String configured = home_from_dir(ProjectSettings::get_singleton()->get_setting("julia/runtime/path"));
	if (is_julia_home(configured)) {
		r_source = "project setting julia/runtime/path";
		return configured;
	}

	String env = OS::get_singleton()->get_environment("JULIA_BINDIR");
	if (!env.is_empty() && is_julia_home(home_from_dir(env))) {
		r_source = "JULIA_BINDIR";
		return home_from_dir(env);
	}

	PackedStringArray julia_args;
	julia_args.push_back("--startup-file=no");
	julia_args.push_back("-e");
	julia_args.push_back("print(Sys.BINDIR)");
	Array output;
	if (OS::get_singleton()->execute("julia", julia_args, output) == 0 && output.size() > 0) {
		String from_path = home_from_dir(String(output[0]));
		if (is_julia_home(from_path)) {
			r_source = "julia on PATH";
			return from_path;
		}
	}

#ifdef GDJL_DEV_JULIA_DIR
	String dev = home_from_dir(GDJL_DEV_JULIA_DIR);
	if (is_julia_home(dev)) {
		r_source = "build-time Julia (development build)";
		return dev;
	}
#endif
	return String();
}

String JuliaHost::locate_packages() const {
	if (!export_dir_utf8.empty()) {
		// System-image exports carry no package sources; jit exports ship them inside their depot (relocatable caches).
		String packages = export_dir().path_join("depot/packages");
		return DirAccess::dir_exists_absolute(packages) ? packages : String();
	}
	String addon_packages = get_library_dir().get_base_dir().path_join("julia");
	if (FileAccess::file_exists(addon_packages.path_join("Godot/src/Godot.jl"))) {
		return addon_packages;
	}
#ifdef GDJL_DEV_PACKAGES_DIR
	return normalize_dir(GDJL_DEV_PACKAGES_DIR);
#else
	return String();
#endif
}

bool JuliaHost::load_library(const String &p_home) {
#ifdef _WIN32
	// Julia's ccall loads its bundled DLLs (pcre2, gmp, ...) by bare name via the standard search path.
	String bin = p_home.path_join("bin").replace("/", "\\");
	String search_path = OS::get_singleton()->get_environment("PATH");
	if (!search_path.begins_with(bin + ";")) {
		OS::get_singleton()->set_environment("PATH", bin + ";" + search_path);
	}
#endif
	std::string error;
	String path = p_home.path_join(LIBJULIA_REL);
	libjulia = dynlib_open(path.utf8().get_data(), error);
	if (!libjulia) {
		ERR_PRINT("Godot-julia: could not load " + path + ": " + String::utf8(error.c_str()));
		return false;
	}

	bool ok = resolve(libjulia, "jl_parse_opts", api.jl_parse_opts) &&
			resolve(libjulia, "jl_init_with_image_file", api.jl_init_with_image_file) &&
			resolve(libjulia, "jl_eval_string", api.jl_eval_string) &&
			resolve(libjulia, "jl_exception_occurred", api.jl_exception_occurred) &&
			resolve(libjulia, "jl_exception_clear", api.jl_exception_clear) &&
			resolve(libjulia, "jl_typeof_str", api.jl_typeof_str) &&
			resolve(libjulia, "jl_string_ptr", api.jl_string_ptr) &&
			resolve(libjulia, "jl_adopt_thread", api.jl_adopt_thread) &&
			resolve(libjulia, "jl_get_pgcstack", api.jl_get_pgcstack) &&
			resolve(libjulia, "jl_ver_major", api.jl_ver_major) &&
			resolve(libjulia, "jl_ver_minor", api.jl_ver_minor) &&
			resolve(libjulia, "jl_ver_string", api.jl_ver_string);
	if (!ok) {
		return false;
	}
	// Julia 1.13+ reports where libjulia-internal is; 1.12 keeps it at its standard place in the install.
	api.jl_get_libjulia_internal_path = reinterpret_cast<const char *(*)()>(dynlib_symbol(libjulia, "jl_get_libjulia_internal_path"));
	std::string internal_path = api.jl_get_libjulia_internal_path ? std::string(api.jl_get_libjulia_internal_path())
																  : std::string(p_home.path_join(LIBJULIA_INTERNAL_REL).utf8().get_data());
	void *internal = dynlib_open(internal_path.c_str(), error);
	if (!internal) {
		ERR_PRINT("Godot-julia: could not open libjulia-internal: " + String::utf8(error.c_str()));
		return false;
	}
	return resolve(internal, "jl_gc_safe_enter", api.jl_gc_safe_enter) &&
			resolve(internal, "jl_gc_safe_leave", api.jl_gc_safe_leave) &&
			resolve(internal, "jl_gc_unsafe_enter", api.jl_gc_unsafe_enter) &&
			resolve(internal, "jl_gc_unsafe_leave", api.jl_gc_unsafe_leave);
}

bool JuliaHost::start_julia(const String &p_home) {
	ProjectSettings *ps = ProjectSettings::get_singleton();
	int threads = std::max(1, int(ps->get_setting("julia/runtime/threads")));
	int optimize = std::clamp(int(export_config("optimize", ps->get_setting("julia/runtime/optimize"))), 0, 3);
	bool handle_signals = ps->get_setting("julia/runtime/handle_signals");

	// Thread count goes through options: on Windows Julia's C getenv does not see variables set at runtime.
	args = {
		"godot-julia",
		"--startup-file=no",
		"--history-file=no",
		"--threads=" + std::to_string(threads),
		"-O" + std::to_string(optimize),
		std::string("--handle-signals=") + (handle_signals ? "yes" : "no"),
	};
	String project_dir = normalize_dir(ps->globalize_path("res://"));
	if (!export_dir_utf8.empty()) {
		project_dir = export_dir().path_join("env");
	}
	if (FileAccess::file_exists(project_dir.path_join("Project.toml"))) {
		args.push_back(std::string("--project=") + project_dir.utf8().get_data());
	}
	argv.clear();
	for (std::string &arg : args) {
		argv.push_back(arg.data());
	}
	argv.push_back(nullptr);
	int argc = int(args.size());
	char **argvp = argv.data();
	api.jl_parse_opts(&argc, &argvp);

	String sysimage = normalize_dir(ps->get_setting("julia/runtime/sysimage"));
	if (!export_dir_utf8.empty()) {
		String image = export_config("sysimage", "");
		sysimage = image.is_empty() ? String() : export_dir().path_join(image);
	}
	if (sysimage.is_empty()) {
		sysimage = p_home.path_join(SYSIMAGE_REL);
	}
	if (!FileAccess::file_exists(sysimage)) {
		ERR_PRINT("Godot-julia: Julia system image not found: " + sysimage);
		return false;
	}
	bindir_utf8 = p_home.path_join("bin").utf8().get_data();
	image_utf8 = sysimage.utf8().get_data();
	api.jl_init_with_image_file(bindir_utf8.c_str(), image_utf8.c_str());
	running = true;
	return true;
}

bool JuliaHost::eval_checked(const String &p_code, String &r_error) {
	void *result = api.jl_eval_string(p_code.utf8().get_data());
	if (!result) {
		void *exception = api.jl_exception_occurred();
		r_error = String("Julia raised ") + (exception ? api.jl_typeof_str(exception) : "an unknown exception");
		api.jl_exception_clear();
		return false;
	}
	// Bootstrap snippets return a String only to describe a failure.
	if (std::strcmp(api.jl_typeof_str(result), "String") == 0) {
		r_error = String::utf8(api.jl_string_ptr(result));
		return false;
	}
	return true;
}

bool JuliaHost::bootstrap(String &r_error) {
	String packages = locate_packages();
	bool exported = !export_dir_utf8.empty();
	if (packages.is_empty() && !exported) {
		r_error = "the Godot Julia package was not found (expected addons/godot_julia/julia/Godot)";
		return false;
	}

	// Isolate games from the user's global environment, like C# projects only see referenced packages.
	String setup = "empty!(LOAD_PATH); append!(LOAD_PATH, [\"@\", " + (packages.is_empty() ? String() : "raw\"" + packages + "\", ") + "\"@stdlib\"]);";
	String depot = normalize_dir(ProjectSettings::get_singleton()->get_setting("julia/runtime/depot_path"));
	if (exported) {
		// Only the game's own depot (compiled caches of jit exports) and the bundled runtime's.
		setup += " empty!(DEPOT_PATH); append!(DEPOT_PATH, [raw\"" + export_dir().path_join("depot") + "\", raw\"" +
				export_dir().path_join("julia/share/julia") + "\"]);";
	} else if (!depot.is_empty()) {
		setup += " pushfirst!(DEPOT_PATH, raw\"" + depot + "\");";
	}
	if (!eval_checked(setup + " nothing", r_error)) {
		return false;
	}

	if (!eval_checked("try; using Godot; nothing; catch e; sprint(showerror, e, catch_backtrace()); end", r_error)) {
		return false;
	}
	if (exported && !eval_checked("Godot.Runtime.EXPORT_DIR[] = raw\"" + export_dir() + "\"; nothing", r_error)) {
		return false;
	}

	host_api.abi_version = GDJL_ABI_VERSION;
	host_api.size = sizeof(GDJLHostAPI);
#ifdef REAL_T_IS_DOUBLE
	host_api.real_t_size = 8;
#else
	host_api.real_t_size = 4;
#endif
	host_api.print = &host_print;
	host_api.report_error = &host_report_error;
	host_api.string_out = &host_string_out;
	host_api.guard_callback = &host_guard_callback;
	host_api.report_script_error = &host_report_script_error;
	julia_api = {};
	julia_api.abi_version = GDJL_ABI_VERSION;
	julia_api.size = sizeof(GDJLJuliaAPI);

	auto hex = [](const void *p_ptr) { return "0x" + String::num_uint64(uint64_t(uintptr_t(p_ptr)), 16); };
	String init = "try; Godot.Runtime.__init_runtime__(Ptr{Cvoid}(" + hex(reinterpret_cast<const void *>(gdextension_interface::get_proc_address)) +
			"), Ptr{Cvoid}(" + hex(gdextension_interface::library) +
			"), Ptr{Godot.Runtime.HostAPI}(" + hex(&host_api) +
			"), Ptr{Godot.Runtime.JuliaAPI}(" + hex(&julia_api) +
			")) ? nothing : \"__init_runtime__ returned false\"; catch e; sprint(showerror, e, catch_backtrace()); end";
	if (!eval_checked(init, r_error)) {
		return false;
	}
	if (!julia_api.eval_string || !julia_api.shutdown || !julia_api.script_call) {
		r_error = "Godot.Runtime did not provide its entry points";
		return false;
	}
	return true;
}

bool JuliaHost::initialize() {
	using Clock = std::chrono::steady_clock;
	auto ms_since = [](Clock::time_point p_start) {
		return std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - p_start).count();
	};
	Clock::time_point start = Clock::now();

	define_settings();
	export_dir_utf8 = find_export_dir().utf8().get_data();
	String source;
	String home = locate_runtime(source);
	if (home.is_empty()) {
		if (!export_dir_utf8.empty()) {
			ERR_PRINT("Godot-julia: the exported Julia runtime is missing from " + export_dir() + "/julia. Julia scripting is disabled.");
			return false;
		}
		ERR_PRINT("Godot-julia: Julia runtime not found. Install Julia >= 1." + String::num_int64(MIN_JULIA_MINOR) +
				" and put it on PATH, or set the project setting julia/runtime/path. Julia scripting is disabled.");
		return false;
	}
	home_utf8 = home.utf8().get_data();
	if (!load_library(home)) {
		return false;
	}
	int64_t locate_ms = ms_since(start);
	String version = String::utf8(api.jl_ver_string());
	version_utf8 = version.utf8().get_data();
	if (api.jl_ver_major() != 1 || api.jl_ver_minor() < MIN_JULIA_MINOR) {
		ERR_PRINT("Godot-julia: Julia " + version + " is not supported; Julia >= 1." + String::num_int64(MIN_JULIA_MINOR) + " is required.");
		return false;
	}
	if (!start_julia(home)) {
		return false;
	}
	int64_t init_ms = ms_since(start) - locate_ms;

	String error;
	ready = bootstrap(error);
	// From now on the main thread runs Godot code; let Julia's GC proceed without waiting for it.
	main_gc_state = api.jl_gc_safe_enter();
	if (!ready) {
		ERR_PRINT("Godot-julia: failed to start Godot.Runtime: " + error);
		return false;
	}
	int64_t total_ms = ms_since(start);
	UtilityFunctions::print("Godot-julia: Julia " + version + " from " + home + " (" + source + "); startup " + String::num_int64(total_ms) +
			" ms (locate " + String::num_int64(locate_ms) + " ms, jl_init " + String::num_int64(init_ms) + " ms, Godot.Runtime " +
			String::num_int64(total_ms - locate_ms - init_ms) + " ms)");
	return true;
}

void JuliaHost::shutdown() {
	if (!running) {
		return;
	}
	if (ready) {
		JuliaThreadGuard guard(api);
		julia_api.shutdown();
	}
	ready = false;
	// jl_atexit_hook is deliberately not called (the runtime ends with the process, as the CLR does for Godot's C#
	// module): it suspends every other Julia thread, including engine threads Julia adopted, and those threads then
	// block forever in Julia's thread-detach hook when Godot joins them. User atexit hooks run in `_shutdown`.
	// The main thread stays parked GC-safe.
	running = false;
}

bool JuliaHost::eval_string(const String &p_code, String &r_result) {
	ERR_FAIL_COND_V_MSG(!ready, false, "Godot-julia: the Julia runtime is not available.");
	CharString code = p_code.utf8();
	JuliaThreadGuard guard(api);
	return julia_api.eval_string(code.get_data(), code.length(), &r_result) == 0;
}

void JuliaHost::script_call(const char *p_method, void *p_self, const Variant *const *p_args, int64_t p_argc, Variant &r_ret) {
	if (!ready) {
		return;
	}
	JuliaThreadGuard guard(api);
	julia_api.script_call(p_method, p_self, reinterpret_cast<const void *const *>(p_args), p_argc, r_ret._native_ptr());
}

void JuliaHost::load_editor_api() {
	if (!ready) {
		return;
	}
	auto start = std::chrono::steady_clock::now();
	String error;
	bool ok;
	{
		JuliaThreadGuard guard(api);
		ok = eval_checked("try; Godot.Runtime.load_editor_api!(); nothing; catch e; sprint(showerror, e, catch_backtrace()); end", error);
	}
	if (!ok) {
		ERR_PRINT("Godot-julia: failed to load the editor API (GodotEditor): " + error);
		return;
	}
	int64_t ms = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start).count();
	UtilityFunctions::print("Godot-julia: editor API (Godot.Editor) loaded in " + String::num_int64(ms) + " ms");
}

} // namespace gdjl
