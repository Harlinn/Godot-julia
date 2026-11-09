// Copyright 2026 Espen Harlinn
// SPDX-License-Identifier: Apache-2.0

#include "julia_editor.h"

#include "julia_host.h"
#include "julia_script.h"

#include <godot_cpp/classes/class_db_singleton.hpp>
#include <godot_cpp/classes/code_edit.hpp>
#include <godot_cpp/classes/editor_export_platform.hpp>
#include <godot_cpp/classes/editor_interface.hpp>
#include <godot_cpp/classes/editor_plugin_registration.hpp>
#include <godot_cpp/classes/editor_settings.hpp>
#include <godot_cpp/classes/script_editor.hpp>
#include <godot_cpp/classes/script_editor_base.hpp>
#include <godot_cpp/classes/text_edit.hpp>
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

namespace gdjl {

namespace {

Variant call_tools(const char *p_method, const Object *p_self, const Variant &p_arg = Variant()) {
	const Variant *ptrs[1] = { &p_arg };
	Variant ret;
	JuliaHost::get_singleton().script_call(p_method, p_self->_owner, ptrs, p_arg.get_type() == Variant::NIL ? 0 : 1, ret);
	return ret;
}

bool is_ident_start(char32_t c) {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c > 127;
}

bool is_ident_char(char32_t c) {
	return is_ident_start(c) || (c >= '0' && c <= '9') || c == '!';
}

bool is_digit(char32_t c) {
	return c >= '0' && c <= '9';
}

} // namespace

// --- JuliaSyntaxHighlighter ---------------------------------------------------------------------------------------

String JuliaSyntaxHighlighter::_get_name() const {
	return "Julia";
}

PackedStringArray JuliaSyntaxHighlighter::_get_supported_languages() const {
	PackedStringArray r;
	r.push_back("Julia");
	return r;
}

Ref<EditorSyntaxHighlighter> JuliaSyntaxHighlighter::_create() const {
	Ref<JuliaSyntaxHighlighter> h;
	h.instantiate();
	return h;
}

void JuliaSyntaxHighlighter::_clear_highlighting_cache() {
	line_states.clear();
}

void JuliaSyntaxHighlighter::_update_cache() {
	line_states.clear();
	if (JuliaLanguage *language = JuliaLanguage::get_singleton()) {
		reserved_words = language->_get_reserved_words();
	}
	EditorInterface *ei = EditorInterface::get_singleton();
	Ref<EditorSettings> es = ei ? ei->get_editor_settings() : Ref<EditorSettings>();
	auto get = [&](const char *p_name, const Color &p_default) {
		String key = String("text_editor/theme/highlighting/") + p_name;
		return es.is_valid() && es->has_setting(key) ? Color(es->get_setting(key)) : p_default;
	};
	colors.text = get("text_color", Color(0.8, 0.8, 0.8));
	colors.keyword = get("keyword_color", Color(1.0, 0.44, 0.52));
	colors.control_flow = get("control_flow_keyword_color", Color(1.0, 0.55, 0.8));
	colors.comment = get("comment_color", Color(0.8, 0.8, 0.8, 0.5));
	colors.string = get("string_color", Color(1.0, 0.93, 0.63));
	colors.number = get("number_color", Color(0.63, 1.0, 0.88));
	colors.symbol = get("symbol_color", Color(0.67, 0.79, 1.0));
	colors.function = get("function_color", Color(0.34, 0.7, 1.0));
	colors.engine_type = get("engine_type_color", Color(0.56, 1.0, 0.86));
	colors.user_type = get("user_type_color", Color(0.78, 1.0, 0.86));
	colors.macro = get("gdscript/annotation_color", Color(1.0, 0.7, 0.45));
}

uint8_t JuliaSyntaxHighlighter::scan(const String &p_line, uint8_t p_state, Dictionary *r_colors) const {
	const int n = p_line.length();
	auto mark = [&](int p_col, const Color &p_color) {
		if (r_colors && p_col < n) {
			Dictionary d;
			d["color"] = p_color;
			(*r_colors)[p_col] = d;
		}
	};
	int i = 0;
	if (p_state == 1 || p_state == 2) {
		const char *close = p_state == 1 ? "=#" : "\"\"\"";
		int end = p_line.find(close);
		mark(0, p_state == 1 ? colors.comment : colors.string);
		if (end < 0) {
			return p_state;
		}
		i = end + (p_state == 1 ? 2 : 3);
		mark(i, colors.text);
	}
	JuliaLanguage *language = JuliaLanguage::get_singleton();
	while (i < n) {
		const char32_t c = p_line[i];
		if (c == '#') {
			mark(i, colors.comment);
			if (i + 1 < n && p_line[i + 1] == '=') {
				int end = p_line.find("=#", i + 2);
				if (end < 0) {
					return 1;
				}
				i = end + 2;
				mark(i, colors.text);
				continue;
			}
			return 0;
		}
		if (c == '"' || c == '`') {
			mark(i, colors.string);
			if (c == '"' && p_line.substr(i, 3) == "\"\"\"") {
				int end = p_line.find("\"\"\"", i + 3);
				if (end < 0) {
					return 2;
				}
				i = end + 3;
			} else {
				int j = i + 1;
				while (j < n && p_line[j] != c) {
					j += p_line[j] == '\\' ? 2 : 1;
				}
				i = j + 1;
			}
			mark(i, colors.text);
			continue;
		}
		if (c == '\'') {
			// A quote after a value is the adjoint operator, otherwise a character literal.
			char32_t prev = i > 0 ? p_line[i - 1] : ' ';
			if (!(is_ident_char(prev) || prev == ')' || prev == ']' || prev == '}' || prev == '\'')) {
				int j = i + 1;
				while (j < n && p_line[j] != '\'') {
					j += p_line[j] == '\\' ? 2 : 1;
				}
				mark(i, colors.string);
				i = j + 1;
				mark(i, colors.text);
				continue;
			}
		}
		if (is_digit(c) && (i == 0 || !is_ident_char(p_line[i - 1]))) {
			int j = i + 1;
			while (j < n && (is_ident_char(p_line[j]) || p_line[j] == '.')) {
				j++;
			}
			mark(i, colors.number);
			i = j;
			mark(i, colors.text);
			continue;
		}
		if (c == '@' && i + 1 < n && is_ident_start(p_line[i + 1])) {
			int j = i + 1;
			while (j < n && (is_ident_char(p_line[j]) || p_line[j] == '.')) {
				j++;
			}
			mark(i, colors.macro);
			i = j;
			mark(i, colors.text);
			continue;
		}
		if (is_ident_start(c)) {
			int j = i + 1;
			while (j < n && is_ident_char(p_line[j])) {
				j++;
			}
			String word = p_line.substr(i, j - i);
			int k = j;
			while (k < n && p_line[k] == ' ') {
				k++;
			}
			Color color = colors.text;
			if (reserved_words.has(word)) {
				color = language && language->_is_control_flow_keyword(word) ? colors.control_flow : colors.keyword;
			} else if (k < n && p_line[k] == '(') {
				color = colors.function;
			} else if (c >= 'A' && c <= 'Z') {
				color = ClassDBSingleton::get_singleton()->class_exists(word) ? colors.engine_type : colors.user_type;
			}
			mark(i, color);
			i = j;
			mark(i, colors.text);
			continue;
		}
		if (c != ' ' && c != '\t') {
			mark(i, colors.symbol);
			mark(i + 1, colors.text);
		}
		i++;
	}
	return 0;
}

uint8_t JuliaSyntaxHighlighter::state_at(int32_t p_line) const {
	TextEdit *te = get_text_edit();
	if (!te || p_line <= 0) {
		return 0;
	}
	if (line_states.empty()) {
		line_states.push_back(0);
	}
	while (int32_t(line_states.size()) <= p_line) {
		int32_t l = int32_t(line_states.size()) - 1;
		line_states.push_back(scan(te->get_line(l), line_states[l], nullptr));
	}
	return line_states[p_line];
}

Dictionary JuliaSyntaxHighlighter::_get_line_syntax_highlighting(int32_t p_line) const {
	Dictionary r;
	TextEdit *te = get_text_edit();
	if (!te || p_line < 0 || p_line >= te->get_line_count()) {
		return r;
	}
	scan(te->get_line(p_line), state_at(p_line), &r);
	return r;
}

// --- JuliaExportPlugin --------------------------------------------------------------------------------------------

String JuliaExportPlugin::_get_name() const {
	return "Julia";
}

bool JuliaExportPlugin::_supports_platform(const Ref<EditorExportPlatform> &p_platform) const {
	return true;
}

static Dictionary export_option(const String &p_name, Variant::Type p_type, const Variant &p_default, PropertyHint p_hint = PROPERTY_HINT_NONE, const String &p_hint_string = "") {
	Dictionary info;
	info["name"] = p_name;
	info["type"] = p_type;
	info["hint"] = p_hint;
	info["hint_string"] = p_hint_string;
	Dictionary option;
	option["option"] = info;
	option["default_value"] = p_default;
	return option;
}

TypedArray<Dictionary> JuliaExportPlugin::_get_export_options(const Ref<EditorExportPlatform> &p_platform) const {
	TypedArray<Dictionary> options;
	options.push_back(export_option("julia/export/mode", Variant::STRING, "sysimage", PROPERTY_HINT_ENUM, "sysimage,jit"));
	options.push_back(export_option("julia/export/include_sources", Variant::BOOL, false));
	options.push_back(export_option("julia/export/include_debug_symbols", Variant::BOOL, false));
	return options;
}

void JuliaExportPlugin::_export_begin(const PackedStringArray &p_features, bool p_is_debug, const String &p_path, uint32_t p_flags) {
	Dictionary args;
	args["features"] = p_features;
	args["is_debug"] = p_is_debug;
	args["path"] = p_path;
	call_tools("export_begin", this, args);
}

void JuliaExportPlugin::_export_file(const String &p_path, const String &p_type, const PackedStringArray &p_features) {
	if (p_path.ends_with(".jl")) {
		call_tools("export_file", this, p_path);
	}
}

void JuliaExportPlugin::_export_end() {
	call_tools("export_end", this);
}

// --- JuliaTranslationParserPlugin ---------------------------------------------------------------------------------

TypedArray<PackedStringArray> JuliaTranslationParserPlugin::_parse_file(const String &p_path) {
	TypedArray<PackedStringArray> r;
	if (!JuliaHost::get_singleton().is_ready()) {
		return r;
	}
	Variant v = call_tools("translation_parse_file", this, p_path);
	if (v.get_type() == Variant::ARRAY) {
		Array a = v;
		for (int64_t i = 0; i < a.size(); i++) {
			r.push_back(PackedStringArray(a[i]));
		}
	}
	return r;
}

PackedStringArray JuliaTranslationParserPlugin::_get_recognized_extensions() const {
	PackedStringArray r;
	r.push_back("jl");
	return r;
}

// --- JuliaEditorPlugin --------------------------------------------------------------------------------------------

void JuliaEditorPlugin::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_syntax_highlighter"), &JuliaEditorPlugin::register_syntax_highlighter);
}

