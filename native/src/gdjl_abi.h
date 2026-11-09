// Copyright 2026 Espen Harlinn
// SPDX-License-Identifier: Apache-2.0

#pragma once

// Function tables exchanged between the native host and `Godot.Runtime`; mirrored in julia/Godot/src/runtime/abi.jl.

#include <cstdint>

#define GDJL_ABI_VERSION 5

enum GDJLPrintKind : int32_t {
	GDJL_PRINT_STDOUT = 0,
	GDJL_PRINT_STDERR = 1,
};

// Julia callbacks that Godot may call directly from any thread (custom Callables, script instances, instance
// bindings). Julia hands them to the host, which returns a trampoline with the same signature that adopts the thread
// and parks it GC-safe afterwards (Julia's @cfunction wrappers would leave a newly adopted thread GC-unsafe and stall
// every later collection). X(id, return type, argument types...); the order defines the ids used by Julia.
#define GDJL_CALLBACKS(X)                                                                \
	X(CALLABLE_CALL, void, void *, const void *const *, int64_t, void *, void *)         \
	X(CALLABLE_FREE, void, void *)                                                       \
	X(CALLABLE_HASH, uint32_t, void *)                                                   \
	X(CALLABLE_EQUAL, uint8_t, void *, void *)                                           \
	X(CALLABLE_LESS, uint8_t, void *, void *)                                            \
	X(CALLABLE_TO_STRING, void, void *, uint8_t *, void *)                               \
	X(CALLABLE_ARGCOUNT, int64_t, void *, uint8_t *)                                     \
	X(BINDING_CREATE, void *, void *, void *)                                            \
	X(BINDING_FREE, void, void *, void *, void *)                                        \
	X(BINDING_REFERENCE, uint8_t, void *, void *, uint8_t)                               \
	X(INST_SET, uint8_t, void *, const void *, const void *)                             \
	X(INST_GET, uint8_t, void *, const void *, void *)                                   \
	X(INST_GET_PROPERTY_LIST, const void *, void *, uint32_t *)                          \
	X(INST_FREE_PROPERTY_LIST, void, void *, const void *, uint32_t)                     \
	X(INST_PROPERTY_CAN_REVERT, uint8_t, void *, const void *)                           \
	X(INST_PROPERTY_GET_REVERT, uint8_t, void *, const void *, void *)                   \
	X(INST_GET_OWNER, void *, void *)                                                    \
	X(INST_GET_PROPERTY_STATE, void, void *, void *, void *)                             \
	X(INST_GET_METHOD_LIST, const void *, void *, uint32_t *)                            \
	X(INST_FREE_METHOD_LIST, void, void *, const void *, uint32_t)                       \
	X(INST_GET_PROPERTY_TYPE, int32_t, void *, const void *, uint8_t *)                  \
	X(INST_VALIDATE_PROPERTY, uint8_t, void *, void *)                                   \
	X(INST_HAS_METHOD, uint8_t, void *, const void *)                                    \
	X(INST_GET_METHOD_ARGUMENT_COUNT, int64_t, void *, const void *, uint8_t *)          \
	X(INST_CALL, void, void *, const void *, const void *const *, int64_t, void *, void *) \
	X(INST_NOTIFICATION, void, void *, int32_t, uint8_t)                                 \
	X(INST_TO_STRING, void, void *, uint8_t *, void *)                                   \
	X(INST_REFCOUNT_INCREMENTED, void, void *)                                           \
	X(INST_REFCOUNT_DECREMENTED, uint8_t, void *)                                        \
	X(INST_GET_SCRIPT, void *, void *)                                                   \
	X(INST_IS_PLACEHOLDER, uint8_t, void *)                                              \
	X(INST_GET_LANGUAGE, void *, void *)                                                 \
	X(INST_FREE, void, void *)

#define GDJL_CALLBACK_ID(m_id, ...) GDJL_CB_##m_id,
enum GDJLCallbackId : int32_t {
	GDJL_CALLBACKS(GDJL_CALLBACK_ID)
		GDJL_CB_COUNT
};
#undef GDJL_CALLBACK_ID

struct GDJLHostAPI {
	uint32_t abi_version;
	uint32_t size;
	uint32_t real_t_size;
	uint32_t reserved;
	void (*print)(int32_t kind, const char *utf8, int64_t len);
	void (*report_error)(int32_t is_warning, const char *function, const char *file, int32_t line, const char *utf8, int64_t len);
	void (*string_out)(void *ctx, const char *utf8, int64_t len);
	// Returns a thread-guarded trampoline for Julia callback `julia_fn` of kind `id` (GDJLCallbackId).
	void *(*guard_callback)(int32_t id, void *julia_fn);
	// Script error/warning (Godot's print_script_error_with_message): shown as a script error with clickable source.
	void (*report_script_error)(int32_t is_warning, const char *function, const char *file, int32_t line, const char *description, const char *message);
};

struct GDJLJuliaAPI {
	uint32_t abi_version;
	uint32_t size;
	int32_t (*eval_string)(const char *utf8, int64_t len, void *ctx);
	void (*shutdown)(void);
	// Script bridge (ScriptManagerBridge analog): `args` are argc `const Variant *`, `r_ret` an initialized nil Variant.
	void (*script_call)(const char *method, void *self, const void *const *args, int64_t argc, void *r_ret);
};
