// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
// Swiss Ephemeris Zig port --- swemmoon module (Moshier moon).
// Translated 1:1 from swemmoon.c to preserve exact floating-point
// operation order, differential-tested against the C oracle.
// The `swed.oec` obliquity and the astro_models entries that sweph.c
// threads through swi_epsiln/swi_precess are passed explicitly
// (same pattern as DeltatCtx); the SEI_MOON plan_data cache is kept
// as module state like C's swed.pldat[SEI_MOON].
const std = @import("std");
const lib = @import("swephlib");

const swe_shim_sin = lib.swe_shim_sin;
const swe_shim_cos = lib.swe_shim_cos;
const swe_shim_fmod = lib.swe_shim_fmod;

const PI = lib.PI;
const DEGTORAD = lib.DEGTORAD;
const RADTODEG = lib.RADTODEG;
const J2000 = lib.J2000;
const STR: f64 = 4.8481368110953599359e-6; // radians per arc second
const AUNIT: f64 = 1.49597870700e+11; // au in meters, DE431
const MOON_MEAN_DIST: f64 = 384400000.0; // in m
const MOON_MEAN_INCL: f64 = 5.1453964;
const MOON_MEAN_ECC: f64 = 0.054900489;
const MOON_SPEED_INTV: f64 = 0.00005; // 4.32 seconds (in days)
const MOSHLUEPH_START: f64 = 625000.5;
const MOSHLUEPH_END: f64 = 2818000.5;
const MOSHNDEPH_START: f64 = -3100015.5;
const MOSHNDEPH_END: f64 = 8000016.5;
const JPL_DE431_START: f64 = -3027215.5;
const JPL_DE431_END: f64 = 7930192.5;
const OK: i32 = 0;
const ERR: i32 = -1;
const SEI_MOON: usize = 1;
const SEI_INTP_APOG: i32 = 4;
const SEI_INTP_PERG: i32 = 5;
const SEFLG_MOSEPH: i32 = 4;
const AS_MAXCH: usize = 256;

const AstroModels = lib.AstroModels;
const Eps = lib.Eps;

pub fn swe_degnorm(x: f64) f64 {
    return lib.swe_degnorm(x);
}

// --- perturbation tables (swemmoon.c, MOSH_MOON_200 not defined) ---

const z = [25]f64{
    -13.12045233711,     -0.00113821591258,   -9.646018347184e-06, 31.46734198839,      0.0476835758578,
    -0.0003421689790404, -6.84707090541,      -0.005834100476561,  -0.0002905334122698, -5.663161722088,
    0.005722859298199,   -8.466472828815e-05, -84.29817796435,     -207.2552484689,     7.876842214863,
    1.836463749022,      -15.57471855361,     -20.06969124724,     21.52670284757,      -6.179946916139,
    -0.9070028191196,    -12.70848233038,     -2.145589319058,     13.81936399935,      -1.999840061168,
};

const LR = [944]i16{
    0,     0,     1,   0,     22639, 5858,  -20905, -3550, 2,    0,     -1,  0,     4586, 4383,  -3699, -1109, 2,   0,     0,    0,     2369, 9139,
    -2955, -9676, 0,   0,     2,     0,     769,    257,   -569, -9251, 0,   1,     0,    0,     -666,  -4171, 48,  8883,  0,    0,     0,    2,
    -411,  -5957, -3,  -1483, 2,     0,     -2,     0,     211,  6556,  246, 1585,  2,    -1,    -1,    0,     205, 4358,  -152, -1377, 2,    0,
    1,     0,     191, 9562,  -170,  -7331, 2,      -1,    0,    0,     164, 7285,  -204, -5860, 0,     1,     -1,  0,     -147, -3213, -129, -6201,
    1,     0,     0,   0,     -124,  -9881, 108,    7427,  0,    1,     1,   0,     -109, -3803, 104,   7552,  2,   0,     0,    -2,    55,   1771,
    10,    3211,  0,   0,     1,     2,     -45,    -996,  0,    0,     0,   0,     1,    -2,    39,    5333,  79,  6606,  4,    0,     -1,   0,
    38,    4298,  -34, -7825, 0,     0,     3,      0,     36,   1238,  -23, -2104, 4,    0,     -2,    0,     30,  7726,  -21,  -6363, 2,    1,
    -1,    0,     -28, -3971, 24,    2085,  2,      1,     0,    0,     -24, -3582, 30,   8238,  1,     0,     -1,  0,     -18,  -5847, -8,   -3791,
    1,     1,     0,   0,     17,    9545,  -16,    -6747, 2,    -1,    1,   0,     14,   5303,  -12,   -8314, 2,   0,     2,    0,     14,   3797,
    -10,   -4448, 4,   0,     0,     0,     13,     8991,  -11,  -6500, 2,   0,     -3,   0,     13,    1941,  14,  4027,  0,    1,     -2,   0,
    -9,    -6791, -7,  -27,   2,     0,     -1,     2,     -9,   -3659, 0,   7740,  2,    -1,    -2,    0,     8,   6055,  10,   562,   1,    0,
    1,     0,     -8,  -4531, 6,     3220,  2,      -2,    0,    0,     8,   502,   -9,   -8845, 0,     1,     2,   0,     -7,   -6302, 5,    7509,
    0,     2,     0,   0,     -7,    -4475, 1,      657,   2,    -2,    -1,  0,     7,    3712,  -4,    -9501, 2,   0,     1,    -2,    -6,   -3832,
    4,     1311,  2,   0,     0,     2,     -5,     -7416, 0,    0,     4,   -1,    -1,   0,     4,     3740,  -3,  -9580, 0,    0,     2,    2,
    -3,    -9976, 0,   0,     3,     0,     -1,     0,     -3,   -2097, 3,   2582,  2,    1,     1,     0,     -2,  -9145, 2,    6164,  4,    -1,
    -2,    0,     2,   7319,  -1,    -8970, 0,      2,     -1,   0,     -2,  -5679, -2,   -1171, 2,     2,     -1,  0,     -2,   -5212, 2,    3536,
    2,     1,     -2,  0,     2,     4889,  0,      1437,  2,    -1,    0,   -2,    2,    1461,  0,     6571,  4,   0,     1,    0,     1,    9777,
    -1,    -4226, 0,   0,     4,     0,     1,      9337,  -1,   -1169, 4,   -1,    0,    0,     1,     8708,  -1,  -5714, 1,    0,     -2,   0,
    -1,    -7530, -1,  -7385, 2,     1,     0,      -2,    -1,   -4372, 0,   -1357, 0,    0,     2,     -2,    -1,  -3726, -4,   -4212, 1,    1,
    1,     0,     1,   2618,  0,     -9333, 3,      0,     -2,   0,     -1,  -2241, 0,    8624,  4,     0,     -3,  0,     1,    1868,  0,    -5142,
    2,     -1,    2,   0,     1,     1770,  0,      -8488, 0,    2,     1,   0,     -1,   -1617, 1,     1655,  1,   1,     -1,   0,     1,    777,
    0,     8512,  2,   0,     3,     0,     1,      595,   0,    -6697, 2,   0,     1,    2,     0,     -9902, 0,   0,     2,    0,     -4,   0,
    0,     9483,  0,   7785,  2,     -2,    1,      0,     0,    7517,  0,   -6575, 0,    1,     -3,    0,     0,   -6694, 0,    -4224, 4,    1,
    -1,    0,     0,   -6352, 0,     5788,  1,      0,     2,    0,     0,   -5840, 0,    3785,  1,     0,     0,   -2,    0,    -5833, 0,    -7956,
    6,     0,     -2,  0,     0,     5716,  0,      -4225, 2,    0,     -2,  -2,    0,    -5606, 0,     4726,  1,   -1,    0,    0,     0,    -5569,
    0,     4976,  0,   1,     3,     0,     0,      -5459, 0,    3551,  2,   0,     -2,   2,     0,     -5357, 0,   7740,  2,    0,     -1,   -2,
    0,     1790,  8,   7516,  3,     0,     0,      0,     0,    4042,  -1,  -4189, 2,    -1,    -3,    0,     0,   4784,  0,    4950,  2,    -1,
    3,     0,     0,   932,   0,     -585,  2,      0,     2,    -2,    0,   -4538, 0,    2840,  2,     -1,    -1,  2,     0,    -4262, 0,    373,
    0,     0,     0,   4,     0,     4203,  0,      0,     0,    1,     0,   2,     0,    4134,  0,     -1580, 6,   0,     -1,   0,     0,    3945,
    0,     -2866, 2,   -1,    0,     2,     0,      -3821, 0,    0,     2,   -1,    1,    -2,    0,     -3745, 0,   2094,  4,    1,     -2,   0,
    0,     -3576, 0,   2370,  1,     1,     -2,     0,     0,    3497,  0,   3323,  2,    -3,    0,     0,     0,   3398,  0,    -4107, 0,    0,
    3,     2,     0,   -3286, 0,     0,     4,      -2,    -1,   0,     0,   -3087, 0,    -2790, 0,     1,     -1,  -2,    0,    3015,  0,    0,
    4,     0,     -1,  -2,    0,     3009,  0,      -3218, 2,    -2,    -2,  0,     0,    2942,  0,     3430,  6,   0,     -3,   0,     0,    2925,
    0,     -1832, 2,   1,     2,     0,     0,      -2902, 0,    2125,  4,   1,     0,    0,     0,     -2891, 0,   2445,  4,    -1,    1,    0,
    0,     2825,  0,   -2029, 3,     1,     -1,     0,     0,    2737,  0,   -2126, 0,    1,     1,     2,     0,   2634,  0,    0,     1,    0,
    0,     2,     0,   2543,  0,     0,     3,      0,     0,    -2,    0,   -2530, 0,    2010,  2,     2,     -2,  0,     0,    -2499, 0,    -1089,
    2,     -3,    -1,  0,     0,     2469,  0,      -1481, 3,    -1,    -1,  0,     0,    -2314, 0,     2556,  4,   0,     2,    0,     0,    2185,
    0,     -1392, 4,   0,     -1,    2,     0,      -2013, 0,    0,     0,   2,     -2,   0,     0,     -1931, 0,   0,     2,    2,     0,    0,
    0,     -1858, 0,   0,     2,     1,     -3,     0,     0,    1762,  0,   0,     4,    0,     -2,    2,     0,   -1698, 0,    0,     4,    -2,
    -2,    0,     0,   1578,  0,     -1083, 4,      -2,    0,    0,     0,   1522,  0,    -1281, 3,     1,     0,   0,     0,    1499,  0,    -1077,
    1,     -1,    -1,  0,     0,     -1364, 0,      1141,  1,    -3,    0,   0,     0,    -1281, 0,     0,     6,   0,     0,    0,     0,    1261,
    0,     -859,  2,   0,     2,     2,     0,      -1239, 0,    0,     1,   -1,    1,    0,     0,     -1207, 0,   1100,  0,    0,     5,    0,
    0,     1110,  0,   -589,  0,     3,     0,      0,     0,    -1013, 0,   213,   4,    -1,    -3,    0,     0,   998,   0,    0,
};

