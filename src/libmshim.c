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
/* Returns a dlsym'd handle for the platform libm, or NULL when dynamic
 * loading is unavailable (e.g. statically-linked musl). Callers fall back
 * to the plain libc symbol in that case — parity with the C oracle is
 * degraded, but the program must not crash. */
static void *sym(const char *name) {
#if defined(__APPLE__)
    void *h = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY | RTLD_GLOBAL);
#else
    /* glibc/libm on Linux; RTLD_NOLOAD resolves the already-linked libm */
    void *h = dlopen("libm.so.6", RTLD_LAZY | RTLD_GLOBAL);
    if (h == NULL) h = dlopen(NULL, RTLD_LAZY | RTLD_GLOBAL);
#endif
    if (h == NULL) return NULL;
    return dlsym(h, name);
}

#define DEFINE_SHIM1(fn)                                            \
    double swe_shim_##fn(double x) {                                \
        static double (*f)(double);                                 \
        if (f == NULL) {                                            \
            void *p = sym(#fn);                                     \
            f = p ? (double (*)(double))p : &fn;                    \
        }                                                           \
        return f(x);                                                \
    }

#define DEFINE_SHIM2(fn)                                            \
    double swe_shim_##fn(double x, double y) {                      \
        static double (*f)(double, double);                         \
        if (f == NULL) {                                            \
            void *p = sym(#fn);                                     \
            f = p ? (double (*)(double, double))p : &fn;            \
        }                                                           \
        return f(x, y);                                             \
    }

DEFINE_SHIM1(sin)
DEFINE_SHIM1(cos)
DEFINE_SHIM1(tan)
DEFINE_SHIM1(asin)
DEFINE_SHIM1(acos)
DEFINE_SHIM1(atan)
DEFINE_SHIM2(atan2)
DEFINE_SHIM2(pow)
DEFINE_SHIM1(log10)
DEFINE_SHIM1(log)
DEFINE_SHIM1(exp)
DEFINE_SHIM2(fmod)
#endif
