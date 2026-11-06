#include "julia_script.h"

#include "julia_host.h"

#include <godot_cpp/classes/editor_interface.hpp>
#include <godot_cpp/classes/editor_settings.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/resource_saver.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/memory.hpp>

using namespace godot;

namespace gdjl {

namespace {

// Calls handler `p_method` of Godot.Runtime's script bridge with `p_self`'s engine object as `self`.
template <typename... Args>
Variant jl(const char *p_method, const Object *p_self, const Args &...p_args) {
	const Variant args[] = { Variant(p_args)..., Variant() };
	const Variant *ptrs[sizeof...(Args) + 1] = {};
	for (size_t i = 0; i < sizeof...(Args); i++) {
		ptrs[i] = &args[i];
	}
	Variant ret;
	JuliaHost::get_singleton().script_call(p_method, p_self ? p_self->_owner : nullptr, ptrs, int64_t(sizeof...(Args)), ret);
	return ret;
}

// Conversions that tolerate nil (Julia not running, or a handler that failed and reported its error).
bool as_bool(const Variant &p_v) {
	return p_v.get_type() == Variant::BOOL && bool(p_v);
}

int64_t as_int(const Variant &p_v, int64_t p_default) {
	return p_v.get_type() == Variant::INT ? int64_t(p_v) : p_default;
}

String as_string(const Variant &p_v) {
	if (p_v.get_type() == Variant::STRING) {
		return p_v;
	}
	if (p_v.get_type() == Variant::STRING_NAME) {
		return String(StringName(p_v));
	}
	return String();
}

StringName as_string_name(const Variant &p_v) {
	if (p_v.get_type() == Variant::STRING_NAME) {
		return p_v;
	}
	if (p_v.get_type() == Variant::STRING) {
		return StringName(String(p_v));
	}
	return StringName();
}

Dictionary as_dict(const Variant &p_v) {
	return p_v.get_type() == Variant::DICTIONARY ? Dictionary(p_v) : Dictionary();
}

Array as_array(const Variant &p_v) {
	return p_v.get_type() == Variant::ARRAY ? Array(p_v) : Array();
}

int64_t object_handle(const Object *p_object) {
	return p_object ? int64_t(uintptr_t(p_object->_owner)) : 0;
}

PackedStringArray strings(std::initializer_list<const char *> p_items) {
	PackedStringArray r;
	for (const char *s : p_items) {
		r.push_back(s);
	}
	return r;
}

} // namespace

// --- JuliaLanguage ------------------------------------------------------------------------------------------------

JuliaLanguage *JuliaLanguage::singleton = nullptr;

JuliaLanguage::JuliaLanguage() {
	singleton = this;
}

JuliaLanguage::~JuliaLanguage() {
	if (singleton == this) {
		singleton = nullptr;
	}
}

String JuliaLanguage::_get_name() const {
	return "Julia";
}

void JuliaLanguage::_init() {
	jl("language_init", this);
}

String JuliaLanguage::_get_type() const {
	return "JuliaScript";
}

String JuliaLanguage::_get_extension() const {
	return "jl";
}

void JuliaLanguage::_finish() {
	jl("language_finish", this);
}

PackedStringArray JuliaLanguage::_get_reserved_words() const {
	return strings({ "baremodule", "begin", "break", "catch", "const", "continue", "do", "else", "elseif", "end",
			"export", "false", "finally", "for", "function", "global", "if", "import", "let", "local", "macro",
			"module", "quote", "return", "struct", "true", "try", "using", "while", "abstract", "mutable", "primitive",
			"type", "where", "in", "isa", "outer", "public", "nothing", "missing" });
}

bool JuliaLanguage::_is_control_flow_keyword(const String &p_keyword) const {
	static const char *keywords[] = { "break", "catch", "continue", "do", "else", "elseif", "finally", "for", "if",
		"return", "try", "while" };
	for (const char *k : keywords) {
		if (p_keyword == k) {
			return true;
		}
	}
	return false;
}

PackedStringArray JuliaLanguage::_get_comment_delimiters() const {
	return strings({ "#", "#= =#" });
}

PackedStringArray JuliaLanguage::_get_doc_comment_delimiters() const {
	// Julia documents code with docstrings rather than comments.
	return PackedStringArray();
}

PackedStringArray JuliaLanguage::_get_string_delimiters() const {
	return strings({ "\"\"\" \"\"\"", "\" \"", "` `" });
}

Ref<Script> JuliaLanguage::_make_template(const String &p_template, const String &p_class_name, const String &p_base_class_name) const {
	Ref<JuliaScript> script;
	script.instantiate();
	script->set_source_code(as_string(jl("make_template", this, p_template, p_class_name, p_base_class_name)));
	return script;
}

TypedArray<Dictionary> JuliaLanguage::_get_built_in_templates(const StringName &p_object) const {
	return TypedArray<Dictionary>(as_array(jl("get_built_in_templates", this, p_object)));
}

bool JuliaLanguage::_is_using_templates() {
	return true;
}

Dictionary JuliaLanguage::_validate(const String &p_script, const String &p_path, bool p_validate_functions, bool p_validate_errors, bool p_validate_warnings, bool p_validate_safe_lines) const {
	Dictionary r = as_dict(jl("validate", this, p_script, p_path, p_validate_functions, p_validate_errors, p_validate_warnings, p_validate_safe_lines));
	if (!r.has("valid")) {
		r["valid"] = true;
	}
	return r;
}

String JuliaLanguage::_validate_path(const String &p_path) const {
	return as_string(jl("validate_path", this, p_path));
}

Object *JuliaLanguage::_create_script() const {
	// Deprecated in Godot 4.7 (scripts are created with _make_template). The caller wraps the raw pointer in a Ref,
	// which adds a reference; hand over the one we hold so the object survives (godot-cpp's Ref has no release()).
	Ref<JuliaScript> script = memnew(JuliaScript);
	script->reference();
	return script.ptr();
}

bool JuliaLanguage::_has_named_classes() const {
	return false;
}

bool JuliaLanguage::_supports_builtin_mode() const {
	return false;
}

bool JuliaLanguage::_supports_documentation() const {
	return false;
}

bool JuliaLanguage::_can_inherit_from_file() const {
	return true;
}

int32_t JuliaLanguage::_find_function(const String &p_function, const String &p_code) const {
	return int32_t(as_int(jl("find_function", this, p_function, p_code), -1));
}

String JuliaLanguage::_make_function(const String &p_class_name, const String &p_function_name, const PackedStringArray &p_function_args) const {
	return as_string(jl("make_function", this, p_class_name, p_function_name, p_function_args));
}

bool JuliaLanguage::_can_make_function() const {
	return true;
}

Error JuliaLanguage::_open_in_external_editor(const Ref<Script> &p_script, int32_t p_line, int32_t p_column) {
	return Error(as_int(jl("open_in_external_editor", this, p_script, p_line, p_column), int64_t(ERR_UNAVAILABLE)));
}

bool JuliaLanguage::_overrides_external_editor() {
	return as_bool(jl("overrides_external_editor", this));
}

ScriptLanguage::ScriptNameCasing JuliaLanguage::_preferred_file_name_casing() const {
	return ScriptLanguage::SCRIPT_NAME_CASING_PASCAL_CASE;
}

Dictionary JuliaLanguage::_complete_code(const String &p_code, const String &p_path, Object *p_owner) const {
	return Dictionary();
}

Dictionary JuliaLanguage::_lookup_code(const String &p_code, const String &p_symbol, const String &p_path, Object *p_owner) const {
	return Dictionary();
}

String JuliaLanguage::_auto_indent_code(const String &p_code, int32_t p_from_line, int32_t p_to_line) const {
	return p_code;
}

void JuliaLanguage::_add_global_constant(const StringName &p_name, const Variant &p_value) {}

void JuliaLanguage::_add_named_global_constant(const StringName &p_name, const Variant &p_value) {}

void JuliaLanguage::_remove_named_global_constant(const StringName &p_name) {}

// Foreign threads are adopted lazily by JuliaThreadGuard on their first call into Julia.
void JuliaLanguage::_thread_enter() {}

void JuliaLanguage::_thread_exit() {}

String JuliaLanguage::_debug_get_error() const {
	return as_string(jl("debug_get_error", this));
}

int32_t JuliaLanguage::_debug_get_stack_level_count() const {
	return int32_t(as_int(jl("debug_get_stack_level_count", this), 0));
}

int32_t JuliaLanguage::_debug_get_stack_level_line(int32_t p_level) const {
	return int32_t(as_int(jl("debug_get_stack_level_line", this, p_level), -1));
}

String JuliaLanguage::_debug_get_stack_level_function(int32_t p_level) const {
	return as_string(jl("debug_get_stack_level_function", this, p_level));
}

String JuliaLanguage::_debug_get_stack_level_source(int32_t p_level) const {
	return as_string(jl("debug_get_stack_level_source", this, p_level));
}

Dictionary JuliaLanguage::_debug_get_stack_level_locals(int32_t p_level, int32_t p_max_subitems, int32_t p_max_depth) {
	return as_dict(jl("debug_get_stack_level_locals", this, p_level, p_max_subitems, p_max_depth));
}

Dictionary JuliaLanguage::_debug_get_stack_level_members(int32_t p_level, int32_t p_max_subitems, int32_t p_max_depth) {
	return as_dict(jl("debug_get_stack_level_members", this, p_level, p_max_subitems, p_max_depth));
}

void *JuliaLanguage::_debug_get_stack_level_instance(int32_t p_level) {
	return nullptr;
}

Dictionary JuliaLanguage::_debug_get_globals(int32_t p_max_subitems, int32_t p_max_depth) {
	return as_dict(jl("debug_get_globals", this, p_max_subitems, p_max_depth));
}

String JuliaLanguage::_debug_parse_stack_level_expression(int32_t p_level, const String &p_expression, int32_t p_max_subitems, int32_t p_max_depth) {
	return as_string(jl("debug_parse_stack_level_expression", this, p_level, p_expression, p_max_subitems, p_max_depth));
}

// Called by Godot for every error it reports (any thread), to attach the Julia frames of the current call stack.
TypedArray<Dictionary> JuliaLanguage::_debug_get_current_stack_info() {
	return TypedArray<Dictionary>(as_array(jl("debug_get_current_stack_info", this)));
}

void JuliaLanguage::_reload_all_scripts() {
	jl("language_reload_all_scripts", this);
}

void JuliaLanguage::_reload_scripts(const Array &p_scripts, bool p_soft_reload) {
	jl("language_reload_scripts", this, p_scripts, p_soft_reload);
}

void JuliaLanguage::_reload_tool_script(const Ref<Script> &p_script, bool p_soft_reload) {
	jl("language_reload_tool_script", this, p_script, p_soft_reload);
}

PackedStringArray JuliaLanguage::_get_recognized_extensions() const {
	return strings({ "jl" });
}

TypedArray<Dictionary> JuliaLanguage::_get_public_functions() const {
	return TypedArray<Dictionary>();
}

Dictionary JuliaLanguage::_get_public_constants() const {
	return Dictionary();
}

TypedArray<Dictionary> JuliaLanguage::_get_public_annotations() const {
	return TypedArray<Dictionary>();
}

void JuliaLanguage::_profiling_start() {}

void JuliaLanguage::_profiling_stop() {}

void JuliaLanguage::_profiling_set_save_native_calls(bool p_enable) {}

int32_t JuliaLanguage::_profiling_get_accumulated_data(ScriptLanguageExtensionProfilingInfo *p_info_array, int32_t p_info_max) {
	return 0;
}

int32_t JuliaLanguage::_profiling_get_frame_data(ScriptLanguageExtensionProfilingInfo *p_info_array, int32_t p_info_max) {
	return 0;
}

void JuliaLanguage::_frame() {
	jl("language_frame", this);
}

bool JuliaLanguage::_handles_global_class_type(const String &p_type) const {
	return p_type == "JuliaScript";
}

Dictionary JuliaLanguage::_get_global_class_name(const String &p_path) const {
	return as_dict(jl("get_global_class_name", this, p_path));
}

// --- JuliaScript --------------------------------------------------------------------------------------------------

JuliaScript::~JuliaScript() {
	jl("script_free", this);
}

void JuliaScript::_bind_methods() {
	MethodInfo mi("call_static", PropertyInfo(Variant::STRING_NAME, "method"));
	ClassDB::bind_vararg_method(METHOD_FLAGS_DEFAULT, "call_static", &JuliaScript::call_static, mi);
}

Variant JuliaScript::call_static(const Variant **p_args, GDExtensionInt p_arg_count, GDExtensionCallError &r_error) {
	if (p_arg_count < 1) {
		r_error.error = GDEXTENSION_CALL_ERROR_TOO_FEW_ARGUMENTS;
		r_error.expected = 1;
		return Variant();
	}
	r_error.error = GDEXTENSION_CALL_OK;
	Array args;
	for (GDExtensionInt i = 1; i < p_arg_count; i++) {
		args.push_back(*p_args[i]);
	}
	return jl("script_call_static", this, StringName(*p_args[0]), args);
}

String JuliaScript::get_script_path() const {
	String path = get_path();
	return path.is_empty() ? load_path : path;
}

bool JuliaScript::_editor_can_reload_from_file() {
	return true;
}

void JuliaScript::_placeholder_erased(void *p_placeholder) {
	jl("script_placeholder_erased", this, int64_t(uintptr_t(p_placeholder)));
}

bool JuliaScript::_can_instantiate() const {
	return as_bool(jl("script_can_instantiate", this));
}

Ref<Script> JuliaScript::_get_base_script() const {
	Variant base = jl("script_get_base_script", this);
	if (base.get_type() != Variant::OBJECT) {
		return Ref<Script>();
	}
	return Ref<Script>(Object::cast_to<Script>(base.operator Object *()));
}

StringName JuliaScript::_get_global_name() const {
	return as_string_name(jl("script_get_global_name", this));
}

bool JuliaScript::_inherits_script(const Ref<Script> &p_script) const {
	if (p_script.is_null()) {
		return false;
	}
	Ref<Script> s = _get_base_script();
	if (p_script.ptr() == this) {
		return true;
	}
	int depth = 0;
	while (s.is_valid() && depth++ < 64) {
		if (s == p_script) {
			return true;
		}
		s = s->get_base_script();
	}
	return false;
}

StringName JuliaScript::_get_instance_base_type() const {
	return as_string_name(jl("script_get_instance_base_type", this));
}

void *JuliaScript::_instance_create(Object *p_for_object) const {
	return reinterpret_cast<void *>(uintptr_t(as_int(jl("script_instance_create", this, object_handle(p_for_object)), 0)));
}

void *JuliaScript::_placeholder_instance_create(Object *p_for_object) const {
	return reinterpret_cast<void *>(uintptr_t(as_int(jl("script_placeholder_create", this, object_handle(p_for_object)), 0)));
}

bool JuliaScript::_has_source_code() const {
	return !source_code.is_empty();
}

String JuliaScript::_get_source_code() const {
	return source_code;
}

void JuliaScript::_set_source_code(const String &p_code) {
	source_code = p_code;
}

Error JuliaScript::_reload(bool p_keep_state) {
	return Error(as_int(jl("script_reload", this, source_code, get_script_path(), p_keep_state), int64_t(ERR_UNAVAILABLE)));
}

StringName JuliaScript::_get_doc_class_name() const {
	return _get_global_name();
}

TypedArray<Dictionary> JuliaScript::_get_documentation() const {
	return TypedArray<Dictionary>();
}

String JuliaScript::_get_class_icon_path() const {
	return as_string(jl("script_get_icon_path", this));
}

bool JuliaScript::_has_method(const StringName &p_method) const {
	return as_bool(jl("script_has_method", this, p_method));
}

bool JuliaScript::_has_static_method(const StringName &p_method) const {
	return as_bool(jl("script_has_static_method", this, p_method));
}

Variant JuliaScript::_get_script_method_argument_count(const StringName &p_method) const {
	return jl("script_get_method_argument_count", this, p_method);
}

Dictionary JuliaScript::_get_method_info(const StringName &p_method) const {
	return as_dict(jl("script_get_method_info", this, p_method));
}

bool JuliaScript::_is_tool() const {
	return as_bool(jl("script_is_tool", this));
}

bool JuliaScript::_is_valid() const {
	return as_bool(jl("script_is_valid", this));
}

bool JuliaScript::_is_abstract() const {
	return as_bool(jl("script_is_abstract", this));
}

ScriptLanguage *JuliaScript::_get_language() const {
	return JuliaLanguage::get_singleton();
}

bool JuliaScript::_has_script_signal(const StringName &p_signal) const {
	return as_bool(jl("script_has_signal", this, p_signal));
}

TypedArray<Dictionary> JuliaScript::_get_script_signal_list() const {
	return TypedArray<Dictionary>(as_array(jl("script_get_signal_list", this)));
}

bool JuliaScript::_has_property_default_value(const StringName &p_property) const {
	return as_bool(jl("script_has_property_default", this, p_property));
}

Variant JuliaScript::_get_property_default_value(const StringName &p_property) const {
	return jl("script_get_property_default", this, p_property);
}

void JuliaScript::_update_exports() {
	jl("script_update_exports", this);
}

TypedArray<Dictionary> JuliaScript::_get_script_method_list() const {
	return TypedArray<Dictionary>(as_array(jl("script_get_method_list", this)));
}

TypedArray<Dictionary> JuliaScript::_get_script_property_list() const {
	return TypedArray<Dictionary>(as_array(jl("script_get_property_list", this)));
}

int32_t JuliaScript::_get_member_line(const StringName &p_member) const {
	return int32_t(as_int(jl("script_get_member_line", this, p_member), -1));
}

Dictionary JuliaScript::_get_constants() const {
	return Dictionary();
}

TypedArray<StringName> JuliaScript::_get_members() const {
	return TypedArray<StringName>(as_array(jl("script_get_members", this)));
}

bool JuliaScript::_is_placeholder_fallback_enabled() const {
	return false;
}

Variant JuliaScript::_get_rpc_config() const {
	return as_dict(jl("script_get_rpc_config", this));
}

bool JuliaScript::_instance_has(Object *p_object) const {
	return as_bool(jl("script_instance_has", this, object_handle(p_object)));
}

// --- Resource loader / saver --------------------------------------------------------------------------------------

PackedStringArray ResourceFormatLoaderJulia::_get_recognized_extensions() const {
	return strings({ "jl" });
}

bool ResourceFormatLoaderJulia::_handles_type(const StringName &p_type) const {
	return p_type == StringName("Script") || p_type == StringName("JuliaScript");
}

String ResourceFormatLoaderJulia::_get_resource_type(const String &p_path) const {
	return p_path.get_extension().to_lower() == "jl" ? "JuliaScript" : "";
}

Variant ResourceFormatLoaderJulia::_load(const String &p_path, const String &p_original_path, bool p_use_sub_threads, int32_t p_cache_mode) const {
	String source = FileAccess::get_file_as_string(p_path);
	Error err = FileAccess::get_open_error();
	if (err != OK) {
		return int64_t(err);
	}
	Ref<JuliaScript> script;
	script.instantiate();
	script->set_source_code(source);
	script->set_load_path(p_original_path.is_empty() ? p_path : p_original_path);
	// Errors are reported by Godot.Runtime; like GDScript and C#, an invalid script is still returned.
	script->reload(false);
	return script;
}

Error ResourceFormatSaverJulia::_save(const Ref<Resource> &p_resource, const String &p_path, uint32_t p_flags) {
	Ref<JuliaScript> script = p_resource;
	ERR_FAIL_COND_V(script.is_null(), ERR_INVALID_PARAMETER);
	Ref<FileAccess> file = FileAccess::open(p_path, FileAccess::WRITE);
	if (file.is_null()) {
		return FileAccess::get_open_error();
	}
	file->store_string(script->get_source_code());
	Error err = file->get_error();
	if (err != OK && err != ERR_FILE_EOF) {
		return ERR_CANT_CREATE;
	}
	// Like ResourceFormatSaverGDScript: saving in the editor hot-reloads the script (tool instances keep their state).
	EditorInterface *ei = Engine::get_singleton()->is_editor_hint() ? EditorInterface::get_singleton() : nullptr;
	Ref<EditorSettings> es = ei ? ei->get_editor_settings() : Ref<EditorSettings>();
	if (es.is_valid() && bool(es->get_setting("text_editor/behavior/files/auto_reload_and_parse_scripts_on_save")) &&
			JuliaLanguage::get_singleton()) {
		file.unref();
		JuliaLanguage::get_singleton()->_reload_tool_script(script, true);
	}
	return OK;
}

bool ResourceFormatSaverJulia::_recognize(const Ref<Resource> &p_resource) const {
	return Object::cast_to<JuliaScript>(p_resource.ptr()) != nullptr;
}

PackedStringArray ResourceFormatSaverJulia::_get_recognized_extensions(const Ref<Resource> &p_resource) const {
	return _recognize(p_resource) ? strings({ "jl" }) : PackedStringArray();
}

// --- Registration -------------------------------------------------------------------------------------------------

static JuliaLanguage *language = nullptr;
static Ref<ResourceFormatLoaderJulia> loader;
static Ref<ResourceFormatSaverJulia> saver;

void register_script_language() {
	GDREGISTER_INTERNAL_CLASS(JuliaLanguage);
	GDREGISTER_CLASS(JuliaScript);
	GDREGISTER_INTERNAL_CLASS(ResourceFormatLoaderJulia);
	GDREGISTER_INTERNAL_CLASS(ResourceFormatSaverJulia);

	language = memnew(JuliaLanguage);
	Engine::get_singleton()->register_script_language(language);
	jl("language_init", language);

	loader.instantiate();
	ResourceLoader::get_singleton()->add_resource_format_loader(loader);
	saver.instantiate();
	ResourceSaver::get_singleton()->add_resource_format_saver(saver);
}

void unregister_script_language() {
	if (loader.is_valid()) {
		ResourceLoader::get_singleton()->remove_resource_format_loader(loader);
		loader.unref();
	}
	if (saver.is_valid()) {
		ResourceSaver::get_singleton()->remove_resource_format_saver(saver);
		saver.unref();
	}
	if (language) {
		Engine::get_singleton()->unregister_script_language(language);
		memdelete(language);
		language = nullptr;
	}
}

} // namespace gdjl