const MB = [462]i16{
    0,  0,     0,   1,     18461, 2387,  0,  0,     1,   1,     1010, 1671,  0,  0,     1,   -1,    999, 6936,  2,  0,     0,  -1,    623, 6524,  2,  0,
    -1, 1,     199, 4837,  2,     0,     -1, -1,    166, 5741,  2,    0,     0,  1,     117, 2607,  0,   0,     2,  1,     61, 9120,  2,   0,     1,  -1,
    33, 3572,  0,   0,     2,     -1,    31, 7597,  2,   -1,    0,    -1,    29, 5766,  2,   0,     -2,  -1,    15, 5663,  2,  0,     1,   1,     15, 1216,
    2,  1,     0,   -1,    -12,   -941,  2,  -1,    -1,  1,     8,    8681,  2,  -1,    0,   1,     7,   9586,  2,  -1,    -1, -1,    7,   4346,  0,  1,
    -1, -1,    -6,  -7314, 4,     0,     -1, -1,    6,   5796,  0,    1,     0,  1,     -6,  -4601, 0,   0,     0,  3,     -6, -2965, 0,   1,     -1, 1,
    -5, -6324, 1,   0,     0,     1,     -5, -3684, 0,   1,     1,    1,     -5, -3113, 0,   1,     1,   -1,    -5, -759,  0,  1,     0,   -1,    -4, -8396,
    1,  0,     0,   -1,    -4,    -8057, 0,  0,     3,   1,     3,    9841,  4,  0,     0,   -1,    3,   6745,  4,  0,     -1, 1,     2,   9985,  0,  0,
    1,  -3,    2,   7986,  4,     0,     -2, 1,     2,   4139,  2,    0,     0,  -3,    2,   1863,  2,   0,     2,  -1,    2,  1462,  2,   -1,    1,  -1,
    1,  7660,  2,   0,     -2,    1,     -1, -6244, 0,   0,     3,    -1,    1,  5813,  2,   0,     2,   1,     1,  5198,  2,  0,     -3,  -1,    1,  5156,
    2,  1,     -1,  1,     -1,    -3178, 2,  1,     0,   1,     -1,   -2643, 4,  0,     0,   1,     1,   1919,  2,  -1,    1,  1,     1,   1346,  2,  -2,
    0,  -1,    1,   859,   0,     0,     1,  3,     -1,  -194,  2,    1,     1,  -1,    0,   -8227, 1,   1,     0,  -1,    0,  8042,  1,   1,     0,  1,
    0,  8026,  0,   1,     -2,    -1,    0,  -7932, 2,   1,     -1,   -1,    0,  -7910, 1,   0,     1,   1,     0,  -6674, 2,  -1,    -2,  -1,    0,  6502,
    0,  1,     2,   1,     0,     -6388, 4,  0,     -2,  -1,    0,    6337,  4,  -1,    -1,  -1,    0,   5958,  1,  0,     1,  -1,    0,   -5889, 4,  0,
    1,  -1,    0,   4734,  1,     0,     -1, -1,    0,   -4299, 4,    -1,    0,  -1,    0,   4149,  2,   -2,    0,  1,     0,  3835,  3,   0,     0,  -1,
    0,  -3518, 4,   -1,    -1,    1,     0,  3388,  2,   0,     -1,   -3,    0,  3291,  2,   -2,    -1,  1,     0,  3147,  0,  1,     2,   -1,    0,  -3129,
    3,  0,     -1,  -1,    0,     -3052, 0,  1,     -2,  1,     0,    -3013, 2,  0,     1,   -3,    0,   -2912, 2,  -2,    -1, -1,    0,   2686,  0,  0,
    4,  1,     0,   2633,  2,     0,     -3, 1,     0,   2541,  2,    0,     -1, 3,     0,   -2448, 2,   1,     1,  1,     0,  -2370, 4,   -1,    -2, 1,
    0,  2138,  4,   0,     1,     1,     0,  2126,  3,   0,     -1,   1,     0,  -2059, 4,   1,     -1,  -1,    0,  -1719,
};

const LRT = [304]i16{
    0,  1,    0,  0,     16, 7680,  -1, -2302, 2,  -1,    -1, 0,     -5, -1642, 3,  8245,  2,  -1,    0,  0,    -4, -1383, 5,  1395, 0,  1,
    -1, 0,    3,  7115,  3,  2654,  0,  1,     1,  0,     2,  7560,  -2, -6396, 2,  1,     -1, 0,     0,  7118, 0,  -6068, 2,  1,    0,  0,
    0,  6128, 0,  -7754, 1,  1,     0,  0,     0,  -4516, 0,  4194,  2,  -2,    0,  0,     0,  -4048, 0,  4970, 0,  2,     0,  0,    0,  3747,
    0,  -540, 2,  -2,    -1, 0,     0,  -3707, 0,  2490,  2,  -1,    1,  0,     0,  -3649, 0,  3222,  0,  1,    -2, 0,     0,  2438, 0,  1760,
    2,  -1,   -2, 0,     0,  -2165, 0,  -2530, 0,  1,     2,  0,     0,  1923,  0,  -1450, 0,  2,     -1, 0,    0,  1292,  0,  1070, 2,  2,
    -1, 0,    0,  1271,  0,  -6070, 4,  -1,    -1, 0,     0,  -1098, 0,  990,   2,  0,     0,  0,     0,  1073, 0,  -1360, 2,  0,    -1, 0,
    0,  839,  0,  -630,  2,  1,     1,  0,     0,  734,   0,  -660,  4,  -1,    -2, 0,     0,  -688,  0,  480,  2,  1,     -2, 0,    0,  -630,
    0,  0,    0,  2,     1,  0,     0,  587,   0,  -590,  2,  -1,    0,  -2,    0,  -540,  0,  -170,  4,  -1,   0,  0,     0,  -468, 0,  390,
    2,  -2,   1,  0,     0,  -378,  0,  330,   2,  1,     0,  -2,    0,  364,   0,  0,     1,  1,     1,  0,    0,  -317,  0,  240,  2,  -1,
    2,  0,    0,  -295,  0,  210,   1,  1,     -1, 0,     0,  -270,  0,  -210,  2,  -3,    0,  0,     0,  -256, 0,  310,   2,  -3,   -1, 0,
    0,  -187, 0,  110,   0,  1,     -3, 0,     0,  169,   0,  110,   4,  1,     -1, 0,     0,  158,   0,  -150, 4,  -2,    -1, 0,    0,  -155,
    0,  140,  0,  0,     1,  0,     0,  155,   0,  -250,  2,  -2,    -2, 0,     0,  -148,  0,  -170,
};

