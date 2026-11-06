#pragma once

// Julia script language shims (analog of modules/mono/csharp_script.h). Static language data lives here; everything
// else forwards to Godot.Runtime's script bridge (julia/Godot/src/runtime/scripts.jl) through JuliaHost::script_call.

#include <godot_cpp/classes/resource_format_loader.hpp>
#include <godot_cpp/classes/resource_format_saver.hpp>
#include <godot_cpp/classes/script_extension.hpp>
#include <godot_cpp/classes/script_language_extension.hpp>
#include <godot_cpp/variant/typed_array.hpp>

namespace gdjl {

class JuliaLanguage : public godot::ScriptLanguageExtension {
	GDCLASS(JuliaLanguage, godot::ScriptLanguageExtension)

	static JuliaLanguage *singleton;

protected:
	static void _bind_methods() {}

public:
	static JuliaLanguage *get_singleton() { return singleton; }

	JuliaLanguage();
	~JuliaLanguage();

	godot::String _get_name() const override;
	void _init() override;
	godot::String _get_type() const override;
	godot::String _get_extension() const override;
	void _finish() override;
	godot::PackedStringArray _get_reserved_words() const override;
	bool _is_control_flow_keyword(const godot::String &p_keyword) const override;
	godot::PackedStringArray _get_comment_delimiters() const override;
	godot::PackedStringArray _get_doc_comment_delimiters() const override;
	godot::PackedStringArray _get_string_delimiters() const override;
	godot::Ref<godot::Script> _make_template(const godot::String &p_template, const godot::String &p_class_name, const godot::String &p_base_class_name) const override;
	godot::TypedArray<godot::Dictionary> _get_built_in_templates(const godot::StringName &p_object) const override;
	bool _is_using_templates() override;
	godot::Dictionary _validate(const godot::String &p_script, const godot::String &p_path, bool p_validate_functions, bool p_validate_errors, bool p_validate_warnings, bool p_validate_safe_lines) const override;
	godot::String _validate_path(const godot::String &p_path) const override;
	godot::Object *_create_script() const override;
	bool _has_named_classes() const override;
	bool _supports_builtin_mode() const override;
	bool _supports_documentation() const override;
	bool _can_inherit_from_file() const override;
	int32_t _find_function(const godot::String &p_function, const godot::String &p_code) const override;
	godot::String _make_function(const godot::String &p_class_name, const godot::String &p_function_name, const godot::PackedStringArray &p_function_args) const override;
	bool _can_make_function() const override;
	godot::Error _open_in_external_editor(const godot::Ref<godot::Script> &p_script, int32_t p_line, int32_t p_column) override;
	bool _overrides_external_editor() override;
	godot::ScriptLanguage::ScriptNameCasing _preferred_file_name_casing() const override;
	godot::Dictionary _complete_code(const godot::String &p_code, const godot::String &p_path, godot::Object *p_owner) const override;
	godot::Dictionary _lookup_code(const godot::String &p_code, const godot::String &p_symbol, const godot::String &p_path, godot::Object *p_owner) const override;
	godot::String _auto_indent_code(const godot::String &p_code, int32_t p_from_line, int32_t p_to_line) const override;
	void _add_global_constant(const godot::StringName &p_name, const godot::Variant &p_value) override;
	void _add_named_global_constant(const godot::StringName &p_name, const godot::Variant &p_value) override;
	void _remove_named_global_constant(const godot::StringName &p_name) override;
	void _thread_enter() override;
	void _thread_exit() override;
	godot::String _debug_get_error() const override;
	int32_t _debug_get_stack_level_count() const override;
	int32_t _debug_get_stack_level_line(int32_t p_level) const override;
	godot::String _debug_get_stack_level_function(int32_t p_level) const override;
	godot::String _debug_get_stack_level_source(int32_t p_level) const override;
	godot::Dictionary _debug_get_stack_level_locals(int32_t p_level, int32_t p_max_subitems, int32_t p_max_depth) override;
	godot::Dictionary _debug_get_stack_level_members(int32_t p_level, int32_t p_max_subitems, int32_t p_max_depth) override;
	void *_debug_get_stack_level_instance(int32_t p_level) override;
	godot::Dictionary _debug_get_globals(int32_t p_max_subitems, int32_t p_max_depth) override;
	godot::String _debug_parse_stack_level_expression(int32_t p_level, const godot::String &p_expression, int32_t p_max_subitems, int32_t p_max_depth) override;
	godot::TypedArray<godot::Dictionary> _debug_get_current_stack_info() override;
	void _reload_all_scripts() override;
	void _reload_scripts(const godot::Array &p_scripts, bool p_soft_reload) override;
	void _reload_tool_script(const godot::Ref<godot::Script> &p_script, bool p_soft_reload) override;
	godot::PackedStringArray _get_recognized_extensions() const override;
	godot::TypedArray<godot::Dictionary> _get_public_functions() const override;
	godot::Dictionary _get_public_constants() const override;
	godot::TypedArray<godot::Dictionary> _get_public_annotations() const override;
	void _profiling_start() override;
	void _profiling_stop() override;
	void _profiling_set_save_native_calls(bool p_enable) override;
	int32_t _profiling_get_accumulated_data(godot::ScriptLanguageExtensionProfilingInfo *p_info_array, int32_t p_info_max) override;
	int32_t _profiling_get_frame_data(godot::ScriptLanguageExtensionProfilingInfo *p_info_array, int32_t p_info_max) override;
	void _frame() override;
	bool _handles_global_class_type(const godot::String &p_type) const override;
	godot::Dictionary _get_global_class_name(const godot::String &p_path) const override;
};

class JuliaScript : public godot::ScriptExtension {
	GDCLASS(JuliaScript, godot::ScriptExtension)

