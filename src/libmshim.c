// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
/* libm shim: guarantees the port calls the platform C library's math
 * routines (same implementations the C oracle links). Zig's compiler_rt
 * statically shadows plain "sin"/"cos"/"tan"/"fmod" symbols, so we resolve
 * the platform implementations explicitly via dlsym on libSystem.
 * Windows has no dlopen: msvcrt is the platform libm and is linked into
 * every C process, so resolve those symbols directly. */
#include <math.h>
#include <stdlib.h>
#if !defined(_WIN32)
#include <dlfcn.h>
#endif

#if defined(_WIN32)
#define SHIM_RESOLVE(name) name
#else
static void *libm_handle(void) {
    static void *h;
    if (h == NULL) {
#if defined(__APPLE__)
        h = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY | RTLD_GLOBAL);
#else
        /* glibc/libm on Linux; RTLD_NOLOAD resolves the already-linked libm */
        h = dlopen("libm.so.6", RTLD_LAZY | RTLD_GLOBAL);
        if (h == NULL) h = dlopen(NULL, RTLD_LAZY | RTLD_GLOBAL);
#endif
        if (h == NULL) abort();
    }
    return h;
}

static void *sym(const char *name) {
    void *p = dlsym(libm_handle(), name);
    if (p == NULL) abort();
    return p;
}
#define SHIM_RESOLVE(name) sym(#name)
#endif

double swe_shim_sin(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))SHIM_RESOLVE(sin);
    return f(x);
}

double swe_shim_cos(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))SHIM_RESOLVE(cos);
    return f(x);
}

double swe_shim_tan(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))SHIM_RESOLVE(tan);
    return f(x);
}

double swe_shim_asin(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))SHIM_RESOLVE(asin);
    return f(x);
}

double swe_shim_acos(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))SHIM_RESOLVE(acos);
    return f(x);
}

double swe_shim_atan(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))SHIM_RESOLVE(atan);
    return f(x);
}

double swe_shim_atan2(double y, double x) {
    static double (*f)(double, double);
    if (f == NULL) f = (double (*)(double, double))SHIM_RESOLVE(atan2);
    return f(y, x);
}

double swe_shim_pow(double x, double y) {
    static double (*f)(double, double);
    if (f == NULL) f = (double (*)(double, double))SHIM_RESOLVE(pow);
    return f(x, y);
}

double swe_shim_log10(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))SHIM_RESOLVE(log10);
    return f(x);
}

double swe_shim_log(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))SHIM_RESOLVE(log);
    return f(x);
}

double swe_shim_exp(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))SHIM_RESOLVE(exp);
    return f(x);
}

double swe_shim_fmod(double x, double y) {
    static double (*f)(double, double);
    if (f == NULL) f = (double (*)(double, double))SHIM_RESOLVE(fmod);
    return f(x, y);
}