const BT = [80]i16{
    2,  -1,  0,    -1,   -7430, 2, 1,  0,    -1,   3043, 2, -1, -1,   1,    -2229, 2,  -1, 0,   1,    -1999, 2, -1, -1,  -1,   -1869, 0,
    1,  -1,  -1,   1696, 0,     1, 0,  1,    1623, 0,    1, -1, 1,    1418, 0,     1,  1,  1,   1339, 0,     1, 1,  -1,  1278, 0,     1,
    0,  -1,  1217, 2,    -2,    0, -1, -547, 2,    -1,   1, -1, -443, 2,    1,     -1, 1,  331, 2,    1,     0, 1,  317, 2,    0,     0,
    -1, 295,
};

const LRT2 = [150]i16{
    0,  1,   0,   0,  487, -36, 2,  -1,  -1,  0, -150, 111, 2,  -1,  0,  0,  -120, 149, 0,   1,  -1, 0,  108, 95, 0,   1,  1, 0,
    80, -77, 2,   1,  -1,  0,   21, -18, 2,   1, 0,    0,   20, -23, 1,  1,  0,    0,   -13, 12, 2,  -2, 0,   0,  -12, 14, 2, -1,
    1,  0,   -11, 9,  2,   -2,  -1, 0,   -11, 7, 0,    2,   0,  0,   11, 0,  2,    -1,  -2,  0,  -6, -7, 0,   1,  -2,  0,  7, 5,
    0,  1,   2,   0,  6,   -4,  2,  2,   -1,  0, 5,    -3,  0,  2,   -1, 0,  5,    3,   4,   -1, -1, 0,  -3,  3,  2,   0,  0, 0,
    3,  -4,  4,   -1, -2,  0,   -2, 0,   2,   1, -2,   0,   -2, 0,   2,  -1, 0,    -2,  -2,  0,  2,  1,  1,   0,  2,   -2, 2, 0,
    -1, 0,   2,   0,  0,   2,   1,  0,   2,   0,
};

const BT2 = [60]i16{
    2, -1, 0,  -1, -22, 2, 1, 0, -1, 9, 2, -1, 0, 1,  -6, 2, -1, -1, 1,  -6, 2, -1, -1, -1, -5, 0, 1,  0, 1,  5,
    0, 1,  -1, -1, 5,   0, 1, 1, 1,  4, 0, 1,  1, -1, 4,  0, 1,  0,  -1, 4,  0, 1,  -1, 1,  4,  2, -2, 0, -1, -2,
};

const mean_node_corr = [304]f64{
    -2.56,     -2.473,    -2.392347, -2.316425, -2.239639, -2.167764, -2.0951,   -2.02481,  -1.957622, -1.890097,
    -1.826389, -1.763335, -1.701047, -1.643016, -1.584186, -1.527309, -1.473352, -1.418917, -1.367736, -1.317202,
    -1.267269, -1.221121, -1.174218, -1.128862, -1.086214, -1.042998, -1.002491, -0.962635, -0.923176, -0.887191,
    -0.850403, -0.814929, -0.782117, -0.748462, -0.717241, -0.686598, -0.656013, -0.628726, -0.60046,  -0.573219,
    -0.548634, -0.522931, -0.499285, -0.476273, -0.452978, -0.432663, -0.411386, -0.390788, -0.372825, -0.353681,
    -0.33623,  -0.31952,  -0.302343, -0.287794, -0.272262, -0.257166, -0.244534, -0.230635, -0.218126, -0.206365,
    -0.194,    -0.183876, -0.172782, -0.161877, -0.153254, -0.143371, -0.134501, -0.126552, -0.117932, -0.111199,
    -0.103716, -0.09616,  -0.090718, -0.084046, -0.078007, -0.072959, -0.067235, -0.06299,  -0.058102, -0.05307,
    -0.049786, -0.045381, -0.041317, -0.038165, -0.034501, -0.031871, -0.028844, -0.025701, -0.024018, -0.021427,
    -0.018881, -0.017291, -0.015186, -0.013755, -0.012098, -0.010261, -0.009688, -0.008218, -0.00667,  -0.005979,
    -0.004756, -0.003991, -0.002996, -0.001974, -0.001975, -0.001213, -0.000377, -0.000356, 5.779e-05, 0.000378,
    0.00071,   0.001092,  0.000767,  0.000985,  0.001443,  0.001069,  0.001141,  0.001321,  0.001462,  0.001695,
    0.001319,  0.001567,  0.001873,  0.001376,  0.001336,  0.001347,  0.00133,   0.001256,  0.000813,  0.000946,
    0.001079,  0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,
    0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,
    0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,
    0.0,       -0.000364, -0.000452, -0.001091, -0.001159, -0.001136, -0.001798, -0.002249, -0.002622, -0.00299,
    -0.003555, -0.004425, -0.004758, -0.005134, -0.006065, -0.006839, -0.007474, -0.008283, -0.009411, -0.010786,
    -0.01181,  -0.012989, -0.014825, -0.016426, -0.017922, -0.019774, -0.021881, -0.024194, -0.02619,  -0.02844,
    -0.031285, -0.033817, -0.036318, -0.039212, -0.042456, -0.045799, -0.048994, -0.05271,  -0.056948, -0.061017,
    -0.065181, -0.069843, -0.074922, -0.079976, -0.085052, -0.090755, -0.09684,  -0.102797, -0.108939, -0.115568,
    -0.122636, -0.129593, -0.136683, -0.144641, -0.152825, -0.161044, -0.169758, -0.178916, -0.188712, -0.198401,
    -0.208312, -0.219395, -0.230407, -0.241577, -0.253508, -0.26564,  -0.278556, -0.29133,  -0.304353, -0.318815,
    -0.332882, -0.347316, -0.362895, -0.378421, -0.395061, -0.411748, -0.428666, -0.447477, -0.465636, -0.484277,
    -0.5046,   -0.524405, -0.545533, -0.56702,  -0.588404, -0.612099, -0.634965, -0.658262, -0.683866, -0.708526,
    -0.734719, -0.7618,   -0.788562, -0.818092, -0.846885, -0.876177, -0.908385, -0.939371, -0.972027, -1.006149,
    -1.039634, -1.076135, -1.112156, -1.14849,  -1.188312, -1.226761, -1.266821, -1.309156, -1.350583, -1.395223,
    -1.440028, -1.485047, -1.534104, -1.582023, -1.631506, -1.684031, -1.735687, -1.790421, -1.846039, -1.901951,
    -1.961872, -2.021179, -2.081987, -2.146259, -2.210031, -2.276609, -2.344904, -2.413795, -2.486559, -2.559564,
    -2.634215, -2.712692, -2.791289, -2.872533, -2.956217, -3.040965, -3.129234, -3.218545, -3.309805, -3.404827,
    -3.5008,   -3.601,    -3.7,      -3.8,
};

