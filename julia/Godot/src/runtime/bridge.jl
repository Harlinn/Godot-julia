# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# The script bridge entry point (analog of ScriptManagerBridge): JuliaLanguage / JuliaScript (native/src/julia_script.cpp)
# call `script_call(method, self, args, argc, r_ret)`, dispatched here by method name.

const BRIDGE = Dict{Symbol, Function}(
    :language_init => language_init,
    :language_finish => language_finish,
    :language_frame => language_frame,
    :language_reload_scripts => language_reload_scripts,
    :language_reload_all_scripts => language_reload_all_scripts,
    :language_reload_tool_script => language_reload_tool_script,
    :validate => language_validate,
    :get_global_class_name => language_get_global_class_name,
    :make_template => language_make_template,
    :get_built_in_templates => language_get_built_in_templates,
    :find_function => language_find_function,
    :make_function => language_make_function,
    :validate_path => language_validate_path,
    :overrides_external_editor => language_overrides_external_editor,
    :open_in_external_editor => language_open_in_external_editor,
    :script_reload => script_reload,
    :script_free => script_free,
    :script_can_instantiate => script_can_instantiate,
    :script_get_base_script => script_get_base_script,
    :script_get_global_name => script_get_global_name,
    :script_get_instance_base_type => script_get_instance_base_type,
    :script_instance_create => script_instance_create,
    :script_placeholder_create => script_placeholder_create,
    :script_placeholder_erased => script_placeholder_erased,
    :script_instance_has => script_instance_has,
    :script_get_icon_path => script_get_icon_path,
    :script_has_method => script_has_method,
    :script_get_method_argument_count => script_get_method_argument_count,
    :script_get_method_info => script_get_method_info,
    :script_is_tool => script_is_tool,
    :script_is_valid => script_is_valid,
    :script_is_abstract => script_is_abstract,
    :script_has_signal => script_has_signal,
    :script_get_signal_list => script_get_signal_list,
    :script_has_property_default => script_has_property_default,
    :script_get_property_default => script_get_property_default,
    :script_update_exports => script_update_exports,
    :script_get_method_list => script_get_method_list,
    :script_get_property_list => script_get_property_list,
    :script_get_member_line => script_get_member_line,
    :script_get_members => script_get_members,
    :script_has_static_method => script_has_static_method,
    :script_call_static => script_call_static,
    :script_get_rpc_config => script_get_rpc_config,
    :debug_get_current_stack_info => debug_get_current_stack_info,
    :debug_get_error => debug_get_error,
    :debug_get_stack_level_count => debug_get_stack_level_count,
    :debug_get_stack_level_line => debug_get_stack_level_line,
    :debug_get_stack_level_function => debug_get_stack_level_function,
    :debug_get_stack_level_source => debug_get_stack_level_source,
    :debug_get_stack_level_locals => debug_get_stack_level_locals,
    :debug_get_stack_level_members => debug_get_stack_level_members,
    :debug_get_globals => debug_get_globals,
    :debug_parse_stack_level_expression => debug_parse_stack_level_expression,
)

# The native side passes string literals, so their addresses identify the handler.
const BRIDGE_NAMES = Dict{Ptr{UInt8}, Symbol}()
const BRIDGE_NAMES_LOCK = ReentrantLock()

bridge_name(method::Ptr{UInt8}) =
    @lock BRIDGE_NAMES_LOCK get!(() -> Symbol(unsafe_string(method)), BRIDGE_NAMES, method)

function _script_call(method::Ptr{UInt8}, self::Ptr{Cvoid}, args::Ptr{Ptr{Cvoid}}, argc::Int64, ret::Ptr{Cvoid})::Cvoid
    @godot_entry nothing begin
        handler = BRIDGE[bridge_name(method)]
        xs = Any[Internals.from_variant(unsafe_load(Ptr{FFI.RawVariant}(unsafe_load(args, i)))) for i in 1:argc]
        result = Base.invokelatest(handler, self, xs...)
        result === nothing || Internals.assign_variant_slot!(ret, result)
        nothing
    end
end
