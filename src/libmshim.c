// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
/* libm shim: guarantees the port calls the platform C library's math
 * routines (same implementations the C oracle links). Zig's compiler_rt
 * statically shadows plain "sin"/"cos"/"tan"/"fmod" symbols, so we resolve
 * the platform implementations explicitly via dlsym on libSystem. */
#include <math.h>
#include <dlfcn.h>
#include <stdlib.h>

static void *libm_handle(void) {
    static void *h;
    if (h == NULL) {
        h = dlopen("/usr/lib/libSystem.B.dylib", RTLD_LAZY | RTLD_GLOBAL);
        if (h == NULL) abort();
    }
    return h;
}

static void *sym(const char *name) {
    void *p = dlsym(libm_handle(), name);
    if (p == NULL) abort();
    return p;
}

double swe_shim_sin(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))sym("sin");
    return f(x);
}

double swe_shim_cos(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))sym("cos");
    return f(x);
}

double swe_shim_tan(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))sym("tan");
    return f(x);
}

double swe_shim_asin(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))sym("asin");
    return f(x);
}

double swe_shim_acos(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))sym("acos");
    return f(x);
}

double swe_shim_atan(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))sym("atan");
    return f(x);
}

double swe_shim_atan2(double y, double x) {
    static double (*f)(double, double);
    if (f == NULL) f = (double (*)(double, double))sym("atan2");
    return f(y, x);
}

double swe_shim_pow(double x, double y) {
    static double (*f)(double, double);
    if (f == NULL) f = (double (*)(double, double))sym("pow");
    return f(x, y);
}

double swe_shim_log10(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))sym("log10");
    return f(x);
}

double swe_shim_log(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))sym("log");
    return f(x);
}

double swe_shim_exp(double x) {
    static double (*f)(double);
    if (f == NULL) f = (double (*)(double))sym("exp");
    return f(x);
}

double swe_shim_fmod(double x, double y) {
    static double (*f)(double, double);
    if (f == NULL) f = (double (*)(double, double))sym("fmod");
    return f(x, y);
}