const mean_apsis_corr = [304]f64{
    7.525,     7.29,      7.057295,  6.830813,  6.611723,  6.396775,  6.189569, 5.985968,  5.788342,  5.597304,  5.410167,
    5.229946,  5.053389,  4.882187,  4.716494,  4.553532,  4.396734,  4.243718, 4.094282,  3.950865,  3.810366,  3.674978,
    3.543284,  3.41427,   3.290526,  3.168775,  3.050904,  2.937541,  2.826189, 2.719822,  2.616193,  2.515431,  2.419193,
    2.323782,  2.232545,  2.143635,  2.056803,  1.974913,  1.893874,  1.816201, 1.741957,  1.668083,  1.598335,  1.529645,
    1.463016,  1.399693,  1.336905,  1.278097,  1.220965,  1.165092,  1.113071, 1.060858,  1.011007,  0.963701,  0.916523,
    0.872887,  0.829596,  0.788486,  0.750017,  0.711177,  0.675589,  0.640303, 0.605303,  0.57349,   0.541113,  0.511482,
    0.483159,  0.45521,   0.430305,  0.404643,  0.380782,  0.358524,  0.335405, 0.315244,  0.295131,  0.275766,  0.259223,
    0.241586,  0.22589,   0.210404,  0.194775,  0.181573,  0.167246,  0.154514, 0.143435,  0.131131,  0.121648,  0.111835,
    0.102474,  0.094284,  0.085204,  0.07824,   0.070697,  0.063696,  0.058894, 0.05239,   0.047632,  0.043129,  0.037823,
    0.034143,  0.029188,  0.025648,  0.021972,  0.018348,  0.017127,  0.013989, 0.011967,  0.011003,  0.007865,  0.007033,
    0.005574,  0.00406,   0.003699,  0.002465,  0.002889,  0.002144,  0.001018, 0.001757,  -9.67e-05, -0.000734, -0.000392,
    -0.001546, -0.000863, -0.001266, -0.000933, -0.000503, -0.001304, 0.000238, -0.000507, -0.000897, 0.000647,  0.0,
    0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,      0.0,       0.0,       0.0,       0.0,
    0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,      0.0,       0.0,       0.0,       0.0,
    0.0,       0.0,       0.0,       0.0,       0.0,       0.0,       0.0,      0.000514,  0.000683,  0.002228,  0.001974,
    0.003485,  0.00428,   0.005409,  0.007468,  0.007938,  0.011012,  0.012525, 0.013757,  0.016757,  0.017932,  0.02078,
    0.023416,  0.026386,  0.030428,  0.033512,  0.038789,  0.043126,  0.047778, 0.054175,  0.058891,  0.065878,  0.072345,
    0.079668,  0.088238,  0.095307,  0.104873,  0.113533,  0.122336,  0.133205, 0.142922,  0.154871,  0.166488,  0.179234,
    0.193928,  0.207262,  0.223089,  0.238736,  0.254907,  0.273232,  0.291085, 0.311046,  0.331025,  0.351955,  0.374422,
    0.396341,  0.420772,  0.444867,  0.469984,  0.497448,  0.524717,  0.554752, 0.584581,  0.616272,  0.649744,  0.682947,
    0.719405,  0.755834,  0.79378,   0.833875,  0.873893,  0.91734,   0.960429, 1.005471,  1.052384,  1.099317,  1.149508,
    1.20013,   1.253038,  1.307672,  1.36348,   1.422592,  1.4819,    1.544111, 1.607982,  1.672954,  1.741025,  1.809727,
    1.882038,  1.955243,  2.029956,  2.108428,  2.186805,  2.268697,  2.352071, 2.43737,   2.525903,  2.615415,  2.709082,
    2.804198,  2.901704,  3.002606,  3.104412,  3.210406,  3.317733,  3.428386, 3.541634,  3.656634,  3.775988,  3.896306,
    4.02048,   4.146814,  4.275356,  4.408257,  4.542282,  4.681174,  4.822524, 4.966424,  5.114948,  5.264973,  5.419906,
    5.577056,  5.737688,  5.902347,  6.069138,  6.241065,  6.415155,  6.593317, 6.774853,  6.959322,  7.148845,  7.340334,
    7.537156,  7.737358,  7.940882,  8.149932,  8.361576,  8.57915,   8.799591, 9.024378,  9.254584,  9.487362,  9.726535,
    9.968784,  10.216089, 10.467716, 10.725293, 10.986,    11.25,     11.52,
};

const NLR: usize = 118;
const NMB: usize = 77;
const NLRT: usize = 38;
const NBT: usize = 16;
const NLRT2: usize = 25;
const NBT2: usize = 12;

// --- file static state (swemmoon.c; TLS in C, plain here) ---
/// Moshier moon workspace + save area (was swemmoon.c file statics; TLS
/// there). Lives in Swed so each instance owns its computation context:
/// ss/cc are lazily built per date range, pdp_* is the moon position cache
/// (swed.pldat[SEI_MOON] equivalent fields swi_moshmoon touches).
pub const MoonWs = struct {
    ss: [5][8]f64 = undefined,
    cc: [5][8]f64 = undefined,
    l: f64 = undefined, // Moon's ecliptic longitude
    B: f64 = undefined, // Ecliptic latitude
    moonpol: [3]f64 = undefined,
    SWELP: f64 = undefined,
    M: f64 = undefined,
    MP: f64 = undefined,
    D: f64 = undefined,
    NF: f64 = undefined,
    T: f64 = undefined,
    T2: f64 = undefined,
    T3: f64 = undefined,
    T4: f64 = undefined,
    f: f64 = undefined,
    g: f64 = undefined,
    Ve: f64 = undefined,
    Ea: f64 = undefined,
    Ma: f64 = undefined,
    Ju: f64 = undefined,
    Sa: f64 = undefined,
    cg: f64 = undefined,
    sg: f64 = undefined,
    l1: f64 = undefined,
    l2: f64 = undefined,
    l3: f64 = undefined,
    l4: f64 = undefined,
    pdp_teval: f64 = 0,
    pdp_xflgs: i32 = 0,
    pdp_iephe: i32 = 0,
    pdp_x: [6]f64 = undefined,
};

/// Calculate geometric coordinates of Moon without light time or
/// nutation correction (swemmoon.c swi_moshmoon2).
pub fn swi_moshmoon2(J: f64, pol: *[3]f64, ws: *MoonWs) i32 {
    ws.T = (J - J2000) / 36525.0;
    ws.T2 = ws.T * ws.T;
    mean_elements(ws);
    mean_elements_pl(ws);
    moon1(ws);
    moon2(ws);
    moon3(ws);
    moon4(ws);
    var i: usize = 0;
    while (i < 3) : (i += 1)
        pol[i] = ws.moonpol[i];
    return 0;
}

/// Moshier's moon (swemmoon.c swi_moshmoon); `oec` is swed.oec and
/// `models` the astro_models entries (both threaded explicitly).
pub fn swi_moshmoon(tjd: f64, do_save: bool, xpmret: ?*[6]f64, oec: *const Eps, models: AstroModels, serr: ?[]u8, ws: *MoonWs) i32 {
    var a: f64 = undefined;
    var b: f64 = undefined;
    var x1: [6]f64 = undefined;
    var x2: [6]f64 = undefined;
    var t: f64 = undefined;
    var xx: [6]f64 = undefined;
    var s: [AS_MAXCH]u8 = undefined;
    // in C: xpm points to pdp->x when do_save, else to local xx
    if (tjd < MOSHLUEPH_START - 0.2 or tjd > MOSHLUEPH_END + 0.2) {
        if (serr != null) {
            if (std.fmt.bufPrint(&s, "jd {d:.6} outside Moshier's Moon range {d:.2} .. {d:.2} ", .{ tjd, MOSHLUEPH_START, MOSHLUEPH_END })) |str| {
                appendSerr(serr.?, str);
            } else |_| {}
        }
        return ERR;
    }
    // if moon has already been computed
    if (tjd == ws.pdp_teval and ws.pdp_iephe == SEFLG_MOSEPH) {
        if (xpmret != null) {
            var i: usize = 0;
            while (i <= 5) : (i += 1)
                xpmret.?[i] = ws.pdp_x[i];
        }
        return OK;
    }
    // else compute moon (writes pol[0..2]; mirrors C writing xpm[0..2])
    const xpm: *[6]f64 = if (do_save) &ws.pdp_x else &xx;
    {
        var tmp3: [3]f64 = undefined;
        _ = swi_moshmoon2(tjd, &tmp3, ws);
        xpm[0] = tmp3[0];
        xpm[1] = tmp3[1];
        xpm[2] = tmp3[2];
    }
    if (do_save) {
        ws.pdp_teval = tjd;
        ws.pdp_xflgs = -1;
        ws.pdp_iephe = SEFLG_MOSEPH;
    }
    // Moshier moon is referred to ecliptic of date; convert to
    // equatorial J2000.
    ecldat_equ2000(tjd, xpm, oec, models);
    // speed from two other positions
    t = tjd + MOON_SPEED_INTV;
    _ = swi_moshmoon2(t, x1[0..3], ws);
    ecldat_equ2000(t, &x1, oec, models);
    t = tjd - MOON_SPEED_INTV;
    _ = swi_moshmoon2(t, x2[0..3], ws);
    ecldat_equ2000(t, &x2, oec, models);
    var i: usize = 0;
    while (i <= 2) : (i += 1) {
        b = (x1[i] - x2[i]) / 2;
        a = (x1[i] + x2[i]) / 2 - xpm[i];
        xpm[i + 3] = (2 * a + b) / MOON_SPEED_INTV;
    }
    if (xpmret != null) {
        i = 0;
        while (i <= 5) : (i += 1)
            xpmret.?[i] = xpm[i];
    }
    return OK;
}