	godot::String source_code;
	// Path the script was loaded from; the resource path is assigned by ResourceLoader only after loading.
	godot::String load_path;

protected:
	static void _bind_methods();

public:
	~JuliaScript();

	// Calls static script method `method` (GDExtension scripts cannot intercept `Script.method()` calls).
	godot::Variant call_static(const godot::Variant **p_args, GDExtensionInt p_arg_count, GDExtensionCallError &r_error);

	void set_load_path(const godot::String &p_path) { load_path = p_path; }
	godot::String get_script_path() const;

	bool _editor_can_reload_from_file() override;
	void _placeholder_erased(void *p_placeholder) override;
	bool _can_instantiate() const override;
	godot::Ref<godot::Script> _get_base_script() const override;
	godot::StringName _get_global_name() const override;
	bool _inherits_script(const godot::Ref<godot::Script> &p_script) const override;
	godot::StringName _get_instance_base_type() const override;
	void *_instance_create(godot::Object *p_for_object) const override;
	void *_placeholder_instance_create(godot::Object *p_for_object) const override;
	bool _has_source_code() const override;
	godot::String _get_source_code() const override;
	void _set_source_code(const godot::String &p_code) override;
	godot::Error _reload(bool p_keep_state) override;
	godot::StringName _get_doc_class_name() const override;
	godot::TypedArray<godot::Dictionary> _get_documentation() const override;
	godot::String _get_class_icon_path() const override;
	bool _has_method(const godot::StringName &p_method) const override;
	bool _has_static_method(const godot::StringName &p_method) const override;
	godot::Variant _get_script_method_argument_count(const godot::StringName &p_method) const override;
	godot::Dictionary _get_method_info(const godot::StringName &p_method) const override;
	bool _is_tool() const override;
	bool _is_valid() const override;
	bool _is_abstract() const override;
	godot::ScriptLanguage *_get_language() const override;
	bool _has_script_signal(const godot::StringName &p_signal) const override;
	godot::TypedArray<godot::Dictionary> _get_script_signal_list() const override;
	bool _has_property_default_value(const godot::StringName &p_property) const override;
	godot::Variant _get_property_default_value(const godot::StringName &p_property) const override;
	void _update_exports() override;
	godot::TypedArray<godot::Dictionary> _get_script_method_list() const override;
	godot::TypedArray<godot::Dictionary> _get_script_property_list() const override;
	int32_t _get_member_line(const godot::StringName &p_member) const override;
	godot::Dictionary _get_constants() const override;
	godot::TypedArray<godot::StringName> _get_members() const override;
	bool _is_placeholder_fallback_enabled() const override;
	godot::Variant _get_rpc_config() const override;
	bool _instance_has(godot::Object *p_object) const override;
};

class ResourceFormatLoaderJulia : public godot::ResourceFormatLoader {
	GDCLASS(ResourceFormatLoaderJulia, godot::ResourceFormatLoader)

protected:
	static void _bind_methods() {}

public:
	godot::PackedStringArray _get_recognized_extensions() const override;
	bool _handles_type(const godot::StringName &p_type) const override;
	godot::String _get_resource_type(const godot::String &p_path) const override;
	godot::Variant _load(const godot::String &p_path, const godot::String &p_original_path, bool p_use_sub_threads, int32_t p_cache_mode) const override;
};

class ResourceFormatSaverJulia : public godot::ResourceFormatSaver {
	GDCLASS(ResourceFormatSaverJulia, godot::ResourceFormatSaver)

protected:
	static void _bind_methods() {}

public:
	godot::Error _save(const godot::Ref<godot::Resource> &p_resource, const godot::String &p_path, uint32_t p_flags) override;
	bool _recognize(const godot::Ref<godot::Resource> &p_resource) const override;
	godot::PackedStringArray _get_recognized_extensions(const godot::Ref<godot::Resource> &p_resource) const override;
};

// Registers the classes, the language and the resource loader/saver (SCENE level, after JuliaHost::initialize).
void register_script_language();
void unregister_script_language();

} // namespace gdjl