// Called by the Julia tools once the editor is ready (ScriptEditor exists).
void JuliaEditorPlugin::register_syntax_highlighter() {
	EditorInterface *ei = EditorInterface::get_singleton();
	ScriptEditor *se = ei ? ei->get_script_editor() : nullptr;
	if (!se || highlighter.is_valid()) {
		return;
	}
	highlighter.instantiate();
	se->register_syntax_highlighter(highlighter);
	// Tabs restored from the previous session are created before plugins can register highlighters, so a Julia tab
	// gets the highlighter when it becomes current.
	se->connect("editor_script_changed", callable_mp(this, &JuliaEditorPlugin::_on_editor_script_changed));
	_on_editor_script_changed(se->get_current_script());
}

void JuliaEditorPlugin::_on_editor_script_changed(const Ref<Script> &p_script) {
	ScriptEditor *se = EditorInterface::get_singleton()->get_script_editor();
	if (!se || p_script.is_null() || !p_script->get_path().ends_with(".jl") || highlighter.is_null()) {
		return;
	}
	ScriptEditorBase *seb = se->get_current_editor();
	CodeEdit *code = seb ? Object::cast_to<CodeEdit>(seb->get_base_editor()) : nullptr;
	if (!code || Object::cast_to<JuliaSyntaxHighlighter>(code->get_syntax_highlighter().ptr())) {
		return;
	}
	Ref<EditorSyntaxHighlighter> h = highlighter->_create();
	seb->add_syntax_highlighter(h);
	code->set_syntax_highlighter(h);
}