fn appendSerr(serr: []u8, s: []const u8) void {
    const len = std.mem.indexOfScalar(u8, serr, 0) orelse serr.len;
    if (len + s.len < AS_MAXCH) {
        @memcpy(serr[len .. len + s.len], s);
        if (len + s.len < serr.len) serr[len + s.len] = 0;
    }
}

/// converts from polar coordinates of ecliptic of date to cartesian
/// coordinates of equator 2000 (swemmoon.c ecldat_equ2000)
fn ecldat_equ2000(tjd: f64, xpm: *[6]f64, oec: *const Eps, models: AstroModels) void {
    var p3: [3]f64 = undefined;
    // cartesian
    p3 = .{ xpm[0], xpm[1], xpm[2] };
    lib.swi_polcart(&p3, &p3);
    // equatorial
    lib.swi_coortrf2(&p3, &p3, -oec.seps, oec.ceps);
    // j2000
    _ = lib.swi_precess(&p3, tjd, 0, lib.J_TO_J2000, models);
    xpm[0] = p3[0];
    xpm[1] = p3[1];
    xpm[2] = p3[2];
}

/// Reduce arc seconds modulo 360 degrees; answer in arc seconds
fn mods3600(x: f64) f64 {
    var lx = x;
    lx = lx - 1296000.0 * std.math.floor(lx / 1296000.0);
    return lx;
}

pub fn swi_mean_lunar_elements(tjd: f64, node: *f64, dnode: *f64, peri: *f64, dperi: *f64, ws: *MoonWs) void {
    var dcor: f64 = undefined;
    ws.T = (tjd - J2000) / 36525.0;
    ws.T2 = ws.T * ws.T;
    mean_elements(ws);
    node.* = swe_degnorm((ws.SWELP - ws.NF) * STR * RADTODEG);
    peri.* = swe_degnorm((ws.SWELP - ws.MP) * STR * RADTODEG);
    ws.T -= 1.0 / 36525.0;
    mean_elements(ws);
    dnode.* = swe_degnorm(node.* - (ws.SWELP - ws.NF) * STR * RADTODEG);
    dnode.* -= 360;
    dperi.* = swe_degnorm(peri.* - (ws.SWELP - ws.MP) * STR * RADTODEG);
    dcor = corr_mean_node(tjd);
    node.* = swe_degnorm(node.* - dcor);
    dcor = corr_mean_apog(tjd);
    peri.* = swe_degnorm(peri.* - dcor);
}

fn mean_elements(ws: *MoonWs) void {
    const fracT = swe_shim_fmod(ws.T, 1);
    // Mean anomaly of sun = ws.l' (J. Laskar)
    ws.M = mods3600(129600000.0 * fracT - 3418.961646 * ws.T + 1287104.76154);
    ws.M += ((((((((1.62e-20 * ws.T - 1.0390e-17) * ws.T - 3.83508e-15) * ws.T + 4.237343e-13) * ws.T + 8.8555011e-11) * ws.T - 4.77258489e-8) * ws.T - 1.1297037031e-5) * ws.T + 1.4732069041e-4) * ws.T - 0.552891801772) * ws.T2;
    // Mean distance of moon from its ascending node = F
    ws.NF = mods3600(1739232000.0 * fracT + 295263.0983 * ws.T - 2.079419901760e-01 * ws.T + 335779.55755);
    // Mean anomaly of moon = ws.l
    ws.MP = mods3600(1717200000.0 * fracT + 715923.4728 * ws.T - 2.035946368532e-01 * ws.T + 485868.28096);
    // Mean elongation of moon = ws.D
    ws.D = mods3600(1601856000.0 * fracT + 1105601.4603 * ws.T + 3.962893294503e-01 * ws.T + 1072260.73512);
    // Mean longitude of moon, referred to the mean ecliptic and equinox of date
    ws.SWELP = mods3600(1731456000.0 * fracT + 1108372.83264 * ws.T - 6.784914260953e-01 * ws.T + 785939.95571);
    // Higher degree secular terms found by least squares fit
    ws.NF += ((z[2] * ws.T + z[1]) * ws.T + z[0]) * ws.T2;
    ws.MP += ((z[5] * ws.T + z[4]) * ws.T + z[3]) * ws.T2;
    ws.D += ((z[8] * ws.T + z[7]) * ws.T + z[6]) * ws.T2;
    ws.SWELP += ((z[11] * ws.T + z[10]) * ws.T + z[9]) * ws.T2;
}

pub fn mean_elements_pl(ws: *MoonWs) void {
    // Mean longitudes of planets (Laskar, Bretagnon)
    ws.Ve = mods3600(210664136.4335482 * ws.T + 655127.283046);
    ws.Ve += ((((((((-9.36e-023 * ws.T - 1.95e-20) * ws.T + 6.097e-18) * ws.T + 4.43201e-15) * ws.T + 2.509418e-13) * ws.T - 3.0622898e-10) * ws.T - 2.26602516e-9) * ws.T - 1.4244812531e-5) * ws.T + 0.005871373088) * ws.T2;
    ws.Ea = mods3600(129597742.26669231 * ws.T + 361679.214649);
    ws.Ea += ((((((((-1.16e-22 * ws.T + 2.976e-19) * ws.T + 2.8460e-17) * ws.T - 1.08402e-14) * ws.T - 1.226182e-12) * ws.T + 1.7228268e-10) * ws.T + 1.515912254e-7) * ws.T + 8.863982531e-6) * ws.T - 2.0199859001e-2) * ws.T2;
    ws.Ma = mods3600(68905077.59284 * ws.T + 1279559.78866);
    ws.Ma += (-1.043e-5 * ws.T + 9.38012e-3) * ws.T2;
    ws.Ju = mods3600(10925660.428608 * ws.T + 123665.342120);
    ws.Ju += (1.543273e-5 * ws.T - 3.06037836351e-1) * ws.T2;
    ws.Sa = mods3600(4399609.65932 * ws.T + 180278.89694);
    ws.Sa += ((4.475946e-8 * ws.T - 6.874806E-5) * ws.T + 7.56161437443E-1) * ws.T2;
}

