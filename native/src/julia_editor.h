#pragma once

#include <godot_cpp/classes/editor_export_platform.hpp>
#include <godot_cpp/classes/editor_export_plugin.hpp>
#include <godot_cpp/classes/editor_plugin.hpp>
#include <godot_cpp/classes/editor_syntax_highlighter.hpp>
#include <godot_cpp/classes/script.hpp>
#include <godot_cpp/variant/color.hpp>

#include <vector>

namespace gdjl {

// Script editor highlighting for Julia (analog of GDScriptSyntaxHighlighter; extensions cannot use the engine's
// EditorStandardSyntaxHighlighter). Colors come from the editor's text_editor/theme/highlighting settings.
class JuliaSyntaxHighlighter : public godot::EditorSyntaxHighlighter {
	GDCLASS(JuliaSyntaxHighlighter, godot::EditorSyntaxHighlighter)

	struct Colors {
		godot::Color text, keyword, control_flow, comment, string, number, symbol, function, engine_type, user_type, macro;
	} colors;
	godot::PackedStringArray reserved_words;
	// Lexer state at the start of each line: 0 code, 1 inside #= =#, 2 inside a triple-quoted string.
	mutable std::vector<uint8_t> line_states;

	uint8_t scan(const godot::String &p_line, uint8_t p_state, godot::Dictionary *r_colors) const;
	uint8_t state_at(int32_t p_line) const;

protected:
	static void _bind_methods() {}

public:
	godot::String _get_name() const override;
	godot::PackedStringArray _get_supported_languages() const override;
	godot::Ref<godot::EditorSyntaxHighlighter> _create() const override;
	godot::Dictionary _get_line_syntax_highlighting(int32_t p_line) const override;
	void _clear_highlighting_cache() override;
	void _update_cache() override;
};

// Analog of GodotTools' ExportPlugin: compiles the Julia scripts into the export (GodotEditor.Tools does the work).
class JuliaExportPlugin : public godot::EditorExportPlugin {
	GDCLASS(JuliaExportPlugin, godot::EditorExportPlugin)

protected:
	static void _bind_methods() {}

public:
	godot::String _get_name() const override;
	bool _supports_platform(const godot::Ref<godot::EditorExportPlatform> &p_platform) const override;
	godot::TypedArray<godot::Dictionary> _get_export_options(const godot::Ref<godot::EditorExportPlatform> &p_platform) const override;
	void _export_begin(const godot::PackedStringArray &p_features, bool p_is_debug, const godot::String &p_path, uint32_t p_flags) override;
	void _export_file(const godot::String &p_path, const godot::String &p_type, const godot::PackedStringArray &p_features) override;
	void _export_end() override;
};

// Analog of GodotSharpEditor's plugin: a native EditorPlugin added automatically in the editor that forwards its
// lifecycle to the Julia editor tools (GodotEditor.Tools), which build the Julia panel, menus and Build button.
class JuliaEditorPlugin : public godot::EditorPlugin {
	GDCLASS(JuliaEditorPlugin, godot::EditorPlugin)

	godot::Ref<JuliaSyntaxHighlighter> highlighter;
	godot::Ref<JuliaExportPlugin> export_plugin;

	void _on_editor_script_changed(const godot::Ref<godot::Script> &p_script);

protected:
	static void _bind_methods();

public:
	void register_syntax_highlighter();
	godot::String _get_plugin_name() const override;
	void _enter_tree() override;
	void _exit_tree() override;
	void _process(double p_delta) override;
	bool _build() override;
};

void register_editor_types();

} // namespace gdjl
