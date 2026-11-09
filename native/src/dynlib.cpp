// Copyright 2026 Espen Harlinn
// SPDX-License-Identifier: Apache-2.0

#include "dynlib.h"

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace gdjl {

#ifdef _WIN32

void *dynlib_open(const std::string &p_utf8_path, std::string &r_error) {
	int wlen = MultiByteToWideChar(CP_UTF8, 0, p_utf8_path.c_str(), -1, nullptr, 0);
	std::wstring wpath(wlen, L'\0');
	MultiByteToWideChar(CP_UTF8, 0, p_utf8_path.c_str(), -1, wpath.data(), wlen);
	// Altered search path makes the DLL's own directory (Julia's bin/) resolve its dependencies.
	HMODULE handle = LoadLibraryExW(wpath.c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
	if (!handle) {
		r_error = "LoadLibraryExW failed with error " + std::to_string(GetLastError());
	}
	return reinterpret_cast<void *>(handle);
}

void *dynlib_symbol(void *p_handle, const char *p_name) {
	return reinterpret_cast<void *>(GetProcAddress(reinterpret_cast<HMODULE>(p_handle), p_name));
}

#else

void *dynlib_open(const std::string &p_utf8_path, std::string &r_error) {
	void *handle = dlopen(p_utf8_path.c_str(), RTLD_NOW | RTLD_GLOBAL);
	if (!handle) {
		const char *err = dlerror();
		r_error = err ? err : "dlopen failed";
	}
	return handle;
}

void *dynlib_symbol(void *p_handle, const char *p_name) {
	return dlsym(p_handle, p_name);
}

#endif

} // namespace gdjl