fn moon1(ws: *MoonWs) void {
    var a: f64 = undefined;
    // initialise ws.ss and ws.cc (Bhanu Pinnamaneni, 17-aug-2009)
    var i: usize = 0;
    while (i < 5) : (i += 1) {
        var j: usize = 0;
        while (j < 8) : (j += 1) {
            ws.ss[i][j] = 0;
            ws.cc[i][j] = 0;
        }
    }
    sscc(0, STR * ws.D, 6, ws);
    sscc(1, STR * ws.M, 4, ws);
    sscc(2, STR * ws.MP, 4, ws);
    sscc(3, STR * ws.NF, 4, ws);
    ws.moonpol[0] = 0.0;
    ws.moonpol[1] = 0.0;
    ws.moonpol[2] = 0.0;
    // terms in ws.T^2, scale 1.0 = 10^-5"
    chewm(&LRT2, NLRT2, 4, 2, &ws.moonpol, ws);
    chewm(&BT2, NBT2, 4, 4, &ws.moonpol, ws);
    ws.f = 18 * ws.Ve - 16 * ws.Ea;
    ws.g = STR * (ws.f - ws.MP); // 18V - 16E - ws.l
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l = 6.367278 * ws.cg + 12.747036 * ws.sg; // t^0
    ws.l1 = 23123.70 * ws.cg - 10570.02 * ws.sg; // t^1
    ws.l2 = z[12] * ws.cg + z[13] * ws.sg; // t^2
    ws.moonpol[2] += 5.01 * ws.cg + 2.72 * ws.sg;
    ws.g = STR * (10.0 * ws.Ve - 3.0 * ws.Ea - ws.MP);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += -0.253102 * ws.cg + 0.503359 * ws.sg;
    ws.l1 += 1258.46 * ws.cg + 707.29 * ws.sg;
    ws.l2 += z[14] * ws.cg + z[15] * ws.sg;
    ws.g = STR * (8.0 * ws.Ve - 13.0 * ws.Ea);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += -0.187231 * ws.cg - 0.127481 * ws.sg;
    ws.l1 += -319.87 * ws.cg - 18.34 * ws.sg;
    ws.l2 += z[16] * ws.cg + z[17] * ws.sg;
    a = 4.0 * ws.Ea - 8.0 * ws.Ma + 3.0 * ws.Ju;
    ws.g = STR * a;
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += -0.866287 * ws.cg + 0.248192 * ws.sg;
    ws.l1 += 41.87 * ws.cg + 1053.97 * ws.sg;
    ws.l2 += z[18] * ws.cg + z[19] * ws.sg;
    ws.g = STR * (a - ws.MP);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += -0.165009 * ws.cg + 0.044176 * ws.sg;
    ws.l1 += 4.67 * ws.cg + 201.55 * ws.sg;
    ws.g = STR * ws.f; // 18V - 16E
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += 0.330401 * ws.cg + 0.661362 * ws.sg;
    ws.l1 += 1202.67 * ws.cg - 555.59 * ws.sg;
    ws.l2 += z[20] * ws.cg + z[21] * ws.sg;
    ws.g = STR * (ws.f - 2.0 * ws.MP); // 18V - 16E - 2l
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += 0.352185 * ws.cg + 0.705041 * ws.sg;
    ws.l1 += 1283.59 * ws.cg - 586.43 * ws.sg;
    ws.g = STR * (2.0 * ws.Ju - 5.0 * ws.Sa);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += -0.034700 * ws.cg + 0.160041 * ws.sg;
    ws.l2 += z[22] * ws.cg + z[23] * ws.sg;
    ws.g = STR * (ws.SWELP - ws.NF);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += 0.000116 * ws.cg + 7.063040 * ws.sg;
    ws.l1 += 298.8 * ws.sg;
    // ws.T^3 terms
    ws.sg = swe_shim_sin(STR * ws.M);
    ws.l3 = z[24] * ws.sg;
    ws.l4 = 0;
    ws.g = STR * (2.0 * ws.D - ws.M);
    ws.sg = swe_shim_sin(ws.g);
    ws.cg = swe_shim_cos(ws.g);
    ws.moonpol[2] += -0.2655 * ws.cg * ws.T;
    ws.g = STR * (ws.M - ws.MP);
    ws.moonpol[2] += -0.1568 * swe_shim_cos(ws.g) * ws.T;
    ws.g = STR * (ws.M + ws.MP);
    ws.moonpol[2] += 0.1309 * swe_shim_cos(ws.g) * ws.T;
    ws.g = STR * (2.0 * (ws.D + ws.M) - ws.MP);
    ws.sg = swe_shim_sin(ws.g);
    ws.cg = swe_shim_cos(ws.g);
    ws.moonpol[2] += 0.5568 * ws.cg * ws.T;
    ws.l2 += ws.moonpol[0];
    ws.g = STR * (2.0 * ws.D - ws.M - ws.MP);
    ws.moonpol[2] += -0.1910 * swe_shim_cos(ws.g) * ws.T;
    ws.moonpol[1] *= ws.T;
    ws.moonpol[2] *= ws.T;
    // terms in ws.T
    ws.moonpol[0] = 0.0;
    chewm(&BT, NBT, 4, 4, &ws.moonpol, ws);
    chewm(&LRT, NLRT, 4, 1, &ws.moonpol, ws);
    ws.g = STR * (ws.f - ws.MP - ws.NF - 2355767.6); // 18V - 16E - ws.l - F
    ws.moonpol[1] += -1127.0 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.f - ws.MP + ws.NF - 235353.6); // 18V - 16E - ws.l + F
    ws.moonpol[1] += -1123.0 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.Ea + ws.D + 51987.6);
    ws.moonpol[1] += 1303.0 * swe_shim_sin(ws.g);
    ws.g = STR * ws.SWELP;
    ws.moonpol[1] += 342.0 * swe_shim_sin(ws.g);
    ws.g = STR * (2.0 * ws.Ve - 3.0 * ws.Ea);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += -0.343550 * ws.cg - 0.000276 * ws.sg;
    ws.l1 += 105.90 * ws.cg + 336.53 * ws.sg;
    ws.g = STR * (ws.f - 2.0 * ws.D); // 18V - 16E - 2D
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += 0.074668 * ws.cg + 0.149501 * ws.sg;
    ws.l1 += 271.77 * ws.cg - 124.20 * ws.sg;
    ws.g = STR * (ws.f - 2.0 * ws.D - ws.MP);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += 0.073444 * ws.cg + 0.147094 * ws.sg;
    ws.l1 += 265.24 * ws.cg - 121.16 * ws.sg;
    ws.g = STR * (ws.f + 2.0 * ws.D - ws.MP);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += 0.072844 * ws.cg + 0.145829 * ws.sg;
    ws.l1 += 265.18 * ws.cg - 121.29 * ws.sg;
    ws.g = STR * (ws.f + 2.0 * (ws.D - ws.MP));
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += 0.070201 * ws.cg + 0.140542 * ws.sg;
    ws.l1 += 255.36 * ws.cg - 116.79 * ws.sg;
    ws.g = STR * (ws.Ea + ws.D - ws.NF);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += 0.288209 * ws.cg - 0.025901 * ws.sg;
    ws.l1 += -63.51 * ws.cg - 240.14 * ws.sg;
    ws.g = STR * (2.0 * ws.Ea - 3.0 * ws.Ju + 2.0 * ws.D - ws.MP);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += 0.077865 * ws.cg + 0.438460 * ws.sg;
    ws.l1 += 210.57 * ws.cg + 124.84 * ws.sg;
    ws.g = STR * (ws.Ea - 2.0 * ws.Ma);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += -0.216579 * ws.cg + 0.241702 * ws.sg;
    ws.l1 += 197.67 * ws.cg + 125.23 * ws.sg;
    ws.g = STR * (a + ws.MP);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += -0.165009 * ws.cg + 0.044176 * ws.sg;
    ws.l1 += 4.67 * ws.cg + 201.55 * ws.sg;
    ws.g = STR * (a + 2.0 * ws.D - ws.MP);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += -0.133533 * ws.cg + 0.041116 * ws.sg;
    ws.l1 += 6.95 * ws.cg + 187.07 * ws.sg;
    ws.g = STR * (a - 2.0 * ws.D + ws.MP);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += -0.133430 * ws.cg + 0.041079 * ws.sg;
    ws.l1 += 6.28 * ws.cg + 169.08 * ws.sg;
    ws.g = STR * (3.0 * ws.Ve - 4.0 * ws.Ea);
    ws.cg = swe_shim_cos(ws.g);
    ws.sg = swe_shim_sin(ws.g);
    ws.l += -0.175074 * ws.cg + 0.003035 * ws.sg;
    ws.l1 += 49.17 * ws.cg + 150.57 * ws.sg;
    ws.g = STR * (2.0 * (ws.Ea + ws.D - ws.MP) - 3.0 * ws.Ju + 213534.0);
    ws.l1 += 158.4 * swe_shim_sin(ws.g);
    ws.l1 += ws.moonpol[0];
    a = 0.1 * ws.T; // set amplitude scale of 1.0 = 10^-4 arcsec
    ws.moonpol[1] *= a;
    ws.moonpol[2] *= a;
}