String JuliaEditorPlugin::_get_plugin_name() const {
	return "Julia";
}

void JuliaEditorPlugin::_enter_tree() {
	set_process(false);
	// Before the editor restores the previous session's script tabs, which only get highlighters registered by then.
	register_syntax_highlighter();
	if (JuliaHost::get_singleton().is_ready()) {
		export_plugin.instantiate();
		add_export_plugin(export_plugin);
		translation_parser.instantiate();
		add_translation_parser_plugin(translation_parser);
		call_tools("editor_plugin_enter_tree", this);
	}
}

void JuliaEditorPlugin::_exit_tree() {
	if (highlighter.is_valid()) {
		ScriptEditor *se = EditorInterface::get_singleton()->get_script_editor();
		if (se) {
			se->disconnect("editor_script_changed", callable_mp(this, &JuliaEditorPlugin::_on_editor_script_changed));
			se->unregister_syntax_highlighter(highlighter);
		}
		highlighter.unref();
	}
	if (export_plugin.is_valid()) {
		remove_export_plugin(export_plugin);
		export_plugin.unref();
	}
	if (translation_parser.is_valid()) {
		remove_translation_parser_plugin(translation_parser);
		translation_parser.unref();
	}
	if (JuliaHost::get_singleton().is_ready()) {
		call_tools("editor_plugin_exit_tree", this);
	}
}

void JuliaEditorPlugin::_process(double p_delta) {
	call_tools("editor_plugin_process", this, p_delta);
}

bool JuliaEditorPlugin::_build() {
	if (!JuliaHost::get_singleton().is_ready()) {
		return true;
	}
	Variant ok = call_tools("editor_plugin_build", this);
	return ok.get_type() != Variant::BOOL || bool(ok);
}

void register_editor_types() {
	GDREGISTER_CLASS(JuliaSyntaxHighlighter);
	GDREGISTER_INTERNAL_CLASS(JuliaExportPlugin);
	GDREGISTER_INTERNAL_CLASS(JuliaTranslationParserPlugin);
	GDREGISTER_INTERNAL_CLASS(JuliaEditorPlugin);
	EditorPlugins::add_by_type<JuliaEditorPlugin>();
}

} // namespace gdjl