fn moon2(ws: *MoonWs) void {
    // terms in ws.T^0
    ws.g = STR * (2 * (ws.Ea - ws.Ju + ws.D) - ws.MP + 648431.172);
    ws.l += 1.14307 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.Ve - ws.Ea + 648035.568);
    ws.l += 0.82155 * swe_shim_sin(ws.g);
    ws.g = STR * (3 * (ws.Ve - ws.Ea) + 2 * ws.D - ws.MP + 647933.184);
    ws.l += 0.64371 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.Ea - ws.Ju + 4424.04);
    ws.l += 0.63880 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.SWELP + ws.MP - ws.NF + 4.68);
    ws.l += 0.49331 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.SWELP - ws.MP - ws.NF + 4.68);
    ws.l += 0.4914 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.SWELP + ws.NF + 2.52);
    ws.l += 0.36061 * swe_shim_sin(ws.g);
    ws.g = STR * (2.0 * ws.Ve - 2.0 * ws.Ea + 736.2);
    ws.l += 0.30154 * swe_shim_sin(ws.g);
    ws.g = STR * (2.0 * ws.Ea - 3.0 * ws.Ju + 2.0 * ws.D - 2.0 * ws.MP + 36138.2);
    ws.l += 0.28282 * swe_shim_sin(ws.g);
    ws.g = STR * (2.0 * ws.Ea - 2.0 * ws.Ju + 2.0 * ws.D - 2.0 * ws.MP + 311.0);
    ws.l += 0.24516 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.Ea - ws.Ju - 2.0 * ws.D + ws.MP + 6275.88);
    ws.l += 0.21117 * swe_shim_sin(ws.g);
    ws.g = STR * (2.0 * (ws.Ea - ws.Ma) - 846.36);
    ws.l += 0.19444 * swe_shim_sin(ws.g);
    ws.g = STR * (2.0 * (ws.Ea - ws.Ju) + 1569.96);
    ws.l -= 0.18457 * swe_shim_sin(ws.g);
    ws.g = STR * (2.0 * (ws.Ea - ws.Ju) - ws.MP - 55.8);
    ws.l += 0.18256 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.Ea - ws.Ju - 2.0 * ws.D + 6490.08);
    ws.l += 0.16499 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.Ea - 2.0 * ws.Ju - 212378.4);
    ws.l += 0.16427 * swe_shim_sin(ws.g);
    ws.g = STR * (2.0 * (ws.Ve - ws.Ea - ws.D) + ws.MP + 1122.48);
    ws.l += 0.16088 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.Ve - ws.Ea - ws.MP + 32.04);
    ws.l -= 0.15350 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.Ea - ws.Ju - ws.MP + 4488.88);
    ws.l += 0.14346 * swe_shim_sin(ws.g);
    ws.g = STR * (2.0 * (ws.Ve - ws.Ea + ws.D) - ws.MP - 8.64);
    ws.l += 0.13594 * swe_shim_sin(ws.g);
    ws.g = STR * (2.0 * (ws.Ve - ws.Ea - ws.D) + 1319.76);
    ws.l += 0.13432 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.Ve - ws.Ea - 2.0 * ws.D + ws.MP - 56.16);
    ws.l -= 0.13122 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.Ve - ws.Ea + ws.MP + 54.36);
    ws.l -= 0.12722 * swe_shim_sin(ws.g);
    ws.g = STR * (3.0 * (ws.Ve - ws.Ea) - ws.MP + 433.8);
    ws.l += 0.12539 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.Ea - ws.Ju + ws.MP + 4002.12);
    ws.l += 0.10994 * swe_shim_sin(ws.g);
    ws.g = STR * (20.0 * ws.Ve - 21.0 * ws.Ea - 2.0 * ws.D + ws.MP - 317511.72);
    ws.l += 0.10652 * swe_shim_sin(ws.g);
    ws.g = STR * (26.0 * ws.Ve - 29.0 * ws.Ea - ws.MP + 270002.52);
    ws.l += 0.10490 * swe_shim_sin(ws.g);
    ws.g = STR * (3.0 * ws.Ve - 4.0 * ws.Ea + ws.D - ws.MP - 322765.56);
    ws.l += 0.10386 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.SWELP + 648002.556);
    ws.B = 8.04508 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.Ea + ws.D + 996048.252);
    ws.B += 1.51021 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.f - ws.MP + ws.NF + 95554.332);
    ws.B += 0.63037 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.f - ws.MP - ws.NF + 95553.792);
    ws.B += 0.63014 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.SWELP - ws.MP + 2.9);
    ws.B += 0.45587 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.SWELP + ws.MP + 2.5);
    ws.B += -0.41573 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.SWELP - 2.0 * ws.NF + 3.2);
    ws.B += 0.32623 * swe_shim_sin(ws.g);
    ws.g = STR * (ws.SWELP - 2.0 * ws.D + 2.5);
    ws.B += 0.29855 * swe_shim_sin(ws.g);
}

fn moon3(ws: *MoonWs) void {
    // terms in ws.T^0
    ws.moonpol[0] = 0.0;
    chewm(&LR, NLR, 4, 1, &ws.moonpol, ws);
    chewm(&MB, NMB, 4, 3, &ws.moonpol, ws);
    ws.l += (((ws.l4 * ws.T + ws.l3) * ws.T + ws.l2) * ws.T + ws.l1) * ws.T * 1.0e-5;
    ws.moonpol[0] = ws.SWELP + ws.l + 1.0e-4 * ws.moonpol[0];
    ws.moonpol[1] = 1.0e-4 * ws.moonpol[1] + ws.B;
    ws.moonpol[2] = 1.0e-4 * ws.moonpol[2] + 385000.52899; // kilometers
}

/// Compute final ecliptic polar coordinates
fn moon4(ws: *MoonWs) void {
    ws.moonpol[2] /= AUNIT / 1000;
    ws.moonpol[0] = STR * mods3600(ws.moonpol[0]);
    ws.moonpol[1] = STR * ws.moonpol[1];
    ws.B = ws.moonpol[1];
}

const CORR_MNODE_JD_T0GREG: f64 = -3063616.5; // 1 jan -13100 greg.
fn corr_mean_node(J: f64) f64 {
    var i: i32 = undefined;
    const J0: f64 = CORR_MNODE_JD_T0GREG;
    const dayscty: f64 = 36524.25; // days per Gregorian century
    if (J < JPL_DE431_START) return 0;
    if (J > JPL_DE431_END) return 0;
    const dJ = J - J0;
    i = @intFromFloat(std.math.floor(dJ / dayscty));
    const dfrac = (dJ - @as(f64, @floatFromInt(i)) * dayscty) / dayscty;
    const dcor0 = mean_node_corr[@intCast(i)];
    const dcor1 = mean_node_corr[@as(usize, @intCast(i)) + 1];
    const dcor = dcor0 + dfrac * (dcor1 - dcor0);
    return dcor;
}

/// mean lunar node (swemmoon.c swi_mean_node)
pub fn swi_mean_node(J: f64, pol: *[3]f64, serr: ?[]u8, ws: *MoonWs) i32 {
    var s: [AS_MAXCH]u8 = undefined;
    ws.T = (J - J2000) / 36525.0;
    ws.T2 = ws.T * ws.T;
    ws.T3 = ws.T * ws.T2;
    ws.T4 = ws.T2 * ws.T2;
    // with elements from swi_moshmoon2(), which are fitted to jpl-ephemeris
    if (J < MOSHNDEPH_START or J > MOSHNDEPH_END) {
        if (serr != null) {
            if (std.fmt.bufPrint(&s, "jd {d:.6} outside mean node range {d:.2} .. {d:.2} ", .{ J, MOSHNDEPH_START, MOSHNDEPH_END })) |str| {
                appendSerr(serr.?, str);
            } else |_| {}
        }
        return ERR;
    }
    mean_elements(ws);
    const dcor = corr_mean_node(J) * 3600;
    // longitude
    pol[0] = lib.swi_mod2PI((ws.SWELP - ws.NF - dcor) * STR);
    // latitude
    pol[1] = 0.0;
    // distance
    pol[2] = MOON_MEAN_DIST / AUNIT;
    return OK;
}

const CORR_MAPOG_JD_T0GREG: f64 = -3063616.5; // 1 jan -13100 greg.
fn corr_mean_apog(J: f64) f64 {
    var i: i32 = undefined;
    const J0: f64 = CORR_MAPOG_JD_T0GREG;
    const dayscty: f64 = 36524.25; // days per Gregorian century
    if (J < JPL_DE431_START) return 0;
    if (J > JPL_DE431_END) return 0;
    const dJ = J - J0;
    i = @intFromFloat(std.math.floor(dJ / dayscty));
    const dfrac = (dJ - @as(f64, @floatFromInt(i)) * dayscty) / dayscty;
    const dcor0 = mean_apsis_corr[@intCast(i)];
    const dcor1 = mean_apsis_corr[@as(usize, @intCast(i)) + 1];
    const dcor = dcor0 + dfrac * (dcor1 - dcor0);
    return dcor;
}

/// mean lunar apogee ('dark moon', 'lilith') (swemmoon.c swi_mean_apog)
pub fn swi_mean_apog(J: f64, pol: *[3]f64, serr: ?[]u8, ws: *MoonWs) i32 {
    var s: [AS_MAXCH]u8 = undefined;
    ws.T = (J - J2000) / 36525.0;
    ws.T2 = ws.T * ws.T;
    ws.T3 = ws.T * ws.T2;
    ws.T4 = ws.T2 * ws.T2;
    // with elements from swi_moshmoon2(), which are fitted to jpl-ephemeris
    if (J < MOSHNDEPH_START or J > MOSHNDEPH_END) {
        if (serr != null) {
            if (std.fmt.bufPrint(&s, "jd {d:.6} outside mean apogee range {d:.2} .. {d:.2} ", .{ J, MOSHNDEPH_START, MOSHNDEPH_END })) |str| {
                appendSerr(serr.?, str);
            } else |_| {}
        }
        return ERR;
    }
    mean_elements(ws);
    pol[0] = lib.swi_mod2PI((ws.SWELP - ws.MP) * STR + PI);
    pol[1] = 0;
    pol[2] = MOON_MEAN_DIST * (1 + MOON_MEAN_ECC) / AUNIT; // apogee
    // (Lilith/Dark Moon comment: apogee is projected onto the ecliptic;
    // barycenter offset is neglected.)
    var dcor = corr_mean_apog(J) * DEGTORAD;
    pol[0] = lib.swi_mod2PI(pol[0] - dcor);
    // apogee is now projected onto ecliptic
    var node = (ws.SWELP - ws.NF) * STR;
    dcor = corr_mean_node(J) * DEGTORAD;
    node = lib.swi_mod2PI(node - dcor);
    pol[0] = lib.swi_mod2PI(pol[0] - node);
    var p3: [3]f64 = .{ pol[0], pol[1], pol[2] };
    lib.swi_polcart(&p3, &p3);
    lib.swi_coortrf(&p3, &p3, -MOON_MEAN_INCL * DEGTORAD);
    lib.swi_cartpol(&p3, &p3);
    pol[0] = lib.swi_mod2PI(p3[0] + node);
    pol[1] = p3[1];
    pol[2] = p3[2];
    return OK;
}

/// Program to step through the perturbation table (swemmoon.c chewm)
fn chewm(pt: []const i16, nlines: usize, nangles: usize, typflg: i32, ans: *[3]f64, ws: *MoonWs) void {
    var idx: usize = 0;
    var i: usize = 0;
    while (i < nlines) : (i += 1) {
        var k1: i32 = 0;
        var sv: f64 = 0.0;
        var cv: f64 = 0.0;
        var m: usize = 0;
        while (m < nangles) : (m += 1) {
            const j = pt[idx];
            idx += 1; // multiple angle factor
            if (j != 0) {
                var k = j;
                if (j < 0) k = -k; // make angle factor > 0
                // sin, cos (k*angle) from lookup table
                var su = ws.ss[m][@as(usize, @intCast(k)) - 1];
                const cu = ws.cc[m][@as(usize, @intCast(k)) - 1];
                if (j < 0) su = -su; // negative angle factor
                if (k1 == 0) {
                    // Set sin, cos of first angle.
                    sv = su;
                    cv = cu;
                    k1 = 1;
                } else {
                    // Combine angles by trigonometry.
                    const ff = su * cv + cu * sv;
                    cv = cu * cv - su * sv;
                    sv = ff;
                }
            }
        }
        // Accumulate
        switch (typflg) {
            // large longitude and radius
            1 => {
                var j = pt[idx];
                idx += 1;
                var k = pt[idx];
                idx += 1;
                ans[0] += (10000.0 * @as(f64, @floatFromInt(j)) + @as(f64, @floatFromInt(k))) * sv;
                j = pt[idx];
                idx += 1;
                k = pt[idx];
                idx += 1;
                if (k != 0) ans[2] += (10000.0 * @as(f64, @floatFromInt(j)) + @as(f64, @floatFromInt(k))) * cv;
            },
            // longitude and radius
            2 => {
                const j = pt[idx];
                idx += 1;
                const k = pt[idx];
                idx += 1;
                ans[0] += @as(f64, @floatFromInt(j)) * sv;
                ans[2] += @as(f64, @floatFromInt(k)) * cv;
            },
            // large latitude
            3 => {
                const j = pt[idx];
                idx += 1;
                const k = pt[idx];
                idx += 1;
                ans[1] += (10000.0 * @as(f64, @floatFromInt(j)) + @as(f64, @floatFromInt(k))) * sv;
            },
            // latitude
            4 => {
                const j = pt[idx];
                idx += 1;
                ans[1] += @as(f64, @floatFromInt(j)) * sv;
            },
            else => {},
        }
    }
}

/// Prepare lookup table of sin and cos ( i*Lj ) for required multiple
/// angles (swemmoon.c sscc)
fn sscc(k: usize, arg: f64, n: usize, ws: *MoonWs) void {
    const su = swe_shim_sin(arg);
    const cu = swe_shim_cos(arg);
    ws.ss[k][0] = su; // sin(L)
    ws.cc[k][0] = cu; // cos(L)
    var sv = 2.0 * su * cu;
    var cv = cu * cu - su * su;
    ws.ss[k][1] = sv; // sin(2L)
    ws.cc[k][1] = cv;
    var i: usize = 2;
    while (i < n) : (i += 1) {
        const s = su * cv + cu * sv;
        cv = cu * cv - su * sv;
        sv = s;
        ws.ss[k][i] = sv; // sin( i+1 L )
        ws.cc[k][i] = cv;
    }
}

/// Calculate geometric coordinates of true interpolated Moon apsides
/// (swemmoon.c swi_intp_apsides)
pub fn swi_intp_apsides(J: f64, pol: *[3]f64, ipli: i32, ws: *MoonWs) i32 {
    var dd: f64 = undefined;
    var rsv: [3]f64 = undefined;
    var niter: i32 = 4;
    var ii: i32 = 1;
    const zMP: f64 = 27.55454988;
    const fNF: f64 = 27.212220817 / zMP;
    const fD: f64 = 29.530588835 / zMP;
    const fLP: f64 = 27.321582 / zMP;
    const fM: f64 = 365.2596359 / zMP;
    const fVe: f64 = 224.7008001 / zMP;
    const fEa: f64 = 365.2563629 / zMP;
    const fMa: f64 = 686.9798519 / zMP;
    const fJu: f64 = 4332.589348 / zMP;
    const fSa: f64 = 10759.22722 / zMP;
    ws.T = (J - J2000) / 36525.0;
    ws.T2 = ws.T * ws.T;
    ws.T4 = ws.T2 * ws.T2;
    mean_elements(ws);
    mean_elements_pl(ws);
    var sNF = ws.NF;
    var sD = ws.D;
    var sLP = ws.SWELP;
    var sMP = ws.MP;
    const sM = ws.M;
    const sVe = ws.Ve;
    const sEa = ws.Ea;
    const sMa = ws.Ma;
    const sJu = ws.Ju;
    const sSa = ws.Sa;
    sNF = mods3600(ws.NF);
    sD = mods3600(ws.D);
    sLP = mods3600(ws.SWELP);
    sMP = mods3600(ws.MP);
    if (ipli == SEI_INTP_PERG) {
        ws.MP = 0.0;
        niter = 5;
    }
    if (ipli == SEI_INTP_APOG) {
        ws.MP = 648000.0;
        niter = 4;
    }
    var cMP: f64 = 0;
    dd = 18000.0;
    var iii: i32 = 0;
    while (iii <= niter) : (iii += 1) {
        const dMP = sMP - ws.MP;
        const mLP = sLP - dMP;
        const mNF = sNF - dMP;
        const mD = sD - dMP;
        var mMP = sMP - dMP;
        ii = 0;
        while (ii <= 2) : (ii += 1) {
            const fi: f64 = @floatFromInt(ii);
            ws.MP = mMP + (fi - 1) * dd;
            ws.NF = mNF + (fi - 1) * dd / fNF;
            ws.D = mD + (fi - 1) * dd / fD;
            ws.SWELP = mLP + (fi - 1) * dd / fLP;
            ws.M = sM + (fi - 1) * dd / fM;
            ws.Ve = sVe + (fi - 1) * dd / fVe;
            ws.Ea = sEa + (fi - 1) * dd / fEa;
            ws.Ma = sMa + (fi - 1) * dd / fMa;
            ws.Ju = sJu + (fi - 1) * dd / fJu;
            ws.Sa = sSa + (fi - 1) * dd / fSa;
            moon1(ws);
            moon2(ws);
            moon3(ws);
            moon4(ws);
            if (ii == 1) {
                var i: usize = 0;
                while (i < 3) : (i += 1)
                    pol[i] = ws.moonpol[i];
            }
            rsv[@intCast(ii)] = ws.moonpol[2];
        }
        cMP = (1.5 * rsv[0] - 2 * rsv[1] + 0.5 * rsv[2]) / (rsv[0] + rsv[2] - 2 * rsv[1]);
        cMP *= dd;
        cMP = cMP - dd;
        mMP += cMP;
        ws.MP = mMP;
        dd /= 10;
    }
    return 0;
}

test {
    std.testing.refAllDecls(@This());
}
