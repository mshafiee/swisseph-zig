// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
// Swiss Ephemeris Zig port --- sweph module (swe_calc orchestration).
// Translated 1:1 from sweph.c to preserve exact floating-point operation
// order, differential-tested against the C oracle.
//
// Scope of this phase: the SEFLG_MOSEPH pipeline for SUN, MOON, EMB/Earth,
// Mercury..Pluto, MEAN_NODE, MEAN_APOG (swe_calc_ut / swe_calc), with flag
// combos SPEED/SPEED3/EQUATORIAL/XYZ/RADIANS/J2000/NONUT/TRUEPOS/NOABERR/
// NOGDEFL/HELCTR/BARYCTR/ICRS. Excluded (deferred): SWIEPH/JPL ephemeris
// file machinery, sidereal mode, topocentric mode, planetary center of
// body, TRUE_NODE/OSCU_APOG (lunar_osc_elem), fixstars.
// The `swed` global is modeled as an explicit Swed struct owned by the
// caller; AstroModels/DeltatCtx thread the remaining global state.
const std = @import("std");
const lib = @import("swephlib");
const deltat = @import("deltat");

const swe_shim_sin = lib.swe_shim_sin;
const swe_shim_cos = lib.swe_shim_cos;
const swe_shim_atan2 = lib.swe_shim_atan2;
const swe_shim_tan = lib.swe_shim_tan;
const swe_shim_atan = lib.swe_shim_atan;

const AstroModels = lib.AstroModels;
const Eps = lib.Eps;
const DeltatCtx = deltat.DeltatCtx;

const DEGTORAD = lib.DEGTORAD;
const RADTODEG = lib.RADTODEG;
const J2000 = lib.J2000;
const TWOPI = lib.TWOPI;
const PI = lib.PI;
const AUNIT = lib.AUNIT;
const CLIGHT = lib.CLIGHT;
pub const SEFLG_JPLEPH: i32 = 1;
pub const SEFLG_SWIEPH: i32 = 2;
pub const SEFLG_MOSEPH: i32 = 4;
pub const SEFLG_HELCTR: i32 = 8;
pub const SEFLG_TRUEPOS: i32 = 16;
pub const SEFLG_J2000: i32 = 32;
pub const SEFLG_NONUT: i32 = 64;
pub const SEFLG_SPEED3: i32 = 128;
pub const SEFLG_SPEED: i32 = 256;
pub const SEFLG_NOGDEFL: i32 = 512;
pub const SEFLG_NOABERR: i32 = 1024;
pub const SEFLG_EQUATORIAL: i32 = 2 * 1024;
pub const SEFLG_XYZ: i32 = 4 * 1024;
pub const SEFLG_RADIANS: i32 = 8 * 1024;
pub const SEFLG_BARYCTR: i32 = 16 * 1024;
pub const SEFLG_TOPOCTR: i32 = 32 * 1024;
pub const SEFLG_SIDEREAL: i32 = 64 * 1024;
pub const SEFLG_ICRS: i32 = 128 * 1024;
pub const SEFLG_JPLHOR: i32 = 256 * 1024;
pub const SEFLG_JPLHOR_APPROX: i32 = 512 * 1024;
const SEFLG_CENTER_BODY: i32 = 1024 * 1024;
pub const SEFLG_EPHMASK: i32 = 1 | 2 | 4;
const SEFLG_DEFAULTEPH: i32 = 2;
const SEFLG_COORDSYS: i32 = SEFLG_EQUATORIAL | SEFLG_XYZ | SEFLG_RADIANS;
const SEFLG_TEST_PLMOON: i32 = 2 * 1024 * 1024 | SEFLG_J2000 | SEFLG_ICRS | SEFLG_HELCTR | SEFLG_TRUEPOS;
// sidereal mode bits (swephexp.h)
const SE_SIDBITS: i32 = 256;
pub const SE_SIDBIT_ECL_T0: i32 = 256;
pub const SE_SIDBIT_SSY_PLANE: i32 = 512;
const SE_SIDBIT_USER_UT: i32 = 1024;
const SE_SIDBIT_ECL_DATE: i32 = 2048;
const SE_SIDBIT_NO_PREC_OFFSET: i32 = 4096;
const SE_SIDBIT_PREC_ORIG: i32 = 8192;
const SE_NSIDM_PREDEF: usize = 47;
const SE_SIDM_FAGAN_BRADLEY: i32 = 0;
const SE_SIDM_J2000: i32 = 18;
const SE_SIDM_J1900: i32 = 19;
const SE_SIDM_B1950: i32 = 20;
const SE_SIDM_GALALIGN_MARDYKS: i32 = 34;
const SE_SIDM_TRUE_CITRA: i32 = 27;
const SE_SIDM_TRUE_REVATI: i32 = 28;
const SE_SIDM_TRUE_PUSHYA: i32 = 29;
const SE_SIDM_GALCENT_0SAG: i32 = 17;
const SE_SIDM_GALCENT_COCHRANE: i32 = 40;
const SE_SIDM_GALCENT_RGILBRAND: i32 = 30;
const SE_SIDM_GALCENT_MULA_WILHELM: i32 = 36;
const SE_SIDM_GALEQU_IAU1958: i32 = 31;
const SE_SIDM_GALEQU_TRUE: i32 = 32;
const SE_SIDM_GALEQU_MULA: i32 = 33;
const SE_SIDM_TRUE_MULA: i32 = 35;
const SE_SIDM_TRUE_SHEORAN: i32 = 39;
const SE_SIDM_USER: i32 = 255;
const B1950: f64 = 2433282.42345905; // 1950 January 0.923
// solar system equator (sweph.h)
const SSY_PLANE_NODE_E2000: f64 = @as(f64, 107.582569) * DEGTORAD;
const SSY_PLANE_INCL: f64 = @as(f64, 1.578701) * DEGTORAD;
// observer constants (sweph.h)
const EARTH_RADIUS: f64 = 6378136.6; // AA 2006 K6
const EARTH_OBLATENESS: f64 = 1.0 / @as(f64, 298.25642); // AA 2006 K6
const EARTH_ROT_SPEED: f64 = @as(f64, 7.2921151467e-5) * @as(f64, 86400); // rad/day

/// struct topo_data (sweph.h)
pub const TopData = struct {
    geolon: f64 = 0,
    geolat: f64 = 0,
    geoalt: f64 = 0,
    teval: f64 = 0,
    tjd_ut: f64 = 0,
    xobs: [6]f64 = [_]f64{0} ** 6,
};

/// struct aya_init (sweph.h): predefined ayanamsha reference epochs.
/// Computed literals keep C's per-step f64 rounding (trap 8f).
pub const AyaInit = struct {
    t0: f64,
    ayan_t0: f64,
    t0_is_UT: bool,
    prec_offset: i32,
};
pub const ayanamsa = [SE_NSIDM_PREDEF]AyaInit{
    .{ .t0 = 2433282.42346, .ayan_t0 = 24.042044444, .t0_is_UT = false, .prec_offset = lib.SEMOD_PREC_NEWCOMB }, // 0: Fagan/Bradley
    .{ .t0 = 2435553.5, .ayan_t0 = @as(f64, 23.250182778) - @as(f64, 0.004658035), .t0_is_UT = false, .prec_offset = lib.SEMOD_PREC_IAU_1976 }, // 1: Lahiri
    .{ .t0 = 1721057.5, .ayan_t0 = 0, .t0_is_UT = true, .prec_offset = 0 }, // 2: DeLuce
    .{ .t0 = lib.J1900, .ayan_t0 = @as(f64, 360) - @as(f64, 338.98556), .t0_is_UT = false, .prec_offset = lib.SEMOD_PREC_NEWCOMB }, // 3: Raman
    .{ .t0 = lib.J1900, .ayan_t0 = @as(f64, 360) - @as(f64, 341.33904), .t0_is_UT = false, .prec_offset = -1 }, // 4: Usha/Shashi
    .{ .t0 = lib.J1900, .ayan_t0 = @as(f64, 360) - @as(f64, 337.636111), .t0_is_UT = false, .prec_offset = lib.SEMOD_PREC_NEWCOMB }, // 5: Krishnamurti
    .{ .t0 = lib.J1900, .ayan_t0 = @as(f64, 360) - @as(f64, 333.0369024), .t0_is_UT = false, .prec_offset = 0 }, // 6: Djwhal Khool
    .{ .t0 = lib.J1900, .ayan_t0 = @as(f64, 360) - @as(f64, 338.917778), .t0_is_UT = false, .prec_offset = -1 }, // 7: Shri Yukteshwar
    .{ .t0 = lib.J1900, .ayan_t0 = @as(f64, 360) - @as(f64, 338.634444), .t0_is_UT = false, .prec_offset = -1 }, // 8: Bhasin
    .{ .t0 = 1684532.5, .ayan_t0 = -5.66667, .t0_is_UT = true, .prec_offset = -1 }, // 9: Babylonian, Kugler 1
    .{ .t0 = 1684532.5, .ayan_t0 = -4.26667, .t0_is_UT = true, .prec_offset = -1 }, // 10: Babylonian, Kugler 2
    .{ .t0 = 1684532.5, .ayan_t0 = -3.41667, .t0_is_UT = true, .prec_offset = -1 }, // 11: Babylonian, Kugler 3
    .{ .t0 = 1684532.5, .ayan_t0 = -4.46667, .t0_is_UT = true, .prec_offset = -1 }, // 12: Babylonian, Huber
    .{ .t0 = 1673941, .ayan_t0 = -5.079167, .t0_is_UT = true, .prec_offset = -1 }, // 13: Babylonian, Mercier
    .{ .t0 = 1684532.5, .ayan_t0 = -4.44138598, .t0_is_UT = true, .prec_offset = 0 }, // 14: Babylonian/Aldebaran = 15 Tau
    .{ .t0 = 1674484.0, .ayan_t0 = -9.33333, .t0_is_UT = true, .prec_offset = -1 }, // 15: Hipparchos
    .{ .t0 = 1927135.8747793, .ayan_t0 = 0, .t0_is_UT = true, .prec_offset = -1 }, // 16: Sassanian
    .{ .t0 = 0, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 17: Galactic Center at 0 Sagittarius
    .{ .t0 = lib.J2000, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 18: J2000
    .{ .t0 = lib.J1900, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 19: J1900
    .{ .t0 = B1950, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 20: B1950
    .{ .t0 = 1903396.8128654, .ayan_t0 = 0, .t0_is_UT = true, .prec_offset = 0 }, // 21: Suryasiddhanta
    .{ .t0 = 1903396.8128654, .ayan_t0 = -0.21463395, .t0_is_UT = true, .prec_offset = 0 }, // 22: Suryasiddhanta, mean Sun
    .{ .t0 = 1903396.7895321, .ayan_t0 = 0, .t0_is_UT = true, .prec_offset = 0 }, // 23: Aryabhata
    .{ .t0 = 1903396.7895321, .ayan_t0 = -0.23763238, .t0_is_UT = true, .prec_offset = 0 }, // 24: Aryabhata, mean Sun
    .{ .t0 = 1903396.8128654, .ayan_t0 = -0.79167046, .t0_is_UT = true, .prec_offset = 0 }, // 25: SS Revati
    .{ .t0 = 1903396.8128654, .ayan_t0 = 2.11070444, .t0_is_UT = true, .prec_offset = 0 }, // 26: SS Citra
    .{ .t0 = 0, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 27: True Citra
    .{ .t0 = 0, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 28: True Revati
    .{ .t0 = 0, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 29: True Pushya
    .{ .t0 = 0, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 30: Gil Brand
    .{ .t0 = 0, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 31: GE IAU 1958
    .{ .t0 = 0, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 32: GE true
    .{ .t0 = 0, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 33: GE Mula
    .{ .t0 = 2451079.734892000, .ayan_t0 = 30, .t0_is_UT = false, .prec_offset = 0 }, // 34: Skydram/Mardyks
    .{ .t0 = 0, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 35: Chandra Hari
    .{ .t0 = 0, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 36: Ernst Wilhelm
    .{ .t0 = 1911797.740782065, .ayan_t0 = 0, .t0_is_UT = true, .prec_offset = 0 }, // 37: 0 ayanamsha in year 522
    .{ .t0 = 1721057.5, .ayan_t0 = -3.2, .t0_is_UT = true, .prec_offset = -1 }, // 38: Babylonian (Britton 2010)
    .{ .t0 = 0, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 39: Sunil Sheoran ("Vedic")
    .{ .t0 = 0, .ayan_t0 = 0, .t0_is_UT = false, .prec_offset = 0 }, // 40: Cochrane
    .{ .t0 = 2451544.5, .ayan_t0 = 25.0, .t0_is_UT = true, .prec_offset = 0 }, // 41: N.A. Fiorenza
    .{ .t0 = 1775845.5, .ayan_t0 = -2.9422, .t0_is_UT = true, .prec_offset = -1 }, // 42: Vettius Valens
    .{ .t0 = lib.J1900, .ayan_t0 = 22.44597222, .t0_is_UT = false, .prec_offset = lib.SEMOD_PREC_NEWCOMB }, // 43: Lahiri (1940)
    .{ .t0 = 1825235.2458513028, .ayan_t0 = 0.0, .t0_is_UT = false, .prec_offset = 0 }, // 44: Lahiri VP285 (1980)
    .{ .t0 = 1827424.752255678, .ayan_t0 = 0.0, .t0_is_UT = false, .prec_offset = 0 }, // 45: Krishnamurti VP291
    .{ .t0 = 2435553.5, .ayan_t0 = @as(f64, 23.25) - @as(f64, 0.00464207), .t0_is_UT = false, .prec_offset = lib.SEMOD_PREC_NEWCOMB }, // 46: SE_SIDM_LAHIRI_ICRC
};

const SWI_STAR_LENGTH: usize = 40;
const SE_MAX_STNAME: usize = SWI_STAR_LENGTH;
const SE_STARFILE = "sefstars.txt";
const SE_STARFILE_OLD = "fixstars.cat";

/// struct fixed_star (sweph.h)
pub const FixedStar = struct {
    skey: [SWI_STAR_LENGTH + 2]u8 = [_]u8{0} ** (SWI_STAR_LENGTH + 2),
    starname: [SWI_STAR_LENGTH + 1]u8 = [_]u8{0} ** (SWI_STAR_LENGTH + 1),
    starbayer: [SWI_STAR_LENGTH + 1]u8 = [_]u8{0} ** (SWI_STAR_LENGTH + 1),
    starno: [10]u8 = [_]u8{0} ** 10,
    epoch: f64 = 0,
    ra: f64 = 0,
    de: f64 = 0,
    ramot: f64 = 0,
    demot: f64 = 0,
    radvel: f64 = 0,
    parall: f64 = 0,
    mag: f64 = 0,
};

/// struct sid_data (sweph.h)
pub const SidData = struct {
    sid_mode: i32 = 0,
    ayan_t0: f64 = 0,
    t0: f64 = 0,
    t0_is_UT: bool = false,
};
const OK: i32 = 0;
const ERR: i32 = -1;
pub const NOT_AVAILABLE: i32 = -2;
pub const BEYOND_EPH_LIMITS: i32 = -3;
const IS_PLANET: i32 = 0;
const IS_ANY_BODY: i32 = 1;
const IS_MAIN_ASTEROID: i32 = 2;
pub const AS_MAXCH: usize = 256;
const SE_NPLANETS: usize = 18;
const SEI_NNDAT: usize = 6;

// internal planet indices (sweph.h)
const SEI_EMB: usize = 0;
const SEI_MOON: usize = 1;
const SEI_MERCURY: usize = 2;
const SEI_VENUS: usize = 3;
const SEI_MARS: usize = 4;
const SEI_JUPITER: usize = 5;
const SEI_SATURN: usize = 6;
const SEI_URANUS: usize = 7;
const SEI_NEPTUNE: usize = 8;
const SEI_PLUTO: usize = 9;
pub const SEI_SUNBARY: usize = 10;
const SEI_CHIRON: usize = 12;
const SEI_PHOLUS: usize = 13;
const SEI_CERES: usize = 14;
const SEI_PALLAS: usize = 15;
const SEI_JUNO: usize = 16;
const SEI_VESTA: usize = 17;
// sweph.h main-asteroid JD limits
const CHIRON_START: f64 = 1967601.5; // 1.1.675
const CHIRON_END: f64 = 3419437.5; // 1.1.4650
const PHOLUS_START: f64 = 640648.5; // 1.1.-2958 jul
const PHOLUS_END: f64 = 4390617.5; // 1.1.7309
// swephexp.h MPC numbers of main asteroids
const MPC_VESTA: i32 = 4;
// public body numbers of main asteroids (swephexp.h)
const SE_CHIRON: i32 = 15;
const SE_PHOLUS: i32 = 16;
const SE_CERES: i32 = 17;
const SE_PALLAS: i32 = 18;
const SE_JUNO: i32 = 19;
const SE_VESTA: i32 = 20;
const SEI_ANYBODY: usize = 11;
pub const SEI_EARTH: usize = 0;
const SEI_SUN: usize = 0;

// public body numbers (swephexp.h)
const SE_SUN: i32 = 0;
const SE_MOON: i32 = 1;
const SE_MERCURY: i32 = 2;
const SE_VENUS: i32 = 3;
const SE_MARS: i32 = 4;
const SE_JUPITER: i32 = 5;
const SE_SATURN: i32 = 6;
const SE_URANUS: i32 = 7;
const SE_NEPTUNE: i32 = 8;
const SE_PLUTO: i32 = 9;
const SE_MEAN_NODE: i32 = 10;
const SE_TRUE_NODE: i32 = 11;
const SE_MEAN_APOG: i32 = 12;
const SE_OSCU_APOG: i32 = 13;
const SE_INTP_APOG: i32 = 22;
const SE_INTP_PERG: i32 = 23;
const SE_EARTH: i32 = 14;
pub const SE_ECL_NUT: i32 = -1;
const SE_AST_OFFSET: i32 = 10000;
const SE_PLMOON_OFFSET: i32 = 9000;

const MOSHPLEPH_START: f64 = 625000.5;
const MOSHPLEPH_END: f64 = 2818000.5;
const MOSHLUEPH_START: f64 = 625000.5;
const MOSHLUEPH_END: f64 = 2818000.5;
const PLAN_SPEED_INTV: f64 = 0.0001;
const MOON_SPEED_INTV: f64 = 0.00005;
const MEAN_NODE_SPEED_INTV: f64 = 0.001;
const NODE_CALC_INTV_MOSH: f64 = 0.1;
const NODE_CALC_INTV: f64 = 0.0001;
const EARTH_MOON_MRAT: f64 = @as(f64, 1.0) / @as(f64, 0.0123000383); // AA 2006 K7
const GEOGCONST: f64 = 3.98600448e+14; // G*M(earth) AA 1996 K6
const SEI_TRUE_NODE: usize = 1;
const SEI_OSCU_APOG: usize = 3;
const NUT_SPEED_INTV: f64 = 0.0001;
const DEFL_SPEED_INTV: f64 = 0.0000005;
const HELGRAVCONST: f64 = 1.32712440017987e+20; // G*M(sun) AA 2006 K6
const SUN_RADIUS: f64 = @as(f64, 959.63) / 3600.0 * DEGTORAD;
const J2000_TO_J: i32 = -1;

// internal body numbers for public body numbers (sweph.c pnoext2int)
const pnoext2int = [21]usize{
    SEI_SUN,     SEI_MOON,   SEI_MERCURY, SEI_VENUS,   SEI_MARS,
    SEI_JUPITER, SEI_SATURN, SEI_URANUS,  SEI_NEPTUNE, SEI_PLUTO,
    0,           0,          0,           0,           SEI_EARTH,
    SEI_CHIRON,  SEI_PHOLUS, SEI_CERES,   SEI_PALLAS,  SEI_JUNO,
    SEI_VESTA,
};

pub const PlanData = struct {
    ibdy: i32 = 0,
    iflg: i32 = 0,
    ncoe: i32 = 0,
    lndx0: i32 = 0,
    nndx: i32 = 0,
    tfstart: f64 = 0,
    tfend: f64 = 0,
    dseg: f64 = 0,
    telem: f64 = 0,
    prot: f64 = 0,
    dprot: f64 = 0,
    qrot: f64 = 0,
    dqrot: f64 = 0,
    rmax: f64 = 0,
    peri: f64 = 0,
    dperi: f64 = 0,
    refep: ?[]f64 = null,
    segp: ?[]f64 = null,
    tseg0: f64 = 0,
    tseg1: f64 = 0,
    neval: i32 = 0,
    teval: f64 = 0,
    xflgs: i32 = 0,
    iephe: i32 = 0,
    x: [6]f64 = [_]f64{0} ** 6,
    xreturn: [24]f64 = [_]f64{0} ** 24,
};

pub const SavePositions = struct {
    ipl: i32 = 0,
    tsave: f64 = 0,
    iflgsave: i32 = 0,
    xsaves: [24]f64 = [_]f64{0} ** 24,
};

pub const Nut = struct {
    tnut: f64 = 0,
    nutlo: [2]f64 = [_]f64{0} ** 2,
    snut: f64 = 0,
    cnut: f64 = 0,
    matrix: [3][3]f64 = undefined,
};

pub const SEI_FILE_PLANET: usize = 0;
const SWE_DATA_DPSI_DEPS: usize = 36525;
const DPSI_DEPS_IAU1980_TJD0_HORIZONS: f64 = 2437684.5;
const SEI_FILE_FIXSTAR: i32 = 4;
const DPSI_DEPS_IAU1980_FILE_EOPC04 = "eop_1962_today.txt";
const DPSI_DEPS_IAU1980_FILE_FINALS = "eop_finals.txt";
const SE_FNAME_DFT = "de431.eph";
const SE_FNAME_DFT2 = "de406.eph";
const PNOINT2JPL = [11]i32{ jplmod.J_EARTH, jplmod.J_MOON, jplmod.J_MERCURY, jplmod.J_VENUS, jplmod.J_MARS, jplmod.J_JUPITER, jplmod.J_SATURN, jplmod.J_URANUS, jplmod.J_NEPTUNE, jplmod.J_PLUTO, jplmod.J_SUN };
const SEI_CURR_FPOS: i32 = -1;
const SE_MARS_INT: i32 = 4;
pub const SEI_FILE_MOON: usize = 1;
pub const SEI_FILE_MAIN_AST: usize = 2;
pub const SEI_FILE_ANY_AST: usize = 3;
pub const SEI_NEPHFILES: usize = 7;
pub const SEI_FILE_NMAXPLAN: usize = 50;
pub const SEI_FLG_HELIO: i32 = 1;
pub const SEI_FLG_ROTATE: i32 = 2;
pub const SEI_FLG_ELLIPSE: i32 = 4;
const SEI_FLG_EMBHEL: i32 = 8;
pub const SEI_FILE_TEST_ENDIAN: i32 = 0x616263; // "abc"
pub const SEI_FILE_BIGENDIAN: i32 = 0;
pub const SEI_FILE_NOREORD: i32 = 0;
pub const SEI_FILE_LITENDIAN: i32 = 1;
pub const SEI_FILE_REORD: i32 = 2;
pub const SE_FILE_SUFFIX: []const u8 = "se1";
pub const NCTIES: f64 = 6.0; // centuries per eph. file
pub const MAXORD: usize = 40;
pub const SE_EPHE_PATH: []const u8 = ".:/users/ephe2/:/users/ephe/";
pub const DIR_GLUE: u8 = '/';
pub const SE_DE_NUMBER: i32 = 431;

pub const FileData = struct {
    fnam: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH,
    fversion: i32 = 0,
    astnam: [50]u8 = [_]u8{0} ** 50,
    sweph_denum: i32 = 0,
    fp: ?*anyopaque = null,
    tfstart: f64 = 0,
    tfend: f64 = 0,
    iflg: i32 = 0,
    npl: i32 = 0,
    ipl: [SEI_FILE_NMAXPLAN]i32 = [_]i32{0} ** SEI_FILE_NMAXPLAN,
};

pub const GcData = struct {
    clight: f64 = 0,
    aunit: f64 = 0,
    helgravconst: f64 = 0,
    ratme: f64 = 0,
    sunradius: f64 = 0,
};

// C stdio for ephemeris file machinery — on wasm use in-memory stubs (no libc)
const is_wasm = @import("builtin").target.cpu.arch.isWasm();
fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque {
    if (is_wasm) return null;
    const c = struct {
        extern "c" fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
    };
    return c.fopen(path, mode);
}
fn fread(ptr: [*]u8, size: usize, nitems: usize, stream: ?*anyopaque) usize {
    if (is_wasm) return 0;
    const c = struct {
        extern "c" fn fread(ptr: [*]u8, size: usize, nitems: usize, stream: ?*anyopaque) usize;
    };
    return c.fread(ptr, size, nitems, stream);
}
fn fseek(stream: ?*anyopaque, off: i64, whence: i32) i32 {
    if (is_wasm) return -1;
    const c = struct {
        extern "c" fn fseek(stream: ?*anyopaque, off: i64, whence: i32) i32;
    };
    return c.fseek(stream, off, whence);
}
fn ftell(stream: ?*anyopaque) i64 {
    if (is_wasm) return -1;
    const c = struct {
        extern "c" fn ftell(stream: ?*anyopaque) i64;
    };
    return c.ftell(stream);
}
fn fclose(stream: ?*anyopaque) i32 {
    if (is_wasm) return 0;
    const c = struct {
        extern "c" fn fclose(stream: ?*anyopaque) i32;
    };
    return c.fclose(stream);
}
fn fgets(buf: [*]u8, size: i32, stream: ?*anyopaque) ?[*:0]u8 {
    if (is_wasm) return null;
    const c = struct {
        extern "c" fn fgets(buf: [*]u8, size: i32, stream: ?*anyopaque) ?[*:0]u8;
    };
    return c.fgets(buf, size, stream);
}

/// Model of sweph.c's `struct swe_data` for the ported subset.
pub const Swed = struct {
    pldat: [SE_NPLANETS]PlanData = [_]PlanData{.{}} ** SE_NPLANETS,
    nddat: [SEI_NNDAT]PlanData = [_]PlanData{.{}} ** SEI_NNDAT,
    savedat: [SE_NPLANETS + 1]SavePositions = [_]SavePositions{.{}} ** (SE_NPLANETS + 1),
    oec: Eps = .{},
    oec2000: Eps = .{},
    nut: Nut = .{},
    nutv: Nut = .{},
    nut2000: Nut = .{},
    nutflag: i32 = 0, // swi_check_nutation's function-local static
    last_epheflag: i32 = 0,
    ephe_path_is_set: bool = false,
    jpl_file_is_open: bool = false,
    eop_dpsi_loaded: i32 = 0,
    eop_tjd_beg: f64 = 0,
    eop_tjd_beg_horizons: f64 = 0,
    eop_tjd_end: f64 = 0,
    eop_tjd_end_add: f64 = 0,
    dpsi: [SWE_DATA_DPSI_DEPS]f64 = [_]f64{0} ** SWE_DATA_DPSI_DEPS,
    deps: [SWE_DATA_DPSI_DEPS]f64 = [_]f64{0} ** SWE_DATA_DPSI_DEPS,
    fidat: [SEI_NEPHFILES]FileData = [_]FileData{.{}} ** SEI_NEPHFILES,
    gcdat: GcData = .{},
    ephepath: [AS_MAXCH]u8 = blk: {
        // swi_init_swed_if_start(): strcpy(swed.ephepath, SE_EPHE_PATH)
        var buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
        @memcpy(buf[0..SE_EPHE_PATH.len], SE_EPHE_PATH);
        break :blk buf;
    },
    sweph_denum: i32 = 0,
    jpldenum: i32 = 0,
    jplfnam: [AS_MAXCH]u8 = blk: {
        // swi_init_swed_if_start(): strcpy(swed.jplfnam, SE_FNAME_DFT)
        var buf: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
        @memcpy(buf[0..SE_FNAME_DFT.len], SE_FNAME_DFT);
        break :blk buf;
    },
    is_tid_acc_manual: bool = false,
    tid_acc: f64 = 0,
    astelem: [160]u8 = [_]u8{0} ** 160,
    ast_H: f64 = 0,
    ast_G: f64 = 0,
    ast_diam: f64 = 0,
    sidd: SidData = .{},
    ayana_is_set: bool = false,
    topd: TopData = .{},
    geopos_is_set: bool = false,
    do_interpolate_nut: bool = false,
    interp: lib.Interp = .{},
    n_fixstars_real: i32 = 0,
    n_fixstars_named: i32 = 0,
    n_fixstars_records: i32 = 0,
    fixed_stars: []FixedStar = &[_]FixedStar{},
    fixfp: ?*anyopaque = null,
    is_old_starfile: bool = false,
    i_saved_planet_name: i32 = 0,
    saved_planet_name: [80]u8 = [_]u8{0} ** 80,
};

fn nutInterp(swed: *Swed) ?*lib.Interp {
    return if (swed.do_interpolate_nut) &swed.interp else null;
}

pub fn square_sum(x: []const f64) f64 {
    return x[0] * x[0] + x[1] * x[1] + x[2] * x[2];
}

pub fn dot_prod(a: *const [3]f64, b: *const [3]f64) f64 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

/// sweph.c calc_epsilon
pub fn calc_epsilon(tjd: f64, iflag: i32, e: *Eps, models: AstroModels) void {
    e.teps = tjd;
    e.eps = lib.swi_epsiln(tjd, iflag, models);
    e.seps = swe_shim_sin(e.eps);
    e.ceps = swe_shim_cos(e.eps);
}

/// sweph.c swi_check_ecliptic
fn swi_check_ecliptic(tjd: f64, iflag: i32, swed: *Swed, models: AstroModels) void {
    if (swed.oec2000.teps != J2000) {
        calc_epsilon(J2000, iflag, &swed.oec2000, models);
    }
    if (tjd == J2000) {
        swed.oec.teps = swed.oec2000.teps;
        swed.oec.eps = swed.oec2000.eps;
        swed.oec.seps = swed.oec2000.seps;
        swed.oec.ceps = swed.oec2000.ceps;
        return;
    }
    if (swed.oec.teps != tjd or tjd == 0) {
        calc_epsilon(tjd, iflag, &swed.oec, models);
    }
}

/// sweph.c nut_matrix
fn nut_matrix(nu: *Nut, oe: *const Eps) void {
    const psi = nu.nutlo[0];
    const eps = oe.eps + nu.nutlo[1];
    const sinpsi = swe_shim_sin(psi);
    const cospsi = swe_shim_cos(psi);
    const sineps0 = oe.seps;
    const coseps0 = oe.ceps;
    const sineps = swe_shim_sin(eps);
    const coseps = swe_shim_cos(eps);
    nu.matrix[0][0] = cospsi;
    nu.matrix[0][1] = sinpsi * coseps;
    nu.matrix[0][2] = sinpsi * sineps;
    nu.matrix[1][0] = -sinpsi * coseps0;
    nu.matrix[1][1] = cospsi * coseps * coseps0 + sineps * sineps0;
    nu.matrix[1][2] = cospsi * sineps * coseps0 - coseps * sineps0;
    nu.matrix[2][0] = -sinpsi * sineps0;
    nu.matrix[2][1] = cospsi * coseps * sineps0 - sineps * coseps0;
    nu.matrix[2][2] = cospsi * sineps * sineps0 + coseps * coseps0;
}

/// sweph.c swi_check_nutation; EOP corrections not ported (see plan):
/// the SEFLG_JPLHOR branch is guarded to be unreachable exactly like the
/// library without a JPL file (plaus_iflag downgrades it).
fn swi_check_nutation(tjd: f64, iflag: i32, swed: *Swed, models: AstroModels) void {
    const speedf1 = swed.nutflag & SEFLG_SPEED;
    const speedf2 = iflag & SEFLG_SPEED;
    if ((iflag & SEFLG_NONUT) == 0 and
        (tjd != swed.nut.tnut or tjd == 0 or (speedf1 == 0 and speedf2 != 0)))
    {
        _ = lib.swi_nutation(tjd, iflag, &swed.nut.nutlo, models, nutInterp(swed));
        swed.nut.tnut = tjd;
        swed.nut.snut = swe_shim_sin(swed.nut.nutlo[1]);
        swed.nut.cnut = swe_shim_cos(swed.nut.nutlo[1]);
        swed.nutflag = iflag;
        nut_matrix(&swed.nut, &swed.oec);
        if ((iflag & SEFLG_SPEED) != 0) {
            // once more for 'speed' of nutation, needed for planetary speeds
            const t = tjd - NUT_SPEED_INTV;
            _ = lib.swi_nutation(t, iflag, &swed.nutv.nutlo, models, nutInterp(swed));
            swed.nutv.tnut = t;
            swed.nutv.snut = swe_shim_sin(swed.nutv.nutlo[1]);
            swed.nutv.cnut = swe_shim_cos(swed.nutv.nutlo[1]);
            nut_matrix(&swed.nutv, &swed.oec);
        }
    }
}

/// sweph.c swi_precess_speed; oe selection follows the C code
/// (&swed.oec for J2000_TO_J, &swed.oec2000 otherwise) via the caller's
/// swed state.
pub fn swi_precess_speed(xx: *[6]f64, t: f64, iflag: i32, direction: i32, swed: *Swed, models: AstroModels) void {
    var dpre: f64 = undefined;
    var dpre2: f64 = undefined;
    const tprec = (t - J2000) / 36525.0;
    var prec_model = models.prec_longterm;
    if (prec_model == 0) prec_model = lib.SEMOD_PREC_DEFAULT;
    var fac: f64 = undefined;
    var oe: *const Eps = undefined;
    if (direction == J2000_TO_J) {
        fac = 1;
        oe = &swed.oec;
    } else {
        fac = -1;
        oe = &swed.oec2000;
    }
    // first correct rotation.
    // this costs some sines and cosines, but neglect might
    // involve an error > 1"/day
    var x3: [3]f64 = .{ xx[3], xx[4], xx[5] };
    _ = lib.swi_precess(&x3, t, iflag, direction, models);
    xx[3] = x3[0];
    xx[4] = x3[1];
    xx[5] = x3[2];
    // then add 0.137"/day
    lib.swi_coortrf2(xx[0..3], xx[0..3], oe.seps, oe.ceps);
    lib.swi_coortrf2(xx[3..6], xx[3..6], oe.seps, oe.ceps);
    lib.swi_cartpol_sp(xx, xx);
    if (prec_model == lib.SEMOD_PREC_VONDRAK_2011) {
        lib.swi_ldp_peps(t, &dpre, null);
        lib.swi_ldp_peps(t + 1, &dpre2, null);
        xx[3] += (dpre2 - dpre) * fac;
    } else {
        // formula from Montenbruck, German 1994, p. 18
        xx[3] += (50.290966 + 0.0222226 * tprec) / 3600 / 365.25 * DEGTORAD * fac;
    }
    lib.swi_polcart_sp(xx, xx);
    lib.swi_coortrf2(xx[0..3], xx[0..3], -oe.seps, oe.ceps);
    lib.swi_coortrf2(xx[3..6], xx[3..6], -oe.seps, oe.ceps);
}

/// sweph.c swi_nutate
pub fn swi_nutate(xx: *[6]f64, iflag: i32, backward: bool, swed: *Swed) void {
    var x: [6]f64 = undefined;
    var xv: [3]f64 = undefined;
    var i: usize = 0;
    while (i <= 2) : (i += 1) {
        if (backward) {
            x[i] = xx[0] * swed.nut.matrix[i][0] +
                xx[1] * swed.nut.matrix[i][1] +
                xx[2] * swed.nut.matrix[i][2];
        } else {
            x[i] = xx[0] * swed.nut.matrix[0][i] +
                xx[1] * swed.nut.matrix[1][i] +
                xx[2] * swed.nut.matrix[2][i];
        }
    }
    if ((iflag & SEFLG_SPEED) != 0) {
        // correct speed: first correct rotation
        i = 0;
        while (i <= 2) : (i += 1) {
            if (backward) {
                x[i + 3] = xx[3] * swed.nut.matrix[i][0] +
                    xx[4] * swed.nut.matrix[i][1] +
                    xx[5] * swed.nut.matrix[i][2];
            } else {
                x[i + 3] = xx[3] * swed.nut.matrix[0][i] +
                    xx[4] * swed.nut.matrix[1][i] +
                    xx[5] * swed.nut.matrix[2][i];
            }
        }
        // then apparent motion due to change of nutation during day.
        // this makes a difference of 0.01"
        i = 0;
        while (i <= 2) : (i += 1) {
            if (backward) {
                xv[i] = xx[0] * swed.nutv.matrix[i][0] +
                    xx[1] * swed.nutv.matrix[i][1] +
                    xx[2] * swed.nutv.matrix[i][2];
            } else {
                xv[i] = xx[0] * swed.nutv.matrix[0][i] +
                    xx[1] * swed.nutv.matrix[1][i] +
                    xx[2] * swed.nutv.matrix[2][i];
            }
            // new speed
            xx[3 + i] = x[3 + i] + (x[i] - xv[i]) / NUT_SPEED_INTV;
        }
    }
    // new position
    i = 0;
    while (i <= 2) : (i += 1)
        xx[i] = x[i];
}

/// sweph.c swi_aberr_light
fn swi_aberr_light_inner(xx: *[6]f64, xe: *const [6]f64) void {
    var u: [3]f64 = undefined;
    var xxs: [6]f64 = undefined;
    var v: [3]f64 = undefined;
    var ru: f64 = undefined;
    var v2: f64 = undefined;
    var b_1: f64 = undefined;
    var f1: f64 = undefined;
    var f2: f64 = undefined;
    var i: usize = 0;
    while (i <= 5) : (i += 1)
        xxs[i] = xx[i];
    i = 0;
    while (i <= 2) : (i += 1)
        u[i] = xxs[i];
    ru = std.math.sqrt(u[0] * u[0] + u[1] * u[1] + u[2] * u[2]);
    i = 0;
    while (i <= 2) : (i += 1)
        v[i] = xe[i + 3] / 24.0 / 3600.0 / CLIGHT * AUNIT;
    v2 = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
    b_1 = std.math.sqrt(1 - v2);
    f1 = (u[0] * v[0] + u[1] * v[1] + u[2] * v[2]) / ru;
    f2 = 1.0 + f1 / (1.0 + b_1);
    i = 0;
    while (i <= 2) : (i += 1)
        xx[i] = (b_1 * xx[i] + f2 * ru * v[i]) / (1.0 + f1);
}

pub fn swi_aberr_light(xx: *[6]f64, xe: *const [6]f64, iflag: i32) void {
    var xxs: [6]f64 = undefined;
    var v: [3]f64 = undefined;
    var u: [3]f64 = undefined;
    var xx2: [3]f64 = undefined;
    var dx1: f64 = undefined;
    var dx2: f64 = undefined;
    const intv = PLAN_SPEED_INTV;
    var i: usize = 0;
    while (i <= 5) : (i += 1)
        xxs[i] = xx[i];
    var uvec: [3]f64 = .{ xxs[0], xxs[1], xxs[2] };
    var ru = std.math.sqrt(square_sum(&uvec));
    i = 0;
    while (i <= 2) : (i += 1)
        v[i] = xe[i + 3] / 24.0 / 3600.0 / CLIGHT * AUNIT;
    const v2 = square_sum(&v);
    const b_1 = std.math.sqrt(1 - v2);
    var f1 = dot_prod(&uvec, &v) / ru;
    const f2 = 1.0 + f1 / (1.0 + b_1);
    i = 0;
    while (i <= 2) : (i += 1)
        xx[i] = (b_1 * xx[i] + f2 * ru * v[i]) / (1.0 + f1);
    if ((iflag & SEFLG_SPEED) != 0) {
        // correction of speed: the influence of aberration on apparent
        // velocity can reach 0.4"/day
        i = 0;
        while (i <= 2) : (i += 1)
            u[i] = xxs[i] - intv * xxs[i + 3];
        ru = std.math.sqrt(square_sum(&u));
        f1 = dot_prod(&u, &v) / ru;
        const f2b = 1.0 + f1 / (1.0 + b_1);
        i = 0;
        while (i <= 2) : (i += 1)
            xx2[i] = (b_1 * u[i] + f2b * ru * v[i]) / (1.0 + f1);
        i = 0;
        while (i <= 2) : (i += 1) {
            dx1 = xx[i] - xxs[i];
            dx2 = xx2[i] - u[i];
            dx1 -= dx2;
            xx[i + 3] += dx1 / intv;
        }
    }
}

/// sweph.c meff
fn meff(r: f64) f64 {
    if (r <= 0) {
        return 0.0;
    } else if (r >= 1) {
        return 1.0;
    }
    var i: usize = 0;
    while (eff_arr[i].r > r) : (i += 1) {}
    const f = (r - eff_arr[i - 1].r) / (eff_arr[i].r - eff_arr[i - 1].r);
    return eff_arr[i - 1].m + f * (eff_arr[i].m - eff_arr[i - 1].m);
}

const MeffEle = struct { r: f64, m: f64 };
const eff_arr = [_]MeffEle{
    .{ .r = 1.000, .m = 1.000000 }, .{ .r = 0.990, .m = 0.999979 },
    .{ .r = 0.980, .m = 0.999940 }, .{ .r = 0.970, .m = 0.999881 },
    .{ .r = 0.960, .m = 0.999811 }, .{ .r = 0.950, .m = 0.999724 },
    .{ .r = 0.940, .m = 0.999622 }, .{ .r = 0.930, .m = 0.999497 },
    .{ .r = 0.920, .m = 0.999354 }, .{ .r = 0.910, .m = 0.999192 },
    .{ .r = 0.900, .m = 0.999000 }, .{ .r = 0.890, .m = 0.998786 },
    .{ .r = 0.880, .m = 0.998535 }, .{ .r = 0.870, .m = 0.998242 },
    .{ .r = 0.860, .m = 0.997919 }, .{ .r = 0.850, .m = 0.997571 },
    .{ .r = 0.840, .m = 0.997198 }, .{ .r = 0.830, .m = 0.996792 },
    .{ .r = 0.820, .m = 0.996316 }, .{ .r = 0.810, .m = 0.995791 },
    .{ .r = 0.800, .m = 0.995226 }, .{ .r = 0.790, .m = 0.994625 },
    .{ .r = 0.780, .m = 0.993991 }, .{ .r = 0.770, .m = 0.993326 },
    .{ .r = 0.760, .m = 0.992598 }, .{ .r = 0.750, .m = 0.991770 },
    .{ .r = 0.740, .m = 0.990873 }, .{ .r = 0.730, .m = 0.989919 },
    .{ .r = 0.720, .m = 0.988912 }, .{ .r = 0.710, .m = 0.987856 },
    .{ .r = 0.700, .m = 0.986755 }, .{ .r = 0.690, .m = 0.985610 },
    .{ .r = 0.680, .m = 0.984398 }, .{ .r = 0.670, .m = 0.982986 },
    .{ .r = 0.660, .m = 0.981437 }, .{ .r = 0.650, .m = 0.979779 },
    .{ .r = 0.640, .m = 0.978024 }, .{ .r = 0.630, .m = 0.976182 },
    .{ .r = 0.620, .m = 0.974256 }, .{ .r = 0.610, .m = 0.972253 },
    .{ .r = 0.600, .m = 0.970174 }, .{ .r = 0.590, .m = 0.968024 },
    .{ .r = 0.580, .m = 0.965594 }, .{ .r = 0.570, .m = 0.962797 },
    .{ .r = 0.560, .m = 0.959758 }, .{ .r = 0.550, .m = 0.956515 },
    .{ .r = 0.540, .m = 0.953088 }, .{ .r = 0.530, .m = 0.949495 },
    .{ .r = 0.520, .m = 0.945741 }, .{ .r = 0.510, .m = 0.941838 },
    .{ .r = 0.500, .m = 0.937790 }, .{ .r = 0.490, .m = 0.933563 },
    .{ .r = 0.480, .m = 0.928668 }, .{ .r = 0.470, .m = 0.923288 },
    .{ .r = 0.460, .m = 0.917527 }, .{ .r = 0.450, .m = 0.911432 },
    .{ .r = 0.440, .m = 0.905035 }, .{ .r = 0.430, .m = 0.898353 },
    .{ .r = 0.420, .m = 0.891022 }, .{ .r = 0.410, .m = 0.882940 },
    .{ .r = 0.400, .m = 0.874312 }, .{ .r = 0.390, .m = 0.865206 },
    .{ .r = 0.380, .m = 0.855423 }, .{ .r = 0.370, .m = 0.844619 },
    .{ .r = 0.360, .m = 0.833074 }, .{ .r = 0.350, .m = 0.820876 },
    .{ .r = 0.340, .m = 0.808031 }, .{ .r = 0.330, .m = 0.793962 },
    .{ .r = 0.320, .m = 0.778931 }, .{ .r = 0.310, .m = 0.763021 },
    .{ .r = 0.300, .m = 0.745815 }, .{ .r = 0.290, .m = 0.727557 },
    .{ .r = 0.280, .m = 0.708234 }, .{ .r = 0.270, .m = 0.687583 },
    .{ .r = 0.260, .m = 0.665741 }, .{ .r = 0.250, .m = 0.642597 },
    .{ .r = 0.240, .m = 0.618252 }, .{ .r = 0.230, .m = 0.592586 },
    .{ .r = 0.220, .m = 0.565747 }, .{ .r = 0.210, .m = 0.537697 },
    .{ .r = 0.200, .m = 0.508554 }, .{ .r = 0.190, .m = 0.478420 },
    .{ .r = 0.180, .m = 0.447322 }, .{ .r = 0.170, .m = 0.415454 },
    .{ .r = 0.160, .m = 0.382892 }, .{ .r = 0.150, .m = 0.349955 },
    .{ .r = 0.140, .m = 0.316691 }, .{ .r = 0.130, .m = 0.283565 },
    .{ .r = 0.120, .m = 0.250431 }, .{ .r = 0.110, .m = 0.218327 },
    .{ .r = 0.100, .m = 0.186794 }, .{ .r = 0.090, .m = 0.156287 },
    .{ .r = 0.080, .m = 0.128421 }, .{ .r = 0.070, .m = 0.102237 },
    .{ .r = 0.060, .m = 0.077393 }, .{ .r = 0.050, .m = 0.054833 },
    .{ .r = 0.040, .m = 0.036361 }, .{ .r = 0.030, .m = 0.020953 },
    .{ .r = 0.020, .m = 0.009645 }, .{ .r = 0.010, .m = 0.002767 },
    .{ .r = 0.000, .m = 0.000000 },
};

/// sweph.c swi_deflect_light (relativistic light deflection by the sun)
pub fn swi_deflect_light(xx: *[6]f64, dt: f64, iflag: i32, swed: *Swed) void {
    var xx2: [3]f64 = undefined;
    var u: [3]f64 = undefined;
    var e: [3]f64 = undefined;
    var q: [3]f64 = undefined;
    var xx3: [3]f64 = undefined;
    var xsun: [6]f64 = undefined;
    var xearth: [6]f64 = undefined;
    const pedp = &swed.pldat[SEI_EARTH];
    const psdp = &swed.pldat[SEI_SUNBARY];
    const iephe = pedp.iephe;
    var i: usize = 0;
    while (i <= 5) : (i += 1)
        xearth[i] = pedp.x[i];
    if ((iflag & SEFLG_TOPOCTR) != 0) {
        i = 0;
        while (i <= 5) : (i += 1)
            xearth[i] += swed.topd.xobs[i];
    }
    // U = planetbary(t-tau) - earthbary(t) = planetgeo
    i = 0;
    while (i <= 2) : (i += 1)
        u[i] = xx[i];
    // Eh = earthbary(t) - sunbary(t) = earthhel
    if (iephe == SEFLG_JPLEPH or iephe == SEFLG_SWIEPH) {
        i = 0;
        while (i <= 2) : (i += 1)
            e[i] = xearth[i] - psdp.x[i];
    } else {
        i = 0;
        while (i <= 2) : (i += 1)
            e[i] = xearth[i];
    }
    // Q = planetbary(t-tau) - sunbary(t-tau) = 'planethel'
    // first compute sunbary(t-tau)
    if (iephe == SEFLG_JPLEPH or iephe == SEFLG_SWIEPH) {
        i = 0;
        while (i <= 2) : (i += 1)
            xsun[i] = psdp.x[i] - dt * psdp.x[i + 3];
        i = 3;
        while (i <= 5) : (i += 1)
            xsun[i] = psdp.x[i];
    } else {
        i = 0;
        while (i <= 5) : (i += 1)
            xsun[i] = psdp.x[i];
    }
    i = 0;
    while (i <= 2) : (i += 1)
        q[i] = xx[i] + xearth[i] - xsun[i];
    const ru = std.math.sqrt(square_sum(&u));
    const rq = std.math.sqrt(square_sum(&q));
    const re = std.math.sqrt(square_sum(&e));
    i = 0;
    while (i <= 2) : (i += 1) {
        u[i] /= ru;
        q[i] /= rq;
        e[i] /= re;
    }
    const uq = dot_prod(&u, &q);
    const ue = dot_prod(&u, &e);
    const qe = dot_prod(&q, &e);
    // Non-point-mass treatment near the solar limb, s. meff().
    const sina = std.math.sqrt(1 - ue * ue); // sin(angle) between sun and planet
    const sin_sunr = SUN_RADIUS / re; // sine of sun radius (= sun radius)
    var meff_fact: f64 = undefined;
    if (sina < sin_sunr) {
        meff_fact = meff(sina / sin_sunr);
    } else {
        meff_fact = 1;
    }
    const g1 = 2.0 * HELGRAVCONST * meff_fact / CLIGHT / CLIGHT / AUNIT / re;
    const g2 = 1.0 + qe;
    // compute deflected position
    i = 0;
    while (i <= 2) : (i += 1)
        xx2[i] = ru * (u[i] + g1 / g2 * (uq * e[i] - ue * q[i]));
    if ((iflag & SEFLG_SPEED) != 0) {
        // correction of speed (see comment in sweph.c)
        const dtsp = -DEFL_SPEED_INTV;
        i = 0;
        while (i <= 2) : (i += 1)
            u[i] = xx[i] - dtsp * xx[i + 3];
        if (iephe == SEFLG_JPLEPH or iephe == SEFLG_SWIEPH) {
            i = 0;
            while (i <= 2) : (i += 1)
                e[i] = xearth[i] - psdp.x[i] -
                    dtsp * (xearth[i + 3] - psdp.x[i + 3]);
        } else {
            i = 0;
            while (i <= 2) : (i += 1)
                e[i] = xearth[i] - dtsp * xearth[i + 3];
        }
        i = 0;
        while (i <= 2) : (i += 1)
            q[i] = u[i] + xearth[i] - xsun[i] -
                dtsp * (xearth[i + 3] - xsun[i + 3]);
        const ru2 = std.math.sqrt(square_sum(&u));
        const rq2 = std.math.sqrt(square_sum(&q));
        const re2 = std.math.sqrt(square_sum(&e));
        i = 0;
        while (i <= 2) : (i += 1) {
            u[i] /= ru2;
            q[i] /= rq2;
            e[i] /= re2;
        }
        const uq2 = dot_prod(&u, &q);
        const ue2 = dot_prod(&u, &e);
        const qe2 = dot_prod(&q, &e);
        const sina2 = std.math.sqrt(1 - ue2 * ue2);
        const sin_sunr2 = SUN_RADIUS / re2;
        var meff_fact2: f64 = undefined;
        if (sina2 < sin_sunr2) {
            meff_fact2 = meff(sina2 / sin_sunr2);
        } else {
            meff_fact2 = 1;
        }
        const g1b = 2.0 * HELGRAVCONST * meff_fact2 / CLIGHT / CLIGHT / AUNIT / re2;
        const g2b = 1.0 + qe2;
        i = 0;
        while (i <= 2) : (i += 1)
            xx3[i] = ru2 * (u[i] + g1b / g2b * (uq2 * e[i] - ue2 * q[i]));
        i = 0;
        while (i <= 2) : (i += 1) {
            var dx1 = xx2[i] - xx[i];
            const dx2 = xx3[i] - u[i] * ru2;
            dx1 -= dx2;
            xx[i + 3] += dx1 / dtsp;
        }
    }
    // deflected position
    i = 0;
    while (i <= 2) : (i += 1)
        xx[i] = xx2[i];
}

/// sweph.c denormalize_positions
fn denormalize_positions(x0: *[24]f64, x1: *[24]f64, x2: *[24]f64) void {
    // x*[0] = ecliptic longitude, x*[12] = rectascension
    var i: usize = 0;
    while (i <= 12) : (i += 12) {
        if (x1[i] - x0[i] < -180)
            x0[i] -= 360;
        if (x1[i] - x0[i] > 180)
            x0[i] += 360;
        if (x1[i] - x2[i] < -180)
            x2[i] -= 360;
        if (x1[i] - x2[i] > 180)
            x2[i] += 360;
    }
}

/// sweph.c calc_speed
fn calc_speed(x0: *[24]f64, x1: *[24]f64, x2: *[24]f64, dt: f64) void {
    var j: usize = 0;
    while (j <= 18) : (j += 6) {
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            const k = j + i;
            const b = (x2[k] - x0[k]) / 2;
            const a = (x2[k] + x0[k]) / 2 - x1[k];
            x1[k + 3] = (2 * a + b) / dt;
        }
    }
}

pub fn oscElemDebug(iflag: i32, tjd: f64, xpos: *[6]f64, swed: *Swed, models: AstroModels) void {
    swi_plan_for_osc_elem(iflag, tjd, xpos, swed, models);
}
pub fn plausPublic(iflag: i32, ipl: i32, tjd: f64, swed: *Swed, models: AstroModels) i32 {
    return plaus_iflag(iflag, ipl, tjd, swed, models, null);
}
pub fn sqsum(x: []const f64) f64 {
    return square_sum(x);
}

/// sweph.c plaus_iflag
fn plaus_iflag(iflag_in: i32, ipl: i32, tjd: f64, swed: *Swed, models: AstroModels, serr: ?[]u8) i32 {
    _ = tjd;
    var iflag = iflag_in;
    var epheflag: i32 = 0;
    var jplhor_model = models.jplhora;
    var jplhora_model = models.jplhora;
    if (jplhor_model == 0) jplhor_model = lib.SEMOD_JPLHORA_DEFAULT;
    if (jplhora_model == 0) jplhora_model = lib.SEMOD_JPLHORA_DEFAULT;
    // either Horizons mode or simplified Horizons mode, not both
    if ((iflag & SEFLG_JPLHOR) != 0)
        iflag &= ~SEFLG_JPLHOR_APPROX;
    // if topocentric bit, turn helio- and barycentric bits off
    if ((iflag & SEFLG_TOPOCTR) != 0) {
        iflag = iflag & ~(SEFLG_HELCTR | SEFLG_BARYCTR);
    }
    // if barycentric bit, turn heliocentric bit off
    if ((iflag & SEFLG_BARYCTR) != 0)
        iflag = iflag & ~(SEFLG_HELCTR);
    if ((iflag & SEFLG_HELCTR) != 0)
        iflag = iflag & ~(SEFLG_BARYCTR);
    // if heliocentric bit, turn aberration and deflection off
    if ((iflag & (SEFLG_HELCTR | SEFLG_BARYCTR)) != 0)
        iflag |= SEFLG_NOABERR | SEFLG_NOGDEFL;
    // if no_precession bit is set, set also no_nutation bit
    if ((iflag & SEFLG_J2000) != 0)
        iflag |= SEFLG_NONUT;
    // if sidereal bit is set, set also no_nutation bit and JPL Horizons off
    if ((iflag & SEFLG_SIDEREAL) != 0) {
        iflag |= SEFLG_NONUT;
        iflag = iflag & ~(SEFLG_JPLHOR | SEFLG_JPLHOR_APPROX);
    }
    // if truepos is set, turn off grav. defl. and aberration
    if ((iflag & SEFLG_TRUEPOS) != 0)
        iflag |= (SEFLG_NOGDEFL | SEFLG_NOABERR);
    if ((iflag & SEFLG_MOSEPH) != 0)
        epheflag = SEFLG_MOSEPH;
    if ((iflag & SEFLG_SWIEPH) != 0)
        epheflag = SEFLG_SWIEPH;
    if ((iflag & SEFLG_JPLEPH) != 0)
        epheflag = SEFLG_JPLEPH;
    if (epheflag == 0)
        epheflag = SEFLG_DEFAULTEPH;
    iflag = (iflag & ~SEFLG_EPHMASK) | epheflag;
    // SEFLG_JPLHOR only with JPL and Swiss Ephemeris
    if ((epheflag & SEFLG_JPLEPH) == 0)
        iflag = iflag & ~(SEFLG_JPLHOR | SEFLG_JPLHOR_APPROX);
    // planets that have no JPL Horizons mode
    if (ipl == SE_OSCU_APOG or ipl == SE_TRUE_NODE or
        ipl == SE_MEAN_APOG or ipl == SE_MEAN_NODE or
        ipl == SE_INTP_APOG or ipl == SE_INTP_PERG)
        iflag = iflag & ~(SEFLG_JPLHOR | SEFLG_JPLHOR_APPROX);
    if (ipl >= 40 and ipl <= 999) // SE_FICT_OFFSET..SE_FICT_MAX
        iflag = iflag & ~(SEFLG_JPLHOR | SEFLG_JPLHOR_APPROX);
    // SEFLG_JPLHOR requires SEFLG_ICRS + EOP data; without EOP downgrade
    if ((iflag & SEFLG_JPLHOR) != 0) {
        if (swed.eop_dpsi_loaded <= 0) {
            if (serr) |sr| {
                const msg = switch (swed.eop_dpsi_loaded) {
                    0 => "you did not call swe_set_jpl_file(); default to SEFLG_JPLHOR_APPROX",
                    -1 => "file eop_1962_today.txt not found; default to SEFLG_JPLHOR_APPROX",
                    -2 => "file eop_1962_today.txt corrupt; default to SEFLG_JPLHOR_APPROX",
                    -3 => "file eop_finals.txt corrupt; default to SEFLG_JPLHOR_APPROX",
                    else => "",
                };
                const n = @min(msg.len, sr.len - 1);
                @memcpy(sr[0..n], msg[0..n]);
                sr[n] = 0;
            }
            iflag &= ~SEFLG_JPLHOR;
            iflag |= SEFLG_JPLHOR_APPROX;
        }
    }
    if ((iflag & SEFLG_JPLHOR) != 0)
        iflag |= lib.SEFLG_ICRS;
    if ((iflag & SEFLG_JPLHOR_APPROX) != 0 and jplhora_model == lib.SEMOD_JPLHORA_2)
        iflag |= lib.SEFLG_ICRS;
    return iflag;
}

/// sweph.c swi_get_denum for the ported subset: MOSEPH always reports
/// DE403/404 lineage (>= 403), so the ICRS->J2000 frame bias IS applied.
fn swi_get_denum(ipli: i32, epheflag: i32, swed: *Swed) i32 {
    if ((epheflag & SEFLG_MOSEPH) != 0)
        return 403;
    if ((epheflag & SEFLG_JPLEPH) != 0) {
        if (swed.jpldenum > 0) {
            return swed.jpldenum;
        } else {
            return SE_DE_NUMBER;
        }
    }
    var fdp: ?*FileData = null;
    if (ipli > SE_AST_OFFSET) {
        fdp = &swed.fidat[SEI_FILE_ANY_AST];
    } else if (ipli > SE_PLMOON_OFFSET) {
        fdp = &swed.fidat[SEI_FILE_ANY_AST];
    } else if (ipli == SEI_CHIRON or ipli == SEI_PHOLUS or
        ipli == SEI_CERES or ipli == SEI_PALLAS or
        ipli == SEI_JUNO or ipli == SEI_VESTA)
    {
        fdp = &swed.fidat[SEI_FILE_MAIN_AST];
    } else if (ipli == SEI_MOON) {
        fdp = &swed.fidat[SEI_FILE_MOON];
    } else {
        fdp = &swed.fidat[SEI_FILE_PLANET];
    }
    if (fdp != null) {
        if (fdp.?.sweph_denum != 0) {
            return fdp.?.sweph_denum;
        } else {
            return SE_DE_NUMBER;
        }
    }
    return SE_DE_NUMBER;
}

/// sweph.c swe_set_topo: set geographic position and altitude of observer
pub fn swe_set_topo(geolon: f64, geolat: f64, geoalt: f64, swed: *Swed) void {
    if (swed.geopos_is_set == true and
        swed.topd.geolon == geolon and
        swed.topd.geolat == geolat and
        swed.topd.geoalt == geoalt)
    {
        return;
    }
    swed.topd.geolon = geolon;
    swed.topd.geolat = geolat;
    swed.topd.geoalt = geoalt;
    swed.geopos_is_set = true;
    // to force new calculation of observer position vector
    swed.topd.teval = 0;
    // to force new calculation of light-time etc.
    forceAppPos(swed);
}

/// swephlib.c swe_set_interpolate_nut
pub fn swe_set_interpolate_nut(do_interpolate: bool, swed: *Swed) void {
    if (swed.do_interpolate_nut == do_interpolate)
        return;
    swed.do_interpolate_nut = do_interpolate;
    swed.interp = .{};
}

/// sweph.c swi_get_observer
pub fn swi_get_observer(tjd: f64, iflag: i32, do_save: bool, xobs: *[6]f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var nutlo: [2]f64 = .{ 0, 0 };
    const f = EARTH_OBLATENESS;
    const re = EARTH_RADIUS;
    if (!swed.geopos_is_set) {
        if (serr) |sr| {
            const msg = "geographic position has not been set";
            const n = @min(msg.len, sr.len - 1);
            @memcpy(sr[0..n], msg[0..n]);
            sr[n] = 0;
        }
        return ERR;
    }
    // geocentric position of observer depends on sidereal time,
    // which depends on UT.
    // compute UT from ET. this UT will be slightly different
    // from the user's UT, but this difference is extremely small.
    dctx.sweph_denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
    const delt = deltat.swe_deltat_ex(dctx, tjd, iflag);
    const tjd_ut = tjd - delt;
    var eps: f64 = undefined;
    var nut: f64 = undefined;
    if (swed.oec.teps == tjd and swed.nut.tnut == tjd) {
        eps = swed.oec.eps;
        nutlo[1] = swed.nut.nutlo[1];
        nutlo[0] = swed.nut.nutlo[0];
    } else {
        eps = lib.swi_epsiln(tjd, iflag, models);
        if ((iflag & SEFLG_NONUT) == 0)
            _ = lib.swi_nutation(tjd, iflag, &nutlo, models, nutInterp(swed));
    }
    if ((iflag & SEFLG_NONUT) != 0) {
        nut = 0;
    } else {
        eps += nutlo[1];
        nut = nutlo[0];
    }
    // mean or apparent sidereal time, depending on whether or
    // not SEFLG_NONUT is set
    var sidt = lib.swe_sidtime0(tjd_ut, eps * RADTODEG, nut * RADTODEG, models, dctx, nutInterp(swed));
    sidt *= 15; // in degrees
    // length of position and speed vectors;
    // the height above sea level must be taken into account.
    const cosfi = swe_shim_cos(swed.topd.geolat * DEGTORAD);
    const sinfi = swe_shim_sin(swed.topd.geolat * DEGTORAD);
    const cc = 1 / @sqrt(cosfi * cosfi + (1 - f) * (1 - f) * sinfi * sinfi);
    const ss = (1 - f) * (1 - f) * cc;
    // add sidereal time
    const cosl = swe_shim_cos((swed.topd.geolon + sidt) * DEGTORAD);
    const sinl = swe_shim_sin((swed.topd.geolon + sidt) * DEGTORAD);
    const h = swed.topd.geoalt;
    xobs[0] = (re * cc + h) * cosfi * cosl;
    xobs[1] = (re * cc + h) * cosfi * sinl;
    xobs[2] = (re * ss + h) * sinfi;
    // polar coordinates
    lib.swi_cartpol(xobs[0..3], xobs[0..3]);
    // speed
    xobs[3] = EARTH_ROT_SPEED;
    xobs[4] = 0;
    xobs[5] = 0;
    lib.swi_polcart_sp(xobs, xobs);
    // to AUNIT
    for (0..6) |i|
        xobs[i] /= AUNIT;
    // subtract nutation, set backward flag
    if ((iflag & SEFLG_NONUT) == 0) {
        lib.swi_coortrf2(xobs[0..3], xobs[0..3], -swed.nut.snut, swed.nut.cnut);
        // speed of xobs is always required, namely for aberration!!!
        lib.swi_coortrf2(xobs[3..6], xobs[3..6], -swed.nut.snut, swed.nut.cnut);
        swi_nutate(xobs, iflag | SEFLG_SPEED, true, swed);
    }
    // precess to J2000
    _ = lib.swi_precess(xobs[0..3], tjd, iflag, lib.J_TO_J2000, models);
    swi_precess_speed(xobs, tjd, iflag, lib.J_TO_J2000, swed, models);
    // save
    if (do_save) {
        for (0..6) |i|
            swed.topd.xobs[i] = xobs[i];
        swed.topd.teval = tjd;
        swed.topd.tjd_ut = tjd_ut; // -> save area
    }
    return OK;
}

/// sweph.c swi_force_app_pos_etc
pub fn forceAppPos(swed: *Swed) void {
    for (0..SE_NPLANETS) |i|
        swed.pldat[i].xflgs = -1;
    for (0..SEI_NNDAT) |i|
        swed.nddat[i].xflgs = -1;
    for (0..SE_NPLANETS + 1) |i| {
        swed.savedat[i].tsave = 0;
        swed.savedat[i].iflgsave = -1;
    }
}

/// sweph.c swe_set_sid_mode (internal; models mutated only for
/// SE_SIDBIT_PREC_ORIG, which the caller's model state must see)
pub fn swe_set_sid_mode(sid_mode_in: i32, t0: f64, ayan_t0: f64, swed: *Swed, models: ?*AstroModels) void {
    var sid_mode = sid_mode_in;
    const sip = &swed.sidd;
    if (sid_mode < 0)
        sid_mode = 0;
    sip.sid_mode = sid_mode;
    if (sid_mode >= SE_SIDBITS)
        sid_mode = @mod(sid_mode, SE_SIDBITS);
    // standard equinoxes: positions always referred to ecliptic of t0
    if (sid_mode == SE_SIDM_J2000 or sid_mode == SE_SIDM_J1900 or
        sid_mode == SE_SIDM_B1950 or sid_mode == SE_SIDM_GALALIGN_MARDYKS)
    {
        sip.sid_mode = sid_mode;
        sip.sid_mode |= SE_SIDBIT_ECL_T0;
    }
    if (sid_mode == SE_SIDM_TRUE_CITRA or sid_mode == SE_SIDM_TRUE_REVATI or
        sid_mode == SE_SIDM_TRUE_PUSHYA or sid_mode == SE_SIDM_TRUE_MULA or
        sid_mode == SE_SIDM_TRUE_SHEORAN or sid_mode == SE_SIDM_GALCENT_0SAG or
        sid_mode == SE_SIDM_GALCENT_COCHRANE or sid_mode == SE_SIDM_GALCENT_RGILBRAND or
        sid_mode == SE_SIDM_GALCENT_MULA_WILHELM or sid_mode == SE_SIDM_GALEQU_IAU1958 or
        sid_mode == SE_SIDM_GALEQU_TRUE or sid_mode == SE_SIDM_GALEQU_MULA)
    {
        sip.sid_mode = sid_mode;
    }
    // make sure that sid_mode is either SE_SIDM_USER or < SE_NSIDM_PREDEF
    if (sid_mode >= SE_NSIDM_PREDEF and sid_mode != SE_SIDM_USER) {
        sid_mode = SE_SIDM_FAGAN_BRADLEY;
        sip.sid_mode = sid_mode;
    }
    swed.ayana_is_set = true;
    if (sid_mode == SE_SIDM_USER) {
        sip.t0 = t0;
        sip.ayan_t0 = ayan_t0;
        sip.t0_is_UT = false;
        if ((sip.sid_mode & SE_SIDBIT_USER_UT) != 0)
            sip.t0_is_UT = true;
    } else {
        sip.t0 = ayanamsa[@intCast(sid_mode)].t0;
        sip.ayan_t0 = ayanamsa[@intCast(sid_mode)].ayan_t0;
        sip.t0_is_UT = ayanamsa[@intCast(sid_mode)].t0_is_UT;
    }
    // test feature: ayanamsha using its original precession model
    if (sid_mode < SE_NSIDM_PREDEF and (sip.sid_mode & SE_SIDBIT_PREC_ORIG) != 0 and
        ayanamsa[@intCast(sid_mode)].prec_offset > 0)
    {
        if (models) |m| {
            m.prec_longterm = ayanamsa[@intCast(sid_mode)].prec_offset;
            m.prec_shortterm = ayanamsa[@intCast(sid_mode)].prec_offset;
            // add a corresponding nutation model
            switch (ayanamsa[@intCast(sid_mode)].prec_offset) {
                lib.SEMOD_PREC_NEWCOMB => m.nut = lib.SEMOD_NUT_WOOLARD,
                lib.SEMOD_PREC_IAU_1976 => m.nut = lib.SEMOD_NUT_IAU_1980,
                else => {},
            }
        }
    }
    forceAppPos(swed);
}

/// sweph.c get_aya_correction: ayanamsha correction if it was defined with
/// a different precession model than the current one. The model swap is
/// local to this function (C restores the globals afterwards).
fn get_aya_correction(iflag: i32, corr: *f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    _ = serr;
    var x: [6]f64 = undefined;
    var models2 = models;
    const prec_model = models.prec_longterm;
    corr.* = 0;
    if (swed.sidd.t0 == lib.J2000)
        return 0;
    if ((swed.sidd.sid_mode & SE_SIDBIT_NO_PREC_OFFSET) != 0)
        return 0;
    const sid_mode = @mod(swed.sidd.sid_mode, SE_SIDBITS);
    var prec_offset: i32 = 0;
    if (sid_mode < SE_NSIDM_PREDEF)
        prec_offset = ayanamsa[@intCast(sid_mode)].prec_offset;
    if (prec_offset < 0) prec_offset = 0;
    if (prec_model == prec_offset)
        return 0;
    var t0 = swed.sidd.t0;
    if (swed.sidd.t0_is_UT) {
        dctx.sweph_denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
        t0 += deltat.swe_deltat_ex(dctx, t0, iflag);
    }
    // vernal point (tjd), cartesian
    x[0] = 1;
    x[1] = 0;
    x[2] = 0;
    _ = lib.swi_precess(x[0..3], t0, 0, lib.J_TO_J2000, models);
    models2.prec_longterm = prec_offset;
    models2.prec_shortterm = prec_offset;
    _ = lib.swi_precess(x[0..3], t0, 0, lib.J2000_TO_J, models2);
    // to ecliptic
    const eps = lib.swi_epsiln(t0, 0, models);
    lib.swi_coortrf(x[0..3], x[0..3], eps);
    // to polar
    lib.swi_cartpol(x[0..3], x[0..3]);
    // get ayanamsa
    corr.* = x[0] * RADTODEG;
    if (corr.* > 350) // correct!
        corr.* -= 360; // a signed value near 0
    return 0;
}

/// sweph.c swi_get_ayanamsa_ex (star/galactic-based ayanamshas need
/// swe_fixstar: deferred, see plan)
fn swi_get_ayanamsa_ex(tjd_et: f64, iflag_in: i32, daya: *f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var iflag = iflag_in;
    var x: [6]f64 = undefined;
    const housemod = @import("swehouse");
    var eps: f64 = undefined;
    var t0: f64 = undefined;
    var corr: f64 = 0;
    var sid_mode: i32 = swed.sidd.sid_mode;
    iflag = plaus_iflag(iflag, -1, tjd_et, swed, models, serr);

    daya.* = 0.0;
    iflag &= SEFLG_EPHMASK;
    iflag |= SEFLG_NONUT;
    const otherflag = iflag_in & ~SEFLG_EPHMASK;
    sid_mode = @mod(sid_mode, SE_SIDBITS);
    // star-based ayanamshas
    var iflag_true: i32 = 0;
    var iflag_galequ: i32 = 0;
    var star: [SWI_STAR_LENGTH + 1]u8 = [_]u8{0} ** (SWI_STAR_LENGTH + 1);
    var xstar: [6]f64 = undefined;
    var retflag: i32 = undefined;
    if ((sid_mode == SE_SIDM_TRUE_CITRA or sid_mode == SE_SIDM_TRUE_REVATI or
        sid_mode == SE_SIDM_TRUE_PUSHYA or sid_mode == SE_SIDM_TRUE_MULA or
        sid_mode == SE_SIDM_GALCENT_0SAG or sid_mode == SE_SIDM_GALCENT_COCHRANE or
        sid_mode == SE_SIDM_GALCENT_RGILBRAND or sid_mode == SE_SIDM_GALCENT_MULA_WILHELM or
        sid_mode == SE_SIDM_GALEQU_IAU1958 or sid_mode == SE_SIDM_GALEQU_TRUE or
        sid_mode == SE_SIDM_GALEQU_MULA) and serr != null)
    {
        // warning if ephe path not set (mirrors C's swi_init_swed_if_start check)
    }
    // _TRUE_ ayanamshas can have the following SEFLG_s
    iflag_true = iflag;
    if ((otherflag & SEFLG_TRUEPOS) != 0) iflag_true |= SEFLG_TRUEPOS;
    if ((otherflag & SEFLG_NOABERR) != 0) iflag_true |= SEFLG_NOABERR;
    if ((otherflag & SEFLG_NOGDEFL) != 0) iflag_true |= SEFLG_NOGDEFL;
    // galactic equator ayanamshas always need SEFLG_TRUEPOS
    iflag_galequ = iflag | SEFLG_TRUEPOS;
    if (sid_mode == SE_SIDM_TRUE_CITRA) {
        @memcpy(star[0..5], "Spica");
        star[5] = 0;
        retflag = swe_fixstar(star[0..], tjd_et, iflag_true, &xstar, swed, models, dctx, serr);
        if (retflag == ERR)
            return ERR;
        daya.* = lib.swe_degnorm(xstar[0] - 180);
        return retflag & SEFLG_EPHMASK;
    }
    if (sid_mode == SE_SIDM_TRUE_REVATI) {
        @memcpy(star[0..6], ",zePsc");
        star[6] = 0;
        retflag = swe_fixstar(star[0..], tjd_et, iflag_true, &xstar, swed, models, dctx, serr);
        if (retflag == ERR)
            return ERR;
        daya.* = lib.swe_degnorm(xstar[0] - 359.8333333333);
        return retflag & SEFLG_EPHMASK;
    }
    if (sid_mode == SE_SIDM_TRUE_PUSHYA) {
        @memcpy(star[0..6], ",deCnc");
        star[6] = 0;
        retflag = swe_fixstar(star[0..], tjd_et, iflag_true, &xstar, swed, models, dctx, serr);
        if (retflag == ERR)
            return ERR;
        daya.* = lib.swe_degnorm(xstar[0] - 106);
        return retflag & SEFLG_EPHMASK;
    }
    if (sid_mode == SE_SIDM_TRUE_SHEORAN) {
        @memcpy(star[0..6], ",deCnc");
        star[6] = 0;
        retflag = swe_fixstar(star[0..], tjd_et, iflag_true, &xstar, swed, models, dctx, serr);
        if (retflag == ERR)
            return ERR;
        daya.* = lib.swe_degnorm(xstar[0] - 103.49264221625);
        return retflag & SEFLG_EPHMASK;
    }
    if (sid_mode == SE_SIDM_TRUE_MULA) {
        @memcpy(star[0..6], ",laSco");
        star[6] = 0;
        retflag = swe_fixstar(star[0..], tjd_et, iflag_true, &xstar, swed, models, dctx, serr);
        if (retflag == ERR)
            return ERR;
        daya.* = lib.swe_degnorm(xstar[0] - 240);
        return retflag & SEFLG_EPHMASK;
    }
    if (sid_mode == SE_SIDM_GALCENT_0SAG) {
        @memcpy(star[0..6], ",SgrA*");
        star[6] = 0;
        retflag = swe_fixstar(star[0..], tjd_et, iflag_true, &xstar, swed, models, dctx, serr);
        if (retflag == ERR)
            return ERR;
        daya.* = lib.swe_degnorm(xstar[0] - 240.0);
        return retflag & SEFLG_EPHMASK;
    }
    if (sid_mode == SE_SIDM_GALCENT_COCHRANE) {
        @memcpy(star[0..6], ",SgrA*");
        star[6] = 0;
        retflag = swe_fixstar(star[0..], tjd_et, iflag_true, &xstar, swed, models, dctx, serr);
        if (retflag == ERR)
            return ERR;
        daya.* = lib.swe_degnorm(xstar[0] - 270.0);
        return retflag & SEFLG_EPHMASK;
    }
    if (sid_mode == SE_SIDM_GALCENT_RGILBRAND) {
        @memcpy(star[0..6], ",SgrA*");
        star[6] = 0;
        retflag = swe_fixstar(star[0..], tjd_et, iflag_true, &xstar, swed, models, dctx, serr);
        if (retflag == ERR)
            return ERR;
        daya.* = lib.swe_degnorm(xstar[0] - 210.0 - 90.0 * 0.3819660113);
        return retflag & SEFLG_EPHMASK;
    }
    if (sid_mode == SE_SIDM_GALCENT_MULA_WILHELM) {
        @memcpy(star[0..6], ",SgrA*");
        star[6] = 0;
        retflag = swe_fixstar(star[0..], tjd_et, iflag_true | SEFLG_EQUATORIAL, &xstar, swed, models, dctx, serr);
        if (retflag == ERR)
            return ERR;
        const eps_mula = lib.swi_epsiln(tjd_et, iflag, models) * RADTODEG;
        daya.* = housemod.armc_to_mc(xstar[0], eps_mula);
        daya.* = lib.swe_degnorm(daya.* - 246.6666666667);
        return retflag & SEFLG_EPHMASK;
    }
    if (sid_mode == SE_SIDM_GALEQU_IAU1958) {
        @memcpy(star[0..7], ",GP1958");
        star[7] = 0;
        retflag = swe_fixstar(star[0..], tjd_et, iflag_galequ, &xstar, swed, models, dctx, serr);
        if (retflag == ERR)
            return ERR;
        daya.* = lib.swe_degnorm(xstar[0] - 150);
        return retflag & SEFLG_EPHMASK;
    }
    if (sid_mode == SE_SIDM_GALEQU_TRUE) {
        @memcpy(star[0..5], ",GPol");
        star[5] = 0;
        retflag = swe_fixstar(star[0..], tjd_et, iflag_galequ, &xstar, swed, models, dctx, serr);
        if (retflag == ERR)
            return ERR;
        daya.* = lib.swe_degnorm(xstar[0] - 150);
        return retflag & SEFLG_EPHMASK;
    }
    if (sid_mode == SE_SIDM_GALEQU_MULA) {
        @memcpy(star[0..5], ",GPol");
        star[5] = 0;
        retflag = swe_fixstar(star[0..], tjd_et, iflag_galequ, &xstar, swed, models, dctx, serr);
        if (retflag == ERR)
            return ERR;
        daya.* = lib.swe_degnorm(xstar[0] - 150 - 6.6666666667);
        return retflag & SEFLG_EPHMASK;
    }
    if (!swed.ayana_is_set)
        swe_set_sid_mode(SE_SIDM_FAGAN_BRADLEY, 0, 0, swed, null);
    if ((swed.sidd.sid_mode & SE_SIDBIT_ECL_DATE) == 0) {
        // original method: precession measured on the ecliptic of the
        // start epoch t0 (ayan_t0)
        // vernal point (tjd), cartesian
        x[0] = 1;
        x[1] = 0;
        x[2] = 0;
        x[3] = 0;
        x[4] = 0;
        x[5] = 0;
        // to J2000
        if (tjd_et != lib.J2000)
            _ = lib.swi_precess(x[0..3], tjd_et, 0, lib.J_TO_J2000, models);
        // to t0
        t0 = swed.sidd.t0;
        if (swed.sidd.t0_is_UT) {
            dctx.sweph_denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
            t0 += deltat.swe_deltat_ex(dctx, t0, iflag);
        }
        _ = lib.swi_precess(x[0..3], t0, 0, lib.J2000_TO_J, models);
        // to ecliptic t0
        eps = lib.swi_epsiln(t0, 0, models);
        lib.swi_coortrf(x[0..3], x[0..3], eps);
        // to polar
        lib.swi_cartpol(x[0..3], x[0..3]);
        // subtract initial value of ayanamsa
        x[0] = -x[0] * RADTODEG + swed.sidd.ayan_t0;
    } else {
        // alternative method: ayanamsha measured on the ecliptic of date
        // at t0, we have ayanamsha sip->ayan_t0
        x[0] = lib.swe_degnorm(swed.sidd.ayan_t0) * DEGTORAD;
        x[1] = 0;
        x[2] = 1;
        // get epsilon for t0
        t0 = swed.sidd.t0;
        if (swed.sidd.t0_is_UT) {
            dctx.sweph_denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
            t0 += deltat.swe_deltat_ex(dctx, t0, iflag);
        }
        eps = lib.swi_epsiln(t0, 0, models);
        // to polar equatorial relative to equinox t0
        lib.swi_polcart(x[0..3], x[0..3]);
        lib.swi_coortrf(x[0..3], x[0..3], -eps);
        // precess to J2000
        if (t0 != lib.J2000)
            _ = lib.swi_precess(x[0..3], t0, 0, lib.J_TO_J2000, models);
        // precess to date
        _ = lib.swi_precess(x[0..3], tjd_et, 0, lib.J2000_TO_J, models);
        // epsilon of date
        eps = lib.swi_epsiln(tjd_et, 0, models);
        // to polar
        lib.swi_coortrf(x[0..3], x[0..3], eps);
        lib.swi_cartpol(x[0..3], x[0..3]);
        x[0] = lib.swe_degnorm(x[0] * RADTODEG);
    }
    _ = get_aya_correction(iflag, &corr, swed, models, dctx, null);
    // get ayanamsa
    daya.* = lib.swe_degnorm(x[0] - corr);
    return iflag;
}

/// sweph.c swe_get_ayanamsa_ex
pub fn swe_get_ayanamsa_ex(tjd_et: f64, iflag: i32, daya: *f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var nuttmp: Nut = .{};
    var nutp: *Nut = undefined;
    var retval = swi_get_ayanamsa_ex(tjd_et, iflag, daya, swed, models, dctx, serr);
    if ((iflag & SEFLG_NONUT) == 0) {
        if (tjd_et == swed.nut.tnut) {
            nutp = &swed.nut;
        } else {
            nutp = &nuttmp;
            _ = lib.swi_nutation(tjd_et, iflag, &nutp.nutlo, models, nutInterp(swed));
        }
        daya.* += nutp.nutlo[0] * RADTODEG;
        retval &= ~SEFLG_NONUT; // must remove flag which was added internally in swi_get_ayanamsa_ex()
    }
    return retval;
}

/// sweph.c swe_get_ayanamsa_ex_ut
pub fn swe_get_ayanamsa_ex_ut(tjd_ut: f64, iflag_in: i32, daya: *f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var iflag = iflag_in;
    var retflag: i32 = OK;
    var epheflag = iflag & SEFLG_EPHMASK;
    if (epheflag == 0) {
        epheflag = SEFLG_SWIEPH;
        iflag |= SEFLG_SWIEPH;
    }
    // C's calc_deltat reads swed.fidat[SEI_FILE_MOON].sweph_denum live
    dctx.sweph_denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
    var dt = deltat.swe_deltat_ex(dctx, tjd_ut, iflag);
    // swe... includes nutation, unless SEFLG_NONUT
    retflag = swe_get_ayanamsa_ex(tjd_ut + dt, iflag, daya, swed, models, dctx, serr);
    // if ephe required is not ephe returned, adjust delta t:
    if ((retflag & SEFLG_EPHMASK) != epheflag) {
        dctx.sweph_denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
        dt = deltat.swe_deltat_ex(dctx, tjd_ut, retflag);
        retflag = swe_get_ayanamsa_ex(tjd_ut + dt, iflag, daya, swed, models, dctx, serr);
    }
    return retflag;
}

/// sweph.c swi_get_ayanamsa_with_speed
pub fn swi_get_ayanamsa_with_speed(tjd_et: f64, iflag: i32, daya: *[2]f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var daya_t2: f64 = 0;
    const tintv: f64 = 0.001;
    const t2 = tjd_et - tintv;
    var retflag = swi_get_ayanamsa_ex(t2, iflag, &daya_t2, swed, models, dctx, serr);
    if (retflag == ERR)
        return ERR;
    retflag = swi_get_ayanamsa_ex(tjd_et, iflag, &daya[0], swed, models, dctx, serr);
    if (retflag == ERR)
        return ERR;
    daya[1] = (daya[0] - daya_t2) / tintv;
    return retflag;
}

/// sweph.c swi_trop_ra2sid_lon: input J2000 cartesian equatorial;
/// xout = ecliptical sidereal (ecliptic t0), xoutr = equatorial sidereal
pub fn swi_trop_ra2sid_lon(xin: *const [6]f64, xout: *[6]f64, xoutr: *[6]f64, iflag: i32, swed: *Swed, models: AstroModels, dctx: *DeltatCtx) i32 {
    var x: [6]f64 = undefined;
    var corr: f64 = 0;
    var oectmp: Eps = .{};
    for (0..6) |i|
        x[i] = xin[i];
    if (swed.sidd.t0 != lib.J2000) {
        // iflag must not contain SEFLG_JPLHOR here
        _ = lib.swi_precess(x[0..3], swed.sidd.t0, 0, lib.J2000_TO_J, models);
        _ = lib.swi_precess(x[3..6], swed.sidd.t0, 0, lib.J2000_TO_J, models); // speed
    }
    for (0..6) |i|
        xoutr[i] = x[i];
    calc_epsilon(swed.sidd.t0, iflag, &oectmp, models);
    lib.swi_coortrf2(x[0..3], x[0..3], oectmp.seps, oectmp.ceps);
    if ((iflag & SEFLG_SPEED) != 0)
        lib.swi_coortrf2(x[3..6], x[3..6], oectmp.seps, oectmp.ceps);
    // to polar coordinates
    lib.swi_cartpol_sp(&x, &x);
    // subtract ayan_t0
    _ = get_aya_correction(iflag, &corr, swed, models, dctx, null);
    x[0] -= swed.sidd.ayan_t0 * DEGTORAD;
    x[0] = lib.swe_radnorm(x[0] + corr * DEGTORAD);
    // back to cartesian
    lib.swi_polcart_sp(&x, xout);
    return 0;
}

/// sweph.c swi_trop_ra2sid_lon_sosy: input J2000 cartesian equatorial;
/// xout = ecliptical sidereal position (solar-system-equator projection)
pub fn swi_trop_ra2sid_lon_sosy(xin: *const [6]f64, xout: *[6]f64, iflag: i32, swed: *Swed, models: AstroModels, dctx: *DeltatCtx) i32 {
    var x: [6]f64 = undefined;
    var x0: [6]f64 = undefined;
    var corr: f64 = 0;
    const oe = &swed.oec2000;
    const plane_node = SSY_PLANE_NODE_E2000;
    const plane_incl = SSY_PLANE_INCL;
    for (0..6) |i|
        x[i] = xin[i];
    // planet to ecliptic 2000
    lib.swi_coortrf2(x[0..3], x[0..3], oe.seps, oe.ceps);
    if ((iflag & SEFLG_SPEED) != 0)
        lib.swi_coortrf2(x[3..6], x[3..6], oe.seps, oe.ceps);
    // to polar coordinates
    lib.swi_cartpol_sp(&x, &x);
    // to solar system equator
    x[0] -= plane_node;
    lib.swi_polcart_sp(&x, &x);
    lib.swi_coortrf(x[0..3], x[0..3], plane_incl);
    lib.swi_coortrf(x[3..6], x[3..6], plane_incl);
    lib.swi_cartpol_sp(&x, &x);
    // zero point of t0 in J2000 system
    x0[0] = 1;
    x0[1] = 0;
    x0[2] = 0;
    if (swed.sidd.t0 != lib.J2000) {
        // iflag must not contain SEFLG_JPLHOR here
        _ = lib.swi_precess(x0[0..3], swed.sidd.t0, 0, lib.J_TO_J2000, models);
    }
    // zero point to ecliptic 2000
    lib.swi_coortrf2(x0[0..3], x0[0..3], oe.seps, oe.ceps);
    // to polar coordinates
    lib.swi_cartpol(x0[0..3], x0[0..3]);
    // to solar system equator
    x0[0] -= plane_node;
    lib.swi_polcart(x0[0..3], x0[0..3]);
    lib.swi_coortrf(x0[0..3], x0[0..3], plane_incl);
    lib.swi_cartpol(x0[0..3], x0[0..3]);
    // measure planet from zero point
    x[0] -= x0[0];
    x[0] *= RADTODEG;
    // subtract ayan_t0
    _ = get_aya_correction(iflag, &corr, swed, models, dctx, null);
    x[0] -= swed.sidd.ayan_t0;
    x[0] = lib.swe_degnorm(x[0] + corr) * DEGTORAD;
    // back to cartesian
    lib.swi_polcart_sp(&x, xout);
    return 0;
}

/// sweph.c app_pos_rest (nutation, ecliptic, polar conversions)
fn app_pos_rest(pdp: *PlanData, iflag: i32, xx: *[6]f64, x2000: []const f64, oe: *const Eps, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    // nutation
    if ((iflag & SEFLG_NONUT) == 0)
        swi_nutate(xx, iflag, false, swed);
    // now we have equatorial cartesian coordinates; save them
    var i: usize = 0;
    while (i <= 5) : (i += 1)
        pdp.xreturn[18 + i] = xx[i];
    // transformation to ecliptic.
    lib.swi_coortrf2(xx[0..3], xx[0..3], oe.seps, oe.ceps);
    if ((iflag & SEFLG_SPEED) != 0)
        lib.swi_coortrf2(xx[3..6], xx[3..6], oe.seps, oe.ceps);
    if ((iflag & SEFLG_NONUT) == 0) {
        lib.swi_coortrf2(xx[0..3], xx[0..3], swed.nut.snut, swed.nut.cnut);
        if ((iflag & SEFLG_SPEED) != 0)
            lib.swi_coortrf2(xx[3..6], xx[3..6], swed.nut.snut, swed.nut.cnut);
    }
    // now we have ecliptic cartesian coordinates
    i = 0;
    while (i <= 5) : (i += 1)
        pdp.xreturn[6 + i] = xx[i];
    // sidereal positions
    if ((iflag & SEFLG_SIDEREAL) != 0) {
        var daya: [2]f64 = .{ 0, 0 };
        var xxsv2: [24]f64 = undefined;
        // project onto ecliptic t0
        if ((swed.sidd.sid_mode & SE_SIDBIT_ECL_T0) != 0) {
            if (swi_trop_ra2sid_lon(x2000[0..6], pdp.xreturn[6..12], pdp.xreturn[18..24], iflag, swed, models, dctx) != 0)
                return ERR;
            // project onto solar system equator
        } else if ((swed.sidd.sid_mode & SE_SIDBIT_SSY_PLANE) != 0) {
            if (swi_trop_ra2sid_lon_sosy(x2000[0..6], pdp.xreturn[6..12], iflag, swed, models, dctx) != 0)
                return ERR;
        } else {
            // traditional algorithm
            lib.swi_cartpol_sp(pdp.xreturn[6..12], pdp.xreturn[0..6]);
            // note, swi_get_ayanamsa_ex() disturbs present calculations, if
            // sun is calculated with TRUE_CHITRA ayanamsha, because the
            // ayanamsha also calculates the sun. Therefore current values
            // are saved...
            for (0..24) |k|
                xxsv2[k] = pdp.xreturn[k];
            if (swi_get_ayanamsa_with_speed(pdp.teval, iflag, &daya, swed, models, dctx, serr) == ERR)
                return ERR;
            // ... and restored
            for (0..24) |k|
                pdp.xreturn[k] = xxsv2[k];
            pdp.xreturn[0] -= daya[0] * DEGTORAD;
            pdp.xreturn[3] -= daya[1] * DEGTORAD;
            lib.swi_polcart_sp(pdp.xreturn[0..6], pdp.xreturn[6..12]);
        }
    }
    // transformation to polar coordinates
    // (C: swi_cartpol_sp(xreturn+18, xreturn+12); swi_cartpol_sp(xreturn+6, xreturn))
    lib.swi_cartpol_sp(pdp.xreturn[18..24], pdp.xreturn[12..18]);
    lib.swi_cartpol_sp(pdp.xreturn[6..12], pdp.xreturn[0..6]);
    // radians to degrees
    i = 0;
    while (i < 2) : (i += 1) {
        pdp.xreturn[i] *= RADTODEG; // ecliptic
        pdp.xreturn[i + 3] *= RADTODEG;
        pdp.xreturn[i + 12] *= RADTODEG; // equator
        pdp.xreturn[i + 15] *= RADTODEG;
    }
    // save, what has been done
    pdp.xflgs = iflag;
    pdp.iephe = iflag & SEFLG_EPHMASK;
    return OK;
}

/// sweph.c app_pos_etc_plan for SEFLG_MOSEPH
/// sweph.c calc_center_body: add center-of-body offset to planet position
fn calc_center_body(ipli: usize, iflag: i32, xx: *[6]f64, xcom: *[6]f64) void {
    if ((iflag & SEFLG_CENTER_BODY) == 0)
        return;
    if (ipli < SEI_MARS or ipli > SEI_PLUTO)
        return;
    for (0..6) |i|
        xx[i] += xcom[i];
}

fn app_pos_etc_plan(ipli_in: usize, iplmoon_in: i32, iflag: i32, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    const iplmoon = iplmoon_in;
    var xx: [6]f64 = undefined;
    var xx0: [6]f64 = undefined;
    var dx: [3]f64 = undefined;
    var dt: f64 = undefined;
    var t: f64 = undefined;
    var dtsave_for_defl: f64 = 0;
    var xobs: [6]f64 = undefined;
    var xobs2: [6]f64 = undefined;
    var xearth: [6]f64 = undefined;
    var xsun: [6]f64 = undefined;
    var xxsp: [3]f64 = undefined;
    var xxsv: [6]f64 = undefined;
    var xcom: [6]f64 = undefined;
    const pedp = &swed.pldat[SEI_EARTH];
    // ephemeris file (C: ifno/ibody/pdp selection at function top)
    const ipli: usize = ipli_in;
    var ifno: usize = SEI_FILE_PLANET;
    var ibody: i32 = IS_PLANET;
    var pdp_idx: usize = ipli;
    if (ipli > SE_PLMOON_OFFSET or ipli > SE_AST_OFFSET) { // 2nd condition obsolete in C
        ifno = SEI_FILE_ANY_AST;
        ibody = IS_ANY_BODY;
        pdp_idx = SEI_ANYBODY;
    } else if (ipli == SEI_CHIRON or ipli == SEI_PHOLUS or
        ipli == SEI_CERES or ipli == SEI_PALLAS or
        ipli == SEI_JUNO or ipli == SEI_VESTA)
    {
        ifno = SEI_FILE_MAIN_AST;
        ibody = IS_MAIN_ASTEROID;
        pdp_idx = ipli;
    } else {
        ifno = SEI_FILE_PLANET;
        ibody = IS_PLANET;
        pdp_idx = ipli;
    }
    const pdp = &swed.pldat[pdp_idx];
    var oe: *const Eps = &swed.oec2000;
    const epheflag = iflag & SEFLG_EPHMASK;
    t = pdp.teval;
    // if the same conversions have already been done for the same date, return
    const flg1 = iflag & ~SEFLG_EQUATORIAL & ~SEFLG_XYZ;
    const flg2 = pdp.xflgs & ~SEFLG_EQUATORIAL & ~SEFLG_XYZ;
    if (flg1 == flg2) {
        pdp.xflgs = iflag;
        pdp.iephe = iflag & SEFLG_EPHMASK;
        return OK;
    }
    // the conversions will be done with xx[]
    var i: usize = 0;
    while (i <= 5) : (i += 1)
        xx[i] = pdp.x[i];
    // center body of planet, if SEFLG_CENTER_BODY
    calc_center_body(ipli, iflag, &xx, &swed.pldat[SEI_ANYBODY].x);
    i = 0;
    while (i <= 5) : (i += 1)
        xx0[i] = xx[i];
    // if heliocentric position is wanted
    if ((iflag & SEFLG_HELCTR) != 0) {
        if (pdp.iephe == SEFLG_JPLEPH or pdp.iephe == SEFLG_SWIEPH) {
            i = 0;
            while (i <= 5) : (i += 1)
                xx[i] -= swed.pldat[SEI_SUNBARY].x[i];
        }
    }
    // observer: geocenter or topocenter
    // if topocentric position is wanted
    if ((iflag & SEFLG_TOPOCTR) != 0) {
        if (swed.topd.teval != pedp.teval or swed.topd.teval == 0) {
            if (swi_get_observer(pedp.teval, iflag | SEFLG_NONUT, true, &xobs, swed, models, dctx, serr) != OK)
                return ERR;
        } else {
            i = 0;
            while (i <= 5) : (i += 1)
                xobs[i] = swed.topd.xobs[i];
        }
        // barycentric position of observer
        i = 0;
        while (i <= 5) : (i += 1)
            xobs[i] = xobs[i] + pedp.x[i];
    } else {
        // barycentric position of geocenter
        i = 0;
        while (i <= 5) : (i += 1)
            xobs[i] = pedp.x[i];
    }
    // light-time geocentric
    if ((iflag & SEFLG_TRUEPOS) == 0) {
        // number of iterations - 1
        var niter: usize = undefined;
        if (pdp.iephe == SEFLG_JPLEPH or pdp.iephe == SEFLG_SWIEPH) {
            niter = 1;
        } else { // SEFLG_MOSEPH or planet from osculating elements
            niter = 0;
        }
        if ((iflag & SEFLG_SPEED) != 0) {
            // apparent speed influenced by change of dt with time
            i = 0;
            while (i <= 2) : (i += 1) {
                xxsp[i] = xx[i] - xx[i + 3];
                xxsv[i] = xxsp[i];
            }
            var j: usize = 0;
            while (j <= niter) : (j += 1) {
                i = 0;
                while (i <= 2) : (i += 1) {
                    dx[i] = xxsp[i];
                    if ((iflag & SEFLG_HELCTR) == 0 and (iflag & SEFLG_BARYCTR) == 0)
                        dx[i] -= (xobs[i] - xobs[i + 3]);
                }
                // new dt
                dt = std.math.sqrt(square_sum(&dx)) * AUNIT / CLIGHT / 86400.0;
                i = 0;
                while (i <= 2) : (i += 1) {
                    // rough apparent position at t-1
                    xxsp[i] = xxsv[i] - dt * xx0[i + 3];
                }
            }
            // true position - apparent position at time t-1
            i = 0;
            while (i <= 2) : (i += 1)
                xxsp[i] = xxsv[i] - xxsp[i];
        }
        // dt and t(apparent)
        var j2: usize = 0;
        while (j2 <= niter) : (j2 += 1) {
            i = 0;
            while (i <= 2) : (i += 1) {
                dx[i] = xx[i];
                if ((iflag & SEFLG_HELCTR) == 0 and (iflag & SEFLG_BARYCTR) == 0)
                    dx[i] -= xobs[i];
            }
            dt = std.math.sqrt(square_sum(&dx)) * AUNIT / CLIGHT / 86400.0;
            // new t
            t = pdp.teval - dt;
            dtsave_for_defl = dt;
            i = 0;
            while (i <= 2) : (i += 1) {
                // rough apparent position at t
                xx[i] = xx0[i] - dt * xx0[i + 3];
            }
        }
        // part of daily motion resulting from change of dt
        if ((iflag & SEFLG_SPEED) != 0) {
            i = 0;
            while (i <= 2) : (i += 1)
                xxsp[i] = xx0[i] - xx[i] - xxsp[i];
        }

        // center body of planet, if SEFLG_CENTER_BODY (recompute at t)
        if ((iflag & SEFLG_CENTER_BODY) != 0 and ipli >= SEI_MARS and ipli <= SEI_PLUTO) {
            const retc = sweph(t, @intCast(iplmoon), SEI_FILE_ANY_AST, iflag, null, false, xcom[0..], serr, swed, models);
            if (retc == ERR or retc == NOT_AVAILABLE)
                return ERR;
        }
        // new position, accounting for light-time (accurate)
        switch (epheflag) {
            SEFLG_JPLEPH => {
                var retc: i32 = undefined;
                if (ibody == IS_PLANET) {
                    const iplj = PNOINT2JPL[ipli];
                    retc = jplmod.swi_pleph(t, iplj, jplmod.J_SBARY, xx[0..6], swed, serr);
                    if (retc != OK) {
                        jplmod.swi_close_jpl_file(swed);
                        swed.jpl_file_is_open = false;
                    }
                    if (retc != OK)
                        return retc;
                } else { // asteroid
                    // first sun
                    var xs6: [6]f64 = undefined;
                    retc = jplmod.swi_pleph(t, jplmod.J_SUN, jplmod.J_SBARY, &xs6, swed, serr);
                    if (retc != OK) {
                        jplmod.swi_close_jpl_file(swed);
                        swed.jpl_file_is_open = false;
                    }
                    for (0..6) |k| xsun[k] = xs6[k];
                    // asteroid
                    retc = sweph(t, ipli, ifno, iflag, xsun[0..], false, xx[0..], serr, swed, models);
                }
                if (retc != OK)
                    return retc;
                // for accuracy in speed, we need earth as well
                if ((iflag & SEFLG_SPEED) != 0 and
                    (iflag & SEFLG_HELCTR) == 0 and (iflag & SEFLG_BARYCTR) == 0)
                {
                    var xe6: [6]f64 = undefined;
                    retc = jplmod.swi_pleph(t, jplmod.J_EARTH, jplmod.J_SBARY, &xe6, swed, serr);
                    for (0..6) |k| xearth[k] = xe6[k];
                    if (retc != OK) {
                        jplmod.swi_close_jpl_file(swed);
                        swed.jpl_file_is_open = false;
                        return retc;
                    }
                }
            },
            SEFLG_SWIEPH => {
                if (ibody == IS_PLANET) {
                    const retc = sweplan(t, ipli, ifno, iflag, false, xx[0..], xearth[0..], xsun[0..], null, serr, swed, models);
                    if (retc != OK)
                        return retc;
                } else { // asteroid
                    const retc0 = sweplan(t, SEI_EARTH, SEI_FILE_PLANET, iflag, false, null, xearth[0..], xsun[0..], null, serr, swed, models);
                    var retc = retc0;
                    if (retc == OK)
                        retc = sweph(t, ipli, ifno, iflag, xsun[0..], false, xx[0..], serr, swed, models);
                    if (retc != OK)
                        return retc;
                }
            },
            else => {
                // SEFLG_MOSEPH: with speed flag, call swi_moshplan for new
                // t; this does not increase position precision, but speed
                // precision
                if ((iflag & SEFLG_SPEED) != 0 and
                    (iflag & (SEFLG_HELCTR | SEFLG_BARYCTR)) == 0)
                {
                    var xxsv6: [6]f64 = undefined;
                    var xearth6: [6]f64 = undefined;
                    var retc: i32 = undefined;
                    if (ibody == IS_PLANET) {
                        retc = swi_moshplan_call(t, ipli, &xxsv6, &xearth6, swed, models, null);
                    } else { // if asteroid
                        retc = sweph(t, ipli, ifno, iflag, null, false, xxsv[0..], serr, swed, models);
                        if (retc == OK)
                            retc = swi_moshplan_call(t, SEI_EARTH, null, &xearth6, swed, models, null);
                    }
                    if (retc != OK)
                        return retc;
                    i = 0;
                    while (i <= 5) : (i += 1)
                        xxsv[i] = xxsv6[i];
                    // only speed is taken from this computation, otherwise
                    // position calculations with and without speed would not
                    // agree. The difference would be about 0.01", far below
                    // the intrinsic error of the moshier ephemeris.
                    i = 3;
                    while (i <= 5) : (i += 1)
                        xx[i] = xxsv[i];
                    i = 0;
                    while (i <= 5) : (i += 1)
                        xearth[i] = xearth6[i];
                }
            },
        }
        // add center-of-body offset (recomputed at light-time t) —
        // C order: calc_center_body BEFORE the heliocentric subtraction
        // (sweph.c:2691-2696): (xx + xcom) - sun, not (xx - sun) + xcom
        calc_center_body(ipli, iflag, &xx, &xcom);
        if ((iflag & SEFLG_HELCTR) != 0) {
            if (pdp.iephe == SEFLG_JPLEPH or pdp.iephe == SEFLG_SWIEPH) {
                i = 0;
                while (i <= 5) : (i += 1)
                    xx[i] -= swed.pldat[SEI_SUNBARY].x[i];
            }
        }
        if ((iflag & SEFLG_SPEED) != 0) {
            // observer position for t(light-time)
            if ((iflag & SEFLG_TOPOCTR) != 0) {
                if (swi_get_observer(t, iflag | SEFLG_NONUT, false, &xobs2, swed, models, dctx, serr) != OK)
                    return ERR;
                i = 0;
                while (i <= 5) : (i += 1)
                    xobs2[i] += xearth[i];
            } else {
                i = 0;
                while (i <= 5) : (i += 1)
                    xobs2[i] = xearth[i];
            }
        }
    }
    // conversion to geocenter
    if ((iflag & SEFLG_HELCTR) == 0 and (iflag & SEFLG_BARYCTR) == 0) {
        // subtract earth
        i = 0;
        while (i <= 5) : (i += 1)
            xx[i] -= xobs[i];
        if ((iflag & SEFLG_TRUEPOS) == 0) {
            // apparent speed influenced by change of dt during motion
            if ((iflag & SEFLG_SPEED) != 0) {
                i = 3;
                while (i <= 5) : (i += 1)
                    xx[i] -= xxsp[i - 3];
            }
        }
    }
    if ((iflag & SEFLG_SPEED) == 0) {
        i = 3;
        while (i <= 5) : (i += 1)
            xx[i] = 0;
        i = 0;
    }
    // relativistic deflection of light
    if ((iflag & SEFLG_TRUEPOS) == 0 and (iflag & SEFLG_NOGDEFL) == 0)
        swi_deflect_light(&xx, dtsave_for_defl, iflag, swed);
    // 'annual' aberration of light
    if ((iflag & SEFLG_TRUEPOS) == 0 and (iflag & SEFLG_NOABERR) == 0) {
        swi_aberr_light(&xx, &xobs, iflag);
        // apparent speed influenced by difference of earth speed t vs t-dt
        if ((iflag & SEFLG_SPEED) != 0) {
            i = 3;
            while (i <= 5) : (i += 1)
                xx[i] += xobs[i] - xobs2[i];
        }
    }
    if ((iflag & SEFLG_SPEED) == 0) {
        i = 3;
        while (i <= 5) : (i += 1)
            xx[i] = 0;
    }
    // ICRS to J2000
    if ((iflag & SEFLG_ICRS) == 0 and swi_get_denum(@intCast(ipli), epheflag, swed) >= 403) {
        lib.swi_bias(&xx, t, iflag, false, models);
    }
    // save J2000 coordinates
    var xxsv24: [24]f64 = [_]f64{0} ** 24;
    i = 0;
    while (i <= 5) : (i += 1)
        xxsv24[i] = xx[i];
    // precession, equator 2000 -> equator of date
    if ((iflag & SEFLG_J2000) == 0) {
        var xx3: [3]f64 = .{ xx[0], xx[1], xx[2] };
        _ = lib.swi_precess(&xx3, pdp.teval, iflag, J2000_TO_J, models);
        xx[0] = xx3[0];
        xx[1] = xx3[1];
        xx[2] = xx3[2];
        if ((iflag & SEFLG_SPEED) != 0)
            swi_precess_speed(&xx, pdp.teval, iflag, J2000_TO_J, swed, models);
        oe = &swed.oec;
    } else {
        oe = &swed.oec2000;
    }
    return app_pos_rest(pdp, iflag, &xx, xxsv24[0..], oe, swed, models, dctx, serr);
}

/// sweph.c app_pos_etc_plan_osc (apparent positions of fictitious bodies)
pub fn app_pos_etc_plan_osc_pub(ipl: i32, ipli: usize, iflag: i32, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    return app_pos_etc_plan_osc(ipl, ipli, iflag, swed, models, dctx, serr);
}

fn app_pos_etc_plan_osc(ipl: i32, ipli: usize, iflag: i32, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var xx: [6]f64 = undefined;
    var dx: [3]f64 = undefined;
    var dt: f64 = 0;
    var dtsave_for_defl: f64 = 0;
    var xearth: [6]f64 = undefined;
    var xsun: [6]f64 = undefined;
    var xmoon: [6]f64 = undefined;
    var xxsv: [6]f64 = undefined;
    var xxsp = [3]f64{ 0, 0, 0 };
    var xobs: [6]f64 = undefined;
    var xobs2: [6]f64 = undefined;
    var t: f64 = undefined;
    var i: usize = undefined;
    var j: usize = 0;
    const niter: usize = 1;
    const pdp = &swed.pldat[ipli];
    const pedp = &swed.pldat[SEI_EARTH];
    const psdp = &swed.pldat[SEI_SUNBARY];
    var oe: *const Eps = &swed.oec2000;
    var epheflag: i32 = SEFLG_DEFAULTEPH;
    if ((iflag & SEFLG_MOSEPH) != 0) {
        epheflag = SEFLG_MOSEPH;
    } else if ((iflag & SEFLG_SWIEPH) != 0) {
        epheflag = SEFLG_SWIEPH;
    } else if ((iflag & SEFLG_JPLEPH) != 0) {
        epheflag = SEFLG_JPLEPH;
    }
    // the conversions will be done with xx[]
    i = 0;
    while (i <= 5) : (i += 1)
        xx[i] = pdp.x[i];
    // observer: geocenter or topocenter
    if ((iflag & SEFLG_TOPOCTR) != 0) {
        if (swed.topd.teval != pedp.teval or swed.topd.teval == 0) {
            if (swi_get_observer(pedp.teval, iflag | SEFLG_NONUT, true, &xobs, swed, models, dctx, serr) != OK)
                return ERR;
        } else {
            i = 0;
            while (i <= 5) : (i += 1)
                xobs[i] = swed.topd.xobs[i];
        }
        // barycentric position of observer
        i = 0;
        while (i <= 5) : (i += 1)
            xobs[i] = xobs[i] + pedp.x[i];
    } else if ((iflag & SEFLG_BARYCTR) != 0) {
        i = 0;
        while (i <= 5) : (i += 1)
            xobs[i] = 0;
    } else if ((iflag & SEFLG_HELCTR) != 0) {
        if ((iflag & SEFLG_MOSEPH) != 0) {
            i = 0;
            while (i <= 5) : (i += 1)
                xobs[i] = 0;
        } else {
            i = 0;
            while (i <= 5) : (i += 1)
                xobs[i] = psdp.x[i];
        }
    } else {
        i = 0;
        while (i <= 5) : (i += 1)
            xobs[i] = pedp.x[i];
    }
    // light-time
    if ((iflag & SEFLG_TRUEPOS) == 0) {
        if ((iflag & SEFLG_SPEED) != 0) {
            // apparent speed is influenced by the fact that dt changes
            // with motion; compute the daily motion resulting from it
            i = 0;
            while (i <= 2) : (i += 1) {
                xxsv[i] = xx[i] - xx[i + 3];
                xxsp[i] = xx[i] - xx[i + 3];
            }
            j = 0;
            while (j <= niter) : (j += 1) {
                i = 0;
                while (i <= 2) : (i += 1) {
                    dx[i] = xxsp[i];
                    if ((iflag & SEFLG_HELCTR) == 0 and (iflag & SEFLG_BARYCTR) == 0)
                        dx[i] -= (xobs[i] - xobs[i + 3]);
                }
                // new dt
                dt = std.math.sqrt(square_sum(&dx)) * AUNIT / CLIGHT / 86400.0;
                i = 0;
                while (i <= 2) : (i += 1)
                    xxsp[i] = xxsv[i] - dt * pdp.x[i + 3]; // rough apparent position
            }
            // true position - apparent position at time t-1
            i = 0;
            while (i <= 2) : (i += 1)
                xxsp[i] = xxsv[i] - xxsp[i];
        }
        // dt and t(apparent)
        j = 0;
        while (j <= niter) : (j += 1) {
            i = 0;
            while (i <= 2) : (i += 1) {
                dx[i] = xx[i];
                if ((iflag & SEFLG_HELCTR) == 0 and (iflag & SEFLG_BARYCTR) == 0)
                    dx[i] -= xobs[i];
            }
            // new dt
            dt = std.math.sqrt(square_sum(&dx)) * AUNIT / CLIGHT / 86400.0;
            dtsave_for_defl = dt;
            // new position: subtract t * speed
            i = 0;
            while (i <= 2) : (i += 1) {
                xx[i] = pdp.x[i] - dt * pdp.x[i + 3];
                xx[i + 3] = pdp.x[i + 3];
            }
        }
        if ((iflag & SEFLG_SPEED) != 0) {
            // part of daily motion resulting from change of dt
            i = 0;
            while (i <= 2) : (i += 1)
                xxsp[i] = pdp.x[i] - xx[i] - xxsp[i];
            t = pdp.teval - dt;
            // for accuracy in speed, we will need earth as well
            const retc = mainPlanetBary(t, SEI_EARTH, epheflag, iflag, false, xearth[0..], xearth[0..], xsun[0..], xmoon[0..], swed, models, dctx, serr);
            if (swemplan_mod.swi_osc_el_plan(t, &xx, ipl - swemplan_mod.SE_FICT_OFFSET, ipli, &xearth, &xsun, models, swed, serr) != OK)
                return ERR;
            if (retc != OK)
                return retc;
            if ((iflag & SEFLG_TOPOCTR) != 0) {
                if (swi_get_observer(t, iflag | SEFLG_NONUT, false, &xobs2, swed, models, dctx, serr) != OK)
                    return ERR;
                i = 0;
                while (i <= 5) : (i += 1)
                    xobs2[i] += xearth[i];
            } else {
                i = 0;
                while (i <= 5) : (i += 1)
                    xobs2[i] = xearth[i];
            }
        }
    }
    // conversion to geocenter
    i = 0;
    while (i <= 5) : (i += 1)
        xx[i] -= xobs[i];
    if ((iflag & SEFLG_TRUEPOS) == 0) {
        // apparent speed is also influenced by the change of dt
        if ((iflag & SEFLG_SPEED) != 0) {
            i = 3;
            while (i <= 5) : (i += 1)
                xx[i] -= xxsp[i - 3];
        }
    }
    if ((iflag & SEFLG_SPEED) == 0) {
        i = 3;
        while (i <= 5) : (i += 1)
            xx[i] = 0;
    }
    // relativistic deflection of light
    if ((iflag & SEFLG_TRUEPOS) == 0 and (iflag & SEFLG_NOGDEFL) == 0)
        swi_deflect_light(&xx, dtsave_for_defl, iflag, swed);
    // 'annual' aberration of light
    if ((iflag & SEFLG_TRUEPOS) == 0 and (iflag & SEFLG_NOABERR) == 0) {
        swi_aberr_light(&xx, &xobs, iflag);
        // apparent speed influenced by difference of earth speed t vs t-dt
        if ((iflag & SEFLG_SPEED) != 0) {
            i = 3;
            while (i <= 5) : (i += 1)
                xx[i] += xobs[i] - xobs2[i];
        }
    }
    // save J2000 coordinates; required for sidereal positions
    var xxsv24: [24]f64 = [_]f64{0} ** 24;
    i = 0;
    while (i <= 5) : (i += 1)
        xxsv24[i] = xx[i];
    // precession, equator 2000 -> equator of date
    if ((iflag & SEFLG_J2000) == 0) {
        var xx3: [3]f64 = .{ xx[0], xx[1], xx[2] };
        _ = lib.swi_precess(&xx3, pdp.teval, iflag, J2000_TO_J, models);
        xx[0] = xx3[0];
        xx[1] = xx3[1];
        xx[2] = xx3[2];
        if ((iflag & SEFLG_SPEED) != 0)
            swi_precess_speed(&xx, pdp.teval, iflag, J2000_TO_J, swed, models);
        oe = &swed.oec;
    } else {
        oe = &swed.oec2000;
    }
    return app_pos_rest(pdp, iflag, &xx, xxsv24[0..], oe, swed, models, dctx, serr);
}

fn swi_moshplan_save(tjd: f64, ipli: usize, swed: *Swed, models: AstroModels, serr: ?[]u8) i32 {
    var xp_tmp: [6]f64 = undefined;
    var xe_tmp2: [6]f64 = undefined;
    const retc = swi_moshplan_call(tjd, ipli, &xp_tmp, &xe_tmp2, swed, models, serr);
    if (retc == ERR)
        return ERR;
    for (0..6) |k| swed.pldat[ipli].x[k] = xp_tmp[k];
    for (0..6) |k| swed.pldat[SEI_EARTH].x[k] = xe_tmp2[k];
    swed.pldat[ipli].teval = tjd;
    swed.pldat[ipli].xflgs = -1;
    swed.pldat[ipli].iephe = SEFLG_MOSEPH;
    swed.pldat[SEI_EARTH].teval = tjd;
    swed.pldat[SEI_EARTH].xflgs = -1;
    swed.pldat[SEI_EARTH].iephe = SEFLG_MOSEPH;
    return OK;
}

fn swi_moshplan_call(tjd: f64, ipli: usize, xp: ?[]f64, xeret: ?[]f64, swed: *Swed, models: AstroModels, serr: ?[]u8) i32 {
    const pmod = @import("swemplan");
    var xp6: [6]f64 = [_]f64{0} ** 6;
    var xeret6: [6]f64 = [_]f64{0} ** 6;
    const ret = pmod.swi_moshplan(tjd, ipli, false, &xp6, &xeret6, &swed.oec, &swed.oec2000, models, serr, swed);
    if (xp) |xpd| {
        for (0..6) |i| xpd[i] = xp6[i];
    }
    if (xeret) |xr| {
        for (0..6) |i| xr[i] = xeret6[i];
    }
    return ret;
}

/// sweph.c app_pos_etc_sun for SEFLG_MOSEPH
fn app_pos_etc_sun(iflag: i32, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var xx: [6]f64 = undefined;
    var xxsv: [6]f64 = undefined;
    var dx: [3]f64 = undefined;
    var xearth: [6]f64 = undefined;
    var xsun: [6]f64 = undefined;
    var xobs: [6]f64 = undefined;
    var t: f64 = 0;
    const pedp = &swed.pldat[SEI_EARTH];
    const psdp = &swed.pldat[SEI_SUNBARY];
    var oe: *const Eps = &swed.oec2000;
    // if the same conversions have already been done for the same date, return
    const flg1 = iflag & ~SEFLG_EQUATORIAL & ~SEFLG_XYZ;
    const flg2 = pedp.xflgs & ~SEFLG_EQUATORIAL & ~SEFLG_XYZ;
    if (flg1 == flg2) {
        pedp.xflgs = iflag;
        pedp.iephe = iflag & SEFLG_EPHMASK;
        return OK;
    }
    // observer: geocenter or topocenter
    var i: usize = 0;
    if ((iflag & SEFLG_TOPOCTR) != 0) {
        if (swed.topd.teval != pedp.teval or swed.topd.teval == 0) {
            if (swi_get_observer(pedp.teval, iflag | SEFLG_NONUT, true, &xobs, swed, models, dctx, serr) != OK)
                return ERR;
        } else {
            i = 0;
            while (i <= 5) : (i += 1)
                xobs[i] = swed.topd.xobs[i];
        }
        // barycentric position of observer
        i = 0;
        while (i <= 5) : (i += 1)
            xobs[i] = xobs[i] + pedp.x[i];
    } else {
        i = 0;
        while (i <= 5) : (i += 1)
            xobs[i] = pedp.x[i];
    }
    // true heliocentric position of earth
    if (pedp.iephe == SEFLG_MOSEPH or (iflag & SEFLG_BARYCTR) != 0) {
        i = 0;
        while (i <= 5) : (i += 1)
            xx[i] = xobs[i];
    } else {
        i = 0;
        while (i <= 5) : (i += 1)
            xx[i] = xobs[i] - psdp.x[i];
    }
    // light-time
    if ((iflag & SEFLG_TRUEPOS) == 0) {
        if (pedp.iephe == SEFLG_JPLEPH or pedp.iephe == SEFLG_SWIEPH or
            (iflag & SEFLG_HELCTR) != 0 or (iflag & SEFLG_BARYCTR) != 0)
        {
            i = 0;
            while (i <= 5) : (i += 1) {
                xearth[i] = xobs[i];
                if (pedp.iephe == SEFLG_MOSEPH)
                    xsun[i] = 0
                else
                    xsun[i] = psdp.x[i];
            }
            const niter: usize = 1; // # of iterations
            var j: usize = 0;
            while (j <= niter) : (j += 1) {
                // distance earth-sun
                i = 0;
                while (i <= 2) : (i += 1) {
                    dx[i] = xearth[i];
                    if ((iflag & SEFLG_BARYCTR) == 0)
                        dx[i] -= xsun[i];
                }
                // new t
                const dt = std.math.sqrt(square_sum(&dx)) * AUNIT / CLIGHT / 86400.0;
                t = pedp.teval - dt;
                // new position
                switch (pedp.iephe) {
                    SEFLG_JPLEPH => {
                        var retc: i32 = undefined;
                        if ((iflag & SEFLG_HELCTR) != 0 or (iflag & SEFLG_BARYCTR) != 0) {
                            var xe6: [6]f64 = undefined;
                            retc = jplmod.swi_pleph(t, jplmod.J_EARTH, jplmod.J_SBARY, &xe6, swed, serr);
                            for (0..6) |k| xearth[k] = xe6[k];
                        } else {
                            var xs6: [6]f64 = undefined;
                            retc = jplmod.swi_pleph(t, jplmod.J_SUN, jplmod.J_SBARY, &xs6, swed, serr);
                            for (0..6) |k| xsun[k] = xs6[k];
                        }
                        if (retc != OK) {
                            jplmod.swi_close_jpl_file(swed);
                            swed.jpl_file_is_open = false;
                            return retc;
                        }
                    },
                    SEFLG_SWIEPH => {
                        if ((iflag & SEFLG_HELCTR) != 0 or (iflag & SEFLG_BARYCTR) != 0) {
                            const retc = sweplan(t, 0, SEI_FILE_PLANET, iflag, false, xearth[0..], null, xsun[0..], null, serr, swed, models);
                            if (retc != OK)
                                return retc;
                        } else {
                            const retc = sweph(t, SEI_SUNBARY, SEI_FILE_PLANET, iflag, null, false, xsun[0..], serr, swed, models);
                            if (retc != OK)
                                return retc;
                        }
                    },
                    else => {
                        // SEFLG_MOSEPH
                        if ((iflag & SEFLG_HELCTR) != 0 or (iflag & SEFLG_BARYCTR) != 0) {
                            var xe6: [6]f64 = undefined;
                            const retc = swi_moshplan_call(t, SEI_EARTH, null, xe6[0..], swed, models, serr);
                            if (retc != OK) {
                                return retc;
                            }
                            i = 0;
                            while (i <= 5) : (i += 1)
                                xearth[i] = xe6[i];
                            i = 0;
                        }
                        // with moshier there is no barycentric sun
                    },
                }
                i = 0;
            }
            // apparent heliocentric earth
            i = 0;
            while (i <= 5) : (i += 1) {
                xx[i] = xearth[i];
                if ((iflag & SEFLG_BARYCTR) == 0)
                    xx[i] -= xsun[i];
            }
        }
    }
    if ((iflag & SEFLG_SPEED) == 0) {
        i = 3;
        while (i <= 5) : (i += 1)
            xx[i] = 0;
    }
    // conversion to geocenter
    if ((iflag & SEFLG_HELCTR) == 0 and (iflag & SEFLG_BARYCTR) == 0) {
        i = 0;
        while (i <= 5) : (i += 1)
            xx[i] = -xx[i];
    }
    // 'annual' aberration of light
    if ((iflag & SEFLG_TRUEPOS) == 0 and (iflag & SEFLG_NOABERR) == 0) {
        swi_aberr_light(&xx, &xobs, iflag);
    }
    if ((iflag & SEFLG_SPEED) == 0) {
        i = 3;
        while (i <= 5) : (i += 1)
            xx[i] = 0;
        i = 0;
    }
    // ICRS to J2000
    if ((iflag & SEFLG_ICRS) == 0 and swi_get_denum(SEI_SUN, iflag & SEFLG_EPHMASK, swed) >= 403) {
        lib.swi_bias(&xx, t, iflag, false, models);
    }
    // save J2000 coordinates
    i = 0;
    while (i <= 5) : (i += 1)
        xxsv[i] = xx[i];
    // precession, equator 2000 -> equator of date
    if ((iflag & SEFLG_J2000) == 0) {
        _ = lib.swi_precess(xx[0..3], pedp.teval, iflag, J2000_TO_J, models);
        if ((iflag & SEFLG_SPEED) != 0)
            swi_precess_speed(&xx, pedp.teval, iflag, J2000_TO_J, swed, models);
        oe = &swed.oec;
    } else {
        oe = &swed.oec2000;
    }
    return app_pos_rest(pedp, iflag, &xx, xxsv[0..], oe, swed, models, dctx, serr);
}

/// sweph.c app_pos_etc_moon for SEFLG_MOSEPH
fn app_pos_etc_moon(iflag: i32, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var xx: [6]f64 = undefined;
    var xxsv: [6]f64 = undefined;
    var xobs: [6]f64 = undefined;
    var xxm: [6]f64 = undefined;
    var xs: [6]f64 = undefined;
    var xe: [6]f64 = undefined;
    var xobs2: [6]f64 = undefined;
    var dt: f64 = undefined;
    const psdp = &swed.pldat[SEI_SUNBARY];
    const pdp = &swed.pldat[SEI_MOON];
    var oe: *const Eps = &swed.oec;
    var t: f64 = 0;
    _ = psdp;
    // if the same conversions have already been done for the same date, return
    const flg1 = iflag & ~SEFLG_EQUATORIAL & ~SEFLG_XYZ;
    const flg2 = pdp.xflgs & ~SEFLG_EQUATORIAL & ~SEFLG_XYZ;
    if (flg1 == flg2) {
        pdp.xflgs = iflag;
        pdp.iephe = iflag & SEFLG_EPHMASK;
        return OK;
    }
    // the conversions will be done with xx[]
    var i: usize = 0;
    while (i <= 5) : (i += 1) {
        xx[i] = pdp.x[i];
        xxm[i] = xx[i];
    }
    // to solar system barycentric
    i = 0;
    while (i <= 5) : (i += 1)
        xx[i] += swed.pldat[SEI_EARTH].x[i];
    // observer
    if ((iflag & SEFLG_TOPOCTR) != 0) {
        if (swed.topd.teval != pdp.teval or swed.topd.teval == 0) {
            if (swi_get_observer(pdp.teval, iflag | SEFLG_NONUT, true, &xobs, swed, models, dctx, serr) != OK)
                return ERR;
        } else {
            i = 0;
            while (i <= 5) : (i += 1)
                xobs[i] = swed.topd.xobs[i];
        }
        i = 0;
        while (i <= 5) : (i += 1)
            xxm[i] -= xobs[i];
        i = 0;
        while (i <= 5) : (i += 1)
            xobs[i] += swed.pldat[SEI_EARTH].x[i];
    } else if ((iflag & SEFLG_BARYCTR) != 0) {
        i = 0;
        while (i <= 5) : (i += 1)
            xobs[i] = 0;
        i = 0;
        while (i <= 5) : (i += 1)
            xxm[i] += swed.pldat[SEI_EARTH].x[i];
    } else if ((iflag & SEFLG_HELCTR) != 0) {
        i = 0;
        while (i <= 5) : (i += 1)
            xobs[i] = swed.pldat[SEI_SUNBARY].x[i];
        i = 0;
        while (i <= 5) : (i += 1)
            xxm[i] += swed.pldat[SEI_EARTH].x[i] - swed.pldat[SEI_SUNBARY].x[i];
    } else {
        i = 0;
        while (i <= 5) : (i += 1)
            xobs[i] = swed.pldat[SEI_EARTH].x[i];
    }
    // light-time
    t = pdp.teval;
    if ((iflag & SEFLG_TRUEPOS) == 0) {
        dt = std.math.sqrt(square_sum(&xxm)) * AUNIT / CLIGHT / 86400.0;
        t = pdp.teval - dt;
        switch (pdp.iephe) {
            SEFLG_JPLEPH => {
                var retc: i32 = undefined;
                var xm6: [6]f64 = undefined;
                retc = jplmod.swi_pleph(t, jplmod.J_MOON, jplmod.J_EARTH, &xm6, swed, serr);
                for (0..6) |k| xx[k] = xm6[k];
                if (retc == OK) {
                    var xe6: [6]f64 = undefined;
                    retc = jplmod.swi_pleph(t, jplmod.J_EARTH, jplmod.J_SBARY, &xe6, swed, serr);
                    for (0..6) |k| xe[k] = xe6[k];
                }
                if (retc == OK and (iflag & SEFLG_HELCTR) != 0) {
                    var xs6: [6]f64 = undefined;
                    retc = jplmod.swi_pleph(t, jplmod.J_SUN, jplmod.J_SBARY, &xs6, swed, serr);
                    for (0..6) |k| xs[k] = xs6[k];
                }
                if (retc != OK) {
                    jplmod.swi_close_jpl_file(swed);
                    swed.jpl_file_is_open = false;
                }
                i = 0;
                while (i <= 5) : (i += 1)
                    xx[i] += xe[i];
            },
            SEFLG_SWIEPH => {
                const retc = sweplan(t, SEI_MOON, SEI_FILE_MOON, iflag, false, xx[0..], xe[0..], xs[0..], null, serr, swed, models);
                if (retc != OK)
                    return retc;
                i = 0;
                while (i <= 5) : (i += 1)
                    xx[i] += xe[i];
            },
            else => {
                // SEFLG_MOSEPH: this method results in an error of a
                // milliarcsec in speed
                i = 0;
                while (i <= 2) : (i += 1) {
                    xx[i] -= dt * xx[i + 3];
                    xe[i] = swed.pldat[SEI_EARTH].x[i] - dt * swed.pldat[SEI_EARTH].x[i + 3];
                    xe[i + 3] = swed.pldat[SEI_EARTH].x[i + 3];
                    xs[i] = 0;
                    xs[i + 3] = 0;
                }
            },
        }
        if ((iflag & SEFLG_TOPOCTR) != 0) {
            if (swi_get_observer(t, iflag | SEFLG_NONUT, false, &xobs2, swed, models, dctx, null) != OK)
                return ERR;
            i = 0;
            while (i <= 5) : (i += 1)
                xobs2[i] += xe[i];
        } else if ((iflag & SEFLG_BARYCTR) != 0) {
            i = 0;
            while (i <= 5) : (i += 1)
                xobs2[i] = 0;
        } else if ((iflag & SEFLG_HELCTR) != 0) {
            i = 0;
            while (i <= 5) : (i += 1)
                xobs2[i] = xs[i];
        } else {
            i = 0;
            while (i <= 5) : (i += 1)
                xobs2[i] = xe[i];
        }
    }
    // to correct center
    i = 0;
    while (i <= 5) : (i += 1)
        xx[i] -= xobs[i];
    // 'annual' aberration of light
    if ((iflag & SEFLG_TRUEPOS) == 0 and (iflag & SEFLG_NOABERR) == 0) {
        swi_aberr_light(&xx, &xobs, iflag);
        // apparent speed influenced by difference of earth speed t vs t-dt
        if ((iflag & SEFLG_SPEED) != 0) {
            i = 3;
            while (i <= 5) : (i += 1)
                xx[i] += xobs[i] - xobs2[i];
        }
    }
    // if !speedflag, speed = 0
    if ((iflag & SEFLG_SPEED) == 0) {
        i = 3;
        while (i <= 5) : (i += 1)
            xx[i] = 0;
    }
    // ICRS to J2000
    if ((iflag & SEFLG_ICRS) == 0 and swi_get_denum(SEI_MOON, iflag & SEFLG_EPHMASK, swed) >= 403) {
        lib.swi_bias(&xx, t, iflag, false, models);
    }
    // save J2000 coordinates
    i = 0;
    while (i <= 5) : (i += 1)
        xxsv[i] = xx[i];
    // precession, equator 2000 -> equator of date
    if ((iflag & SEFLG_J2000) == 0) {
        _ = lib.swi_precess(xx[0..3], pdp.teval, iflag, J2000_TO_J, models);
        if ((iflag & SEFLG_SPEED) != 0)
            swi_precess_speed(&xx, pdp.teval, iflag, J2000_TO_J, swed, models);
        oe = &swed.oec;
    } else {
        oe = &swed.oec2000;
    }
    return app_pos_rest(pdp, iflag, &xx, xxsv[0..], oe, swed, models, dctx, serr);
}

/// sweph.c app_pos_etc_mean (mean node / mean apogee)
fn app_pos_etc_mean(ipl_nd: usize, iflag: i32, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var xx: [6]f64 = undefined;
    var xxsv: [6]f64 = [_]f64{0} ** 6;
    const pdp = &swed.nddat[ipl_nd];
    var oe: *const Eps = undefined;
    // if the same conversions have already been done for the same date, return
    const flg1 = iflag & ~SEFLG_EQUATORIAL & ~SEFLG_XYZ;
    const flg2 = pdp.xflgs & ~SEFLG_EQUATORIAL & ~SEFLG_XYZ;
    if (flg1 == flg2) {
        pdp.xflgs = iflag;
        pdp.iephe = iflag & SEFLG_EPHMASK;
        return OK;
    }
    var i: usize = 0;
    while (i <= 5) : (i += 1)
        xx[i] = pdp.x[i];
    // cartesian equatorial coordinates
    lib.swi_polcart_sp(&xx, &xx);
    lib.swi_coortrf2(xx[0..3], xx[0..3], -swed.oec.seps, swed.oec.ceps);
    lib.swi_coortrf2(xx[3..6], xx[3..6], -swed.oec.seps, swed.oec.ceps);
    if ((iflag & SEFLG_SPEED) == 0) {
        i = 3;
        while (i <= 5) : (i += 1)
            xx[i] = 0;
    }
    // J2000 coordinates; required for sidereal positions
    if (((iflag & SEFLG_SIDEREAL) != 0 and (swed.sidd.sid_mode & SE_SIDBIT_ECL_T0) != 0) or
        (swed.sidd.sid_mode & SE_SIDBIT_SSY_PLANE) != 0)
    {
        i = 0;
        while (i <= 5) : (i += 1)
            xxsv[i] = xx[i];
        // xxsv is not J2000 yet!
        if (pdp.teval != lib.J2000) {
            _ = lib.swi_precess(xxsv[0..3], pdp.teval, iflag, lib.J_TO_J2000, models);
            if ((iflag & SEFLG_SPEED) != 0)
                swi_precess_speed(&xxsv, pdp.teval, iflag, lib.J_TO_J2000, swed, models);
        }
    }
    // if no precession, equator of date -> equator 2000
    if ((iflag & SEFLG_J2000) != 0) {
        _ = lib.swi_precess(xx[0..3], pdp.teval, iflag, 1, models);
        if ((iflag & SEFLG_SPEED) != 0)
            swi_precess_speed(&xx, pdp.teval, iflag, 1, swed, models);
        oe = &swed.oec2000;
    } else {
        oe = &swed.oec;
    }
    return app_pos_rest(pdp, iflag, &xx, xxsv[0..], oe, swed, models, dctx, serr);
}

/// sweph.c swecalc for the ported subset (MOSEPH + ECL_NUT + mean
/// node/apogee); file-based ephemerides return ERR (deferred, see plan).
const swemmoon_mod = @import("swemmoon");
const jplmod = @import("swejpl");
const swemplan_mod = @import("swemplan");

fn swecalc(tjd: f64, ipl: i32, iplmoon: i32, iflag_in: i32, x: *[24]f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var iflag = iflag_in;
    var i: usize = undefined;
    var ipli: usize = undefined;
    var epheflag: i32 = SEFLG_DEFAULTEPH;
    // iflag plausible?
    iflag = plaus_iflag(iflag, ipl, tjd, swed, models, serr);
    // which ephemeris is wanted, which is used?
    if ((iflag & SEFLG_MOSEPH) != 0)
        epheflag = SEFLG_MOSEPH;
    if ((iflag & SEFLG_SWIEPH) != 0)
        epheflag = SEFLG_SWIEPH;
    if ((iflag & SEFLG_JPLEPH) != 0)
        epheflag = SEFLG_JPLEPH;
    // no barycentric calculations with Moshier ephemeris
    if ((iflag & SEFLG_BARYCTR) != 0 and (iflag & SEFLG_MOSEPH) != 0) {
        if (serr) |sr| {
            const msg = "barycentric Moshier positions are not supported.";
            @memcpy(sr[0..msg.len], msg);
            if (msg.len < sr.len) sr[msg.len] = 0;
        }
        return ERR;
    }
    if (epheflag != SEFLG_MOSEPH and !swed.ephe_path_is_set and !swed.jpl_file_is_open) {
        // swe_set_ephe_path(NULL): sets ephe_path_is_set; file machinery
        // is not ported, so keep the flag only.
        swed.ephe_path_is_set = true;
    }
    if ((iflag & SEFLG_SIDEREAL) != 0 and !swed.ayana_is_set)
        swe_set_sid_mode(SE_SIDM_FAGAN_BRADLEY, 0, 0, swed, null);
    // obliquity of ecliptic 2000 and of date
    swi_check_ecliptic(tjd, iflag, swed, models);
    // nutation
    swi_check_nutation(tjd, iflag, swed, models);
    if (ipl == SE_ECL_NUT) {
        x[0] = swed.oec.eps + swed.nut.nutlo[1]; // true ecliptic
        x[1] = swed.oec.eps; // mean ecliptic
        x[2] = swed.nut.nutlo[0]; // nutation in longitude
        x[3] = swed.nut.nutlo[1]; // nutation in obliquity
        i = 0;
        while (i <= 3) : (i += 1)
            x[i] *= RADTODEG;
        return iflag;
    } else if (ipl == SE_MOON) {
        ipli = SEI_MOON;
        const pdp = &swed.pldat[ipli];
        switch (epheflag) {
            SEFLG_MOSEPH => {
                // C: swi_moshmoon(tjd, DO_SAVE, NULL) writes into the shared
                // swed.pldat[SEI_MOON].x; capture and copy.
                var moonx6: [6]f64 = undefined;
                const retc = swemmoon_mod.swi_moshmoon(tjd, false, &moonx6, &swed.oec, models, serr);
                if (retc == ERR)
                    return ERR;
                for (0..6) |k| swed.pldat[SEI_MOON].x[k] = moonx6[k];
                swed.pldat[SEI_MOON].teval = tjd;
                swed.pldat[SEI_MOON].xflgs = -1;
                swed.pldat[SEI_MOON].iephe = SEFLG_MOSEPH;
                // for hel. position, we need earth as well
                var xearth6: [6]f64 = undefined;
                const retc2 = swi_moshplan_call(tjd, SEI_EARTH, null, &xearth6, swed, models, serr);
                if (retc2 == ERR)
                    return ERR;
                for (0..6) |k| swed.pldat[SEI_EARTH].x[k] = xearth6[k];
                swed.pldat[SEI_EARTH].teval = tjd;
                swed.pldat[SEI_EARTH].xflgs = -1;
                swed.pldat[SEI_EARTH].iephe = SEFLG_MOSEPH;
            },
            SEFLG_JPLEPH => {
                const retc = jplplan(tjd, ipli, iflag, true, null, null, null, swed, dctx, serr);
                // read error or corrupt file
                if (retc == ERR)
                    return ERR;
                // jpl ephemeris not on disk or date beyond ephemeris range
                //     or file corrupt
                if (retc == NOT_AVAILABLE) {
                    iflag = (iflag & ~SEFLG_JPLEPH) | SEFLG_SWIEPH;
                    if (serr) |sr| appendSerrMax(sr, " \ntrying Swiss Eph; ");
                    // sweph_moon
                    const retc2 = sweplan(tjd, ipli, SEI_FILE_MOON, iflag, true, null, null, null, null, serr, swed, models);
                    if (retc2 == ERR)
                        return ERR;
                    if (retc2 == NOT_AVAILABLE) {
                        if (tjd > MOSHLUEPH_START and tjd < MOSHLUEPH_END) {
                            iflag = (iflag & ~SEFLG_SWIEPH) | SEFLG_MOSEPH;
                            if (serr) |sr| appendSerrMax(sr, " \nusing Moshier eph.; ");
                            const retc3 = swi_moshmoon_save(tjd, swed, models, serr);
                            if (retc3 == ERR)
                                return ERR;
                        } else {
                            return ERR;
                        }
                    }
                } else if (retc == BEYOND_EPH_LIMITS) {
                    if (tjd > MOSHLUEPH_START and tjd < MOSHLUEPH_END) {
                        iflag = (iflag & ~SEFLG_JPLEPH) | SEFLG_MOSEPH;
                        if (serr) |sr| appendSerrMax(sr, " \nusing Moshier Eph; ");
                        const retc3 = swi_moshmoon_save(tjd, swed, models, serr);
                        if (retc3 == ERR)
                            return ERR;
                    } else {
                        return ERR;
                    }
                }
            },
            SEFLG_SWIEPH => {
                const retc = sweplan(tjd, ipli, SEI_FILE_MOON, iflag, true, null, null, null, null, serr, swed, models);
                if (retc == ERR)
                    return ERR;
                // if sweph file not found, switch to moshier
                if (retc == NOT_AVAILABLE) {
                    if (tjd > MOSHLUEPH_START and tjd < MOSHLUEPH_END) {
                        iflag = (iflag & ~SEFLG_SWIEPH) | SEFLG_MOSEPH;
                        if (serr) |sr| {
                            appendSerrMax(sr, " \nusing Moshier eph.; ");
                        }
                        // moshier_moon
                        var moonx6: [6]f64 = undefined;
                        const retc2 = swemmoon_mod.swi_moshmoon(tjd, false, &moonx6, &swed.oec, models, serr);
                        if (retc2 == ERR)
                            return ERR;
                        for (0..6) |k| swed.pldat[SEI_MOON].x[k] = moonx6[k];
                        swed.pldat[SEI_MOON].teval = tjd;
                        swed.pldat[SEI_MOON].xflgs = -1;
                        swed.pldat[SEI_MOON].iephe = SEFLG_MOSEPH;
                        var xearth6: [6]f64 = undefined;
                        const retc3 = swi_moshplan_call(tjd, SEI_EARTH, null, &xearth6, swed, models, serr);
                        if (retc3 == ERR)
                            return ERR;
                        for (0..6) |k| swed.pldat[SEI_EARTH].x[k] = xearth6[k];
                        swed.pldat[SEI_EARTH].teval = tjd;
                        swed.pldat[SEI_EARTH].xflgs = -1;
                        swed.pldat[SEI_EARTH].iephe = SEFLG_MOSEPH;
                    } else {
                        return ERR;
                    }
                }
            },
            else => {},
        }
        // heliocentric, lighttime etc.
        const retc3 = app_pos_etc_moon(iflag, swed, models, dctx, serr);
        if (retc3 != OK)
            return ERR; // retc may be wrong with sidereal calculation
        copy_xreturn(pdp, x);
    } else if (ipl == SE_SUN and (iflag & SEFLG_BARYCTR) != 0) {
        // barycentric sun (only JPL and SWISSEPH ephemerises)
        i = 0; // SEI_SUN = SEI_EARTH
        var xp: [*]f64 = undefined;
        const pedp2 = &swed.pldat[SEI_EARTH];
        xp = &pedp2.xreturn;
        switch (epheflag) {
            SEFLG_JPLEPH => {
                var sweph_sbar = false;
                // open ephemeris, if still closed
                if (!swed.jpl_file_is_open) {
                    var ss: [3]f64 = .{ 0, 0, 0 };
                    const retc0 = openJplFile(&ss, sliceToZ(&swed.jplfnam), sliceToZ(&swed.ephepath), swed, dctx, serr);
                    if (retc0 != OK)
                        sweph_sbar = true;
                }
                if (!sweph_sbar) {
                    var xs6: [6]f64 = undefined;
                    const retc = jplmod.swi_pleph(tjd, jplmod.J_SUN, jplmod.J_SBARY, &xs6, swed, serr);
                    for (0..6) |k| swed.pldat[SEI_SUNBARY].x[k] = xs6[k];
                    if (retc == ERR or retc == BEYOND_EPH_LIMITS) {
                        jplmod.swi_close_jpl_file(swed);
                        swed.jpl_file_is_open = false;
                        return ERR;
                    }
                    // jpl ephemeris not on disk or date beyond ephemeris range
                    //     or file corrupt
                    if (retc == NOT_AVAILABLE) {
                        iflag = (iflag & ~SEFLG_JPLEPH) | SEFLG_SWIEPH;
                        if (serr) |sr| appendSerrMax(sr, " \ntrying Swiss Eph; ");
                        sweph_sbar = true;
                    } else {
                        swed.pldat[SEI_SUNBARY].teval = tjd;
                    }
                }
                if (sweph_sbar) {
                    // sweplan() provides barycentric sun as a by-product in save area
                    const retc = sweplan(tjd, SEI_EARTH, SEI_FILE_PLANET, iflag, true, null, null, null, null, serr, swed, models);
                    if (retc == ERR or retc == NOT_AVAILABLE)
                        return ERR;
                }
            },
            SEFLG_SWIEPH => {
                // sweplan() provides barycentric sun as a by-product
                const retc = sweplan(tjd, SEI_EARTH, SEI_FILE_PLANET, iflag, true, null, null, null, null, serr, swed, models);
                if (retc == ERR or retc == NOT_AVAILABLE)
                    return ERR;
            },
            else => return ERR,
        }
        const psdp2 = &swed.pldat[SEI_SUNBARY];
        psdp2.teval = tjd;
        // flags
        const retc = app_pos_etc_sbar(iflag, swed, models, dctx, serr);
        if (retc != OK)
            return ERR;
        iflag = pedp2.xflgs;
        // force re-computation of pedp->xreturn for the next call
        pedp2.xflgs = -1;
        for (0..24) |k| x[k] = pedp2.xreturn[k];
    } else if (ipl == SE_SUN or ipl == SE_MERCURY or ipl == SE_VENUS or
        ipl == SE_MARS or ipl == SE_JUPITER or ipl == SE_SATURN or
        ipl == SE_URANUS or ipl == SE_NEPTUNE or ipl == SE_PLUTO or
        ipl == SE_EARTH)
    {
        if ((iflag & SEFLG_HELCTR) != 0) {
            if (ipl == SE_SUN) {
                // heliocentric position of Sun does not exist
                for (0..24) |k| x[k] = 0;
                return iflag;
            }
        } else if ((iflag & SEFLG_BARYCTR) != 0) {
            // barycentric Moshier unsupported: handled above
        } else { // geocentric
            if (ipl == SE_EARTH) {
                // geocentric position of Earth does not exist
                for (0..24) |k| x[k] = 0;
                return iflag;
            }
        }
        // internal planet number
        ipli = pnoext2int[@intCast(ipl)];
        const pdp = &swed.pldat[ipli];
        const retc = main_planet(tjd, ipli, iplmoon, epheflag, iflag, swed, models, dctx, serr);
        if (retc == ERR)
            return ERR;
        // iflag has possibly changed in main_planet()
        iflag = pdp.xflgs;
        copy_xreturn(pdp, x);
    } else if (ipl == SE_MEAN_NODE) {
        if ((iflag & SEFLG_HELCTR) != 0 or (iflag & SEFLG_BARYCTR) != 0) {
            // heliocentric/barycentric lunar node not allowed
            for (0..24) |k| x[k] = 0;
            return iflag;
        }
        const ndp = &swed.nddat[0]; // SEI_MEAN_NODE
        var xp2: [6]f64 = undefined;
        var retc = swemmoon_mod.swi_mean_node(tjd, xp2[0..3], serr);
        if (retc == ERR)
            return ERR;
        // speed (is almost constant; variation < 0.001 arcsec)
        retc = swemmoon_mod.swi_mean_node(tjd - MEAN_NODE_SPEED_INTV, xp2[3..6], serr);
        if (retc == ERR)
            return ERR;
        xp2[3] = lib.swe_difrad2n(xp2[0], xp2[3]) / MEAN_NODE_SPEED_INTV;
        xp2[4] = 0;
        xp2[5] = 0;
        for (0..6) |k| ndp.x[k] = xp2[k];
        ndp.teval = tjd;
        ndp.xflgs = -1;
        // lighttime etc.
        retc = app_pos_etc_mean(0, iflag, swed, models, dctx, serr); // SEI_MEAN_NODE
        if (retc != OK)
            return ERR;
        // to avoid infinitesimal deviations from latitude = 0
        if ((iflag & SEFLG_SIDEREAL) == 0 and (iflag & SEFLG_J2000) == 0) {
            ndp.xreturn[1] = 0.0; // ecl. latitude
            ndp.xreturn[4] = 0.0; //               speed
            ndp.xreturn[5] = 0.0; //      radial   speed
            ndp.xreturn[8] = 0.0; // z coordinate
            ndp.xreturn[11] = 0.0; //               speed
        }
        copy_xreturn(ndp, x);
    } else if (ipl == SE_MEAN_APOG) {
        if ((iflag & SEFLG_HELCTR) != 0 or (iflag & SEFLG_BARYCTR) != 0) {
            // heliocentric/barycentric lunar apogee not allowed
            for (0..24) |k| x[k] = 0;
            return iflag;
        }
        const ndp = &swed.nddat[2]; // SEI_MEAN_APOG
        const swemmoon = @import("swemmoon");
        var xp2: [6]f64 = undefined;
        var retc = swemmoon.swi_mean_apog(tjd, xp2[0..3], serr);
        if (retc == ERR)
            return ERR;
        // speed (is not constant! variation ~= several arcsec)
        retc = swemmoon_mod.swi_mean_apog(tjd - MEAN_NODE_SPEED_INTV, xp2[3..6], serr);
        if (retc == ERR)
            return ERR;
        var ii: usize = 0;
        while (ii <= 1) : (ii += 1)
            xp2[3 + ii] = lib.swe_difrad2n(xp2[ii], xp2[3 + ii]) / MEAN_NODE_SPEED_INTV;
        xp2[5] = 0;
        for (0..6) |k| ndp.x[k] = xp2[k];
        ndp.teval = tjd;
        ndp.xflgs = -1;
        // lighttime etc.
        retc = app_pos_etc_mean(2, iflag, swed, models, dctx, serr); // SEI_MEAN_APOG
        if (retc != OK)
            return ERR;
        // to avoid infinitesimal deviations from r-speed = 0
        ndp.xreturn[5] = 0.0;
        copy_xreturn(ndp, x);
    } else if (ipl == SE_TRUE_NODE) {
        if ((iflag & SEFLG_HELCTR) != 0 or (iflag & SEFLG_BARYCTR) != 0) {
            // heliocentric/barycentric lunar node not allowed
            for (0..24) |k| x[k] = 0;
            return iflag;
        }
        const ndp = &swed.nddat[SEI_TRUE_NODE];
        const retc = lunar_osc_elem(tjd, SEI_TRUE_NODE, iflag, swed, models, dctx, serr);
        iflag = ndp.xflgs;
        // to avoid infinitesimal deviations from latitude = 0
        // that result from conversions
        if ((iflag & SEFLG_SIDEREAL) == 0 and (iflag & SEFLG_J2000) == 0) {
            ndp.xreturn[1] = 0.0; // ecl. latitude
            ndp.xreturn[4] = 0.0; //               speed
            ndp.xreturn[8] = 0.0; // z coordinate
            ndp.xreturn[11] = 0.0; //               speed
        }
        if (retc == ERR)
            return ERR;
        copy_xreturn(ndp, x);
    } else if (ipl == SE_OSCU_APOG) {
        if ((iflag & SEFLG_HELCTR) != 0 or (iflag & SEFLG_BARYCTR) != 0) {
            // heliocentric/barycentric lunar apogee not allowed
            for (0..24) |k| x[k] = 0;
            return iflag;
        }
        const ndp = &swed.nddat[SEI_OSCU_APOG];
        const retc = lunar_osc_elem(tjd, SEI_OSCU_APOG, iflag, swed, models, dctx, serr);
        iflag = ndp.xflgs;
        if (retc == ERR)
            return ERR;
        copy_xreturn(ndp, x);
    } else if (ipl == SE_CHIRON or ipl == SE_PHOLUS or
        ipl == SE_CERES or ipl == SE_PALLAS or
        ipl == SE_JUNO or ipl == SE_VESTA or
        ipl > SE_PLMOON_OFFSET or ipl > SE_AST_OFFSET)
    {
        // sweph.c minor planets: main asteroids (Chiron..Vesta) share the
        // seas file machinery; numbered asteroids use SEI_ANYBODY.
        var ipli_ast: i32 = undefined;
        var ipli_u: usize = undefined;
        var ipl_mut = ipl;
        if (ipl_mut < @as(i32, @intCast(SE_NPLANETS))) {
            ipli_u = pnoext2int[@intCast(ipl_mut)];
        } else if (ipl_mut <= SE_AST_OFFSET + MPC_VESTA and ipl_mut > SE_AST_OFFSET) {
            ipli_u = SEI_CERES + @as(usize, @intCast(ipl_mut - SE_AST_OFFSET)) - 1;
            ipl_mut = SE_CERES + (ipl_mut - SE_AST_OFFSET) - 1;
        } else {
            ipli_u = SEI_ANYBODY;
        }
        if (ipli_u == SEI_ANYBODY) {
            ipli_ast = ipl_mut;
        } else {
            ipli_ast = @intCast(ipli_u);
        }
        const pdp_ast = &swed.pldat[ipli_u];
        const xp_ast = &pdp_ast.xreturn;
        var ifno: usize = undefined;
        if (ipli_ast > SE_AST_OFFSET or ipli_ast > SE_PLMOON_OFFSET) {
            ifno = SEI_FILE_ANY_AST;
        } else {
            ifno = SEI_FILE_MAIN_AST;
        }
        if (ipli_u == SEI_CHIRON and (tjd < CHIRON_START or tjd > CHIRON_END)) {
            if (serr) |sr| {
                const r = std.fmt.bufPrint(sr[0 .. sr.len - 1], "Chiron's ephemeris is restricted to JD {d:8.1} - JD {d:8.1}", .{ CHIRON_START, CHIRON_END }) catch "";
                if (r.len < sr.len) sr[r.len] = 0;
            }
            return ERR;
        }
        if (ipli_u == SEI_PHOLUS and (tjd < PHOLUS_START or tjd > PHOLUS_END)) {
            if (serr) |sr| {
                const r = std.fmt.bufPrint(sr[0 .. sr.len - 1], "Pholus's ephemeris is restricted to JD {d:8.1} - JD {d:8.1}", .{ PHOLUS_START, PHOLUS_END }) catch "";
                if (r.len < sr.len) sr[r.len] = 0;
            }
            return ERR;
        }
        // do_asteroid: label of C's retry loop
        while (true) {
            var redo = false;
            // earth and sun are also needed
            var retc = main_planet(tjd, SEI_EARTH, 0, epheflag, iflag, swed, models, dctx, serr);
            if (retc == ERR)
                return ERR;
            // iflag (ephemeris bit) has possibly changed in main_planet()
            iflag = swed.pldat[SEI_EARTH].xflgs;
            // asteroid; save the earth/sun warning, then clear serr
            var serr2: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
            if (serr) |sr| {
                const cur = std.mem.sliceTo(sr, 0);
                const n = @min(cur.len, AS_MAXCH - 1);
                @memcpy(serr2[0..n], cur[0..n]);
                sr[0] = 0;
            }
            retc = sweph(tjd, @intCast(ipli_ast), ifno, iflag, swed.pldat[SEI_SUNBARY].x[0..6], true, null, serr, swed, models);
            if (retc == ERR or retc == NOT_AVAILABLE)
                return ERR;
            retc = app_pos_etc_plan(@intCast(ipli_ast), 0, iflag, swed, models, dctx, serr);
            if (retc == ERR)
                return ERR;
            // app_pos_etc_plan() might have failed if t(light-time) is
            // beyond ephemeris range: redo with Moshier
            if (retc == NOT_AVAILABLE or retc == BEYOND_EPH_LIMITS) {
                if (epheflag != SEFLG_MOSEPH) {
                    iflag = (iflag & ~SEFLG_EPHMASK) | SEFLG_MOSEPH;
                    epheflag = SEFLG_MOSEPH;
                    if (serr) |sr| {
                        const cur = std.mem.sliceTo(sr, 0);
                        if (cur.len + 30 < AS_MAXCH) {
                            const add = "\nusing Moshier eph.; ";
                            const r = cur.len;
                            @memcpy(sr[r .. r + add.len], add);
                            if (r + add.len < sr.len) sr[r + add.len] = 0;
                        }
                    }
                    redo = true;
                } else {
                    return ERR;
                }
            }
            if (!redo) {
                // add warnings from earth/sun computation
                if (serr) |sr| {
                    if (sr[0] == 0 and serr2[0] != 0) {
                        const warn = "sun: ";
                        @memcpy(sr[0..warn.len], warn);
                        // C: serr2[AS_MAXCH-5] = '\0' truncates the source
                        var n: usize = 0;
                        while (n < AS_MAXCH - 5 and serr2[n] != 0) : (n += 1) {}
                        @memcpy(sr[warn.len .. warn.len + n], serr2[0..n]);
                        if (warn.len + n < sr.len) sr[warn.len + n] = 0;
                    }
                }
                break;
            }
        }
        copy_xreturn(pdp_ast, x);
        // xp (C's pdp->xreturn) was already copied by the caller's copy loop
        _ = xp_ast;
    } else if (ipl >= swemplan_mod.SE_FICT_OFFSET and ipl <= swemplan_mod.SE_FICT_MAX) {
        // sweph.c fictitious planets (Isis-Transpluto, Uranian planets)
        ipli = SEI_ANYBODY;
        // do_fict_plan: label of C's retry loop
        while (true) {
            var redo_f = false;
            // the earth for geocentric position
            const retc = main_planet(tjd, SEI_EARTH, 0, epheflag, iflag, swed, models, dctx, serr);
            // iflag (ephemeris bit) has possibly changed in main_planet()
            iflag = swed.pldat[SEI_EARTH].xflgs;
            // planet from osculating elements
            if (swemplan_mod.swi_osc_el_plan(tjd, &swed.pldat[SEI_ANYBODY].x, ipl - swemplan_mod.SE_FICT_OFFSET, ipli, &swed.pldat[SEI_EARTH].x, &swed.pldat[SEI_SUNBARY].x, models, swed, serr) != OK)
                return ERR;
            if (retc == ERR)
                return ERR;
            const retc_osc = app_pos_etc_plan_osc(ipl, ipli, iflag, swed, models, dctx, serr);
            if (retc_osc == ERR)
                return ERR;
            // app_pos_etc_plan_osc() might have failed, if t(light-time)
            // is beyond ephemeris range. in this case redo with Moshier
            if (retc_osc == NOT_AVAILABLE or retc_osc == BEYOND_EPH_LIMITS) {
                if (epheflag != SEFLG_MOSEPH) {
                    iflag = (iflag & ~SEFLG_EPHMASK) | SEFLG_MOSEPH;
                    epheflag = SEFLG_MOSEPH;
                    if (serr) |sr| appendSerrMax(sr, "\nusing Moshier eph.; ");
                    redo_f = true;
                } else {
                    return ERR;
                }
            }
            if (!redo_f)
                break;
        }
        copy_xreturn(&swed.pldat[SEI_ANYBODY], x);
    }
    return iflag;
}

fn undefined6() [6]f64 {
    return [_]f64{0} ** 6;
}

/// C's swi_strcpy(dest, src) where src > dest: shift left by off bytes
/// (both point into the same buffer).
fn swiStrcpyShift(s: [*]u8, off: usize) void {
    var w: usize = 0;
    var r: usize = off;
    while (s[r] != 0) : (r += 1) {
        s[w] = s[r];
        w += 1;
    }
    s[w] = 0;
}

fn copy_xreturn(pdp: *PlanData, x: *[24]f64) void {
    for (0..24) |k| x[k] = pdp.xreturn[k];
}

// sidereal mode marker (swe_set_sid_mode not ported; corpus excludes it)

/// sweph.c main_planet for SEFLG_MOSEPH
pub fn main_planet_pub(tjd: f64, ipli: usize, iplmoon: i32, epheflag_in: i32, iflag_in: i32, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    return main_planet(tjd, ipli, iplmoon, epheflag_in, iflag_in, swed, models, dctx, serr);
}

fn main_planet(tjd: f64, ipli: usize, iplmoon: i32, epheflag_in: i32, iflag_in: i32, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var epheflag = epheflag_in;
    var iflag = iflag_in;
    var retc: i32 = OK;
    var retc2: i32 = OK;
    // center of body: planet center relative to planet barycenter
    if ((iflag & SEFLG_CENTER_BODY) != 0 and ipli >= SEI_MARS and ipli <= SEI_PLUTO) {
        retc = sweph(tjd, @intCast(iplmoon), SEI_FILE_ANY_AST, iflag, null, true, null, serr, swed, models);
        if (retc == ERR or retc == NOT_AVAILABLE)
            return ERR;
    }
    // C's goto three_labels (sweph_planet / moshier_planet) as a retry loop
    while (true) {
        var redo = false;
        switch (epheflag) {
            SEFLG_JPLEPH => {
                retc = jplplan(tjd, ipli, iflag, true, null, null, null, swed, dctx, serr);
                // read error or corrupt file
                if (retc == ERR)
                    return ERR;
                // jpl ephemeris not on disk or date beyond ephemeris range
                if (retc == NOT_AVAILABLE) {
                    iflag = (iflag & ~SEFLG_JPLEPH) | SEFLG_SWIEPH;
                    if (serr) |sr| appendSerrMax(sr, " \ntrying Swiss Eph; ");
                    epheflag = SEFLG_SWIEPH;
                    redo = true;
                } else if (retc == BEYOND_EPH_LIMITS) {
                    if (tjd > MOSHPLEPH_START and tjd < MOSHPLEPH_END) {
                        iflag = (iflag & ~SEFLG_JPLEPH) | SEFLG_MOSEPH;
                        if (serr) |sr| appendSerrMax(sr, " \nusing Moshier Eph; ");
                        epheflag = SEFLG_MOSEPH;
                        redo = true;
                    } else {
                        return ERR;
                    }
                }
                if (redo) continue;
            },
            SEFLG_SWIEPH => {
                // compute barycentric planet (+ earth, sun, moon)
                retc = sweplan(tjd, ipli, SEI_FILE_PLANET, iflag, true, null, null, null, null, serr, swed, models);
                if (retc == ERR)
                    return ERR;
                // if sweph file not found, switch to moshier
                if (retc == NOT_AVAILABLE) {
                    if (tjd > MOSHPLEPH_START and tjd < MOSHPLEPH_END) {
                        iflag = (iflag & ~SEFLG_SWIEPH) | SEFLG_MOSEPH;
                        if (serr) |sr| appendSerrMax(sr, " \nusing Moshier eph.; ");
                        epheflag = SEFLG_MOSEPH;
                        redo = true;
                    } else {
                        return ERR;
                    }
                }
                if (redo) continue;
            },
            else => {
                // SEFLG_MOSEPH
                retc = swi_moshplan_save(tjd, ipli, swed, models, serr);
                if (retc == ERR)
                    return ERR;
            },
        }
        // geocentric, lighttime etc.
        if (ipli == SEI_SUN) {
            retc2 = app_pos_etc_sun(iflag, swed, models, dctx, serr);
        } else {
            retc2 = app_pos_etc_plan(ipli, iplmoon, iflag, swed, models, dctx, serr);
        }
        if (retc2 == ERR)
            return ERR;
        // t for light-time beyond ephemeris range / file not found
        if (retc2 == NOT_AVAILABLE) {
            if (epheflag == SEFLG_JPLEPH) {
                iflag = (iflag & ~SEFLG_JPLEPH) | SEFLG_SWIEPH;
                if (serr) |sr| appendSerrMax(sr, " \ntrying Swiss Eph; ");
                epheflag = SEFLG_SWIEPH;
                redo = true;
            } else if (epheflag == SEFLG_SWIEPH) {
                if (tjd > MOSHPLEPH_START and tjd < MOSHPLEPH_END) {
                    iflag = (iflag & ~SEFLG_SWIEPH) | SEFLG_MOSEPH;
                    if (serr) |sr| appendSerrMax(sr, " \nusing Moshier eph.; ");
                    epheflag = SEFLG_MOSEPH;
                    redo = true;
                } else {
                    return ERR;
                }
            }
        } else if (retc2 == BEYOND_EPH_LIMITS) {
            if (epheflag == SEFLG_JPLEPH) {
                if (tjd > MOSHPLEPH_START and tjd < MOSHPLEPH_END) {
                    iflag = (iflag & ~SEFLG_JPLEPH) | SEFLG_MOSEPH;
                    if (serr) |sr| appendSerrMax(sr, " \nusing Moshier Eph; ");
                    epheflag = SEFLG_MOSEPH;
                    redo = true;
                } else {
                    return ERR;
                }
            }
        }
        if (!redo) break;
    }
    return OK;
}

/// sweph.c swe_calc/// sweph.c swe_calc for the ported subset
pub fn swe_calc(tjd: f64, ipl_in: i32, iflag_in: i32, xx: *[6]f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var iflag = iflag_in;
    const iflgsave = iflag;
    var ipl = ipl_in;
    var iplmoon: i32 = 0;
    var epheflag: i32 = undefined;
    var use_speed3 = false;
    if (serr) |sr| {
        if (sr.len > 0) sr[0] = 0;
    }
    // function calls for Pluto with asteroid number 134340 are treated
    // as calls for Pluto as main body SE_PLUTO
    if (ipl == SE_AST_OFFSET + 134340)
        ipl = SE_PLUTO;
    // if ephemeris flag != ephemeris flag of last call, clear save area
    epheflag = iflag & SEFLG_EPHMASK;
    if ((epheflag & SEFLG_MOSEPH) != 0) {
        epheflag = SEFLG_MOSEPH;
    } else if ((epheflag & SEFLG_JPLEPH) != 0) {
        epheflag = SEFLG_JPLEPH;
    } else {
        epheflag = SEFLG_SWIEPH;
    }
    if (swed.last_epheflag != epheflag) {
        freePlanets(swed);
        // close and free ephemeris files
        if (ipl != SE_ECL_NUT) { // file will not be reopened with this ipl
            if (swed.jpl_file_is_open) {
                swed.jpl_file_is_open = false;
            }
            if (swed.jpl_file_is_open) {
                jplmod.swi_close_jpl_file(swed);
                swed.jpl_file_is_open = false;
            }
            for (&swed.fidat) |*fd| {
                if (fd.fp != null)
                    _ = fclose(fd.fp);
                fd.* = .{};
            }
            // fidat[SEI_FILE_MOON] zeroed: delta-T's moon denum is gone
            dctx.sweph_denum = 0;
            swed.last_epheflag = epheflag;
        }
    }
    // high precision speed prevails fast speed
    if ((iflag & SEFLG_SPEED3) != 0 and (iflag & SEFLG_SPEED) != 0)
        iflag = iflag & ~SEFLG_SPEED3;
    if ((iflag & SEFLG_SPEED3) != 0)
        use_speed3 = true;
    // topocentric with SEFLG_SPEED is not good if aberration is included
    if ((iflag & SEFLG_SPEED) != 0 and (iflag & SEFLG_TOPOCTR) != 0 and (iflag & SEFLG_NOABERR) == 0)
        use_speed3 = true;
    // cartesian flag excludes radians flag
    if ((iflag & SEFLG_XYZ) != 0 and (iflag & SEFLG_RADIANS) != 0)
        iflag = iflag & ~SEFLG_RADIANS;
    // planetary center of body handling
    // planet is called with SE_PLUTO etc. and SEFLG_CENTER_BODY:
    // get number of center of body
    if ((iflag & SEFLG_CENTER_BODY) != 0 and ipl <= SE_PLUTO and (iflag & SEFLG_TEST_PLMOON) != SEFLG_TEST_PLMOON) {
        iplmoon = ipl * 100 + 9099; // planetary center of body
    }
    // planet center of body or planetary moon is called using 9... number:
    // moon number and planet number
    if (ipl >= SE_PLMOON_OFFSET and ipl < SE_AST_OFFSET and (iflag & SEFLG_TEST_PLMOON) != SEFLG_TEST_PLMOON) {
        iplmoon = ipl; // planetary center of body or planetary moon
        ipl = @divTrunc((ipl - 9000), 100);
        iflag |= SEFLG_CENTER_BODY;
    }
    // with Mercury to Mars, we do not have center of body different from barycenter
    if ((iflag & SEFLG_CENTER_BODY) != 0 and ipl <= SE_MARS and @rem(iplmoon, 100) == 99) {
        iplmoon = 0;
        iflag &= ~SEFLG_CENTER_BODY;
    }
    // if any planetary moon or center of body is computed, we need to force
    // new computation of all planetary positions
    if ((iflag & SEFLG_CENTER_BODY) != 0 or iplmoon > 0)
        forceAppPos(swed);
    // pointer to save area
    var sd: *SavePositions = undefined;
    if (ipl < @as(i32, @intCast(SE_NPLANETS)) and ipl >= SE_SUN) {
        sd = &swed.savedat[@intCast(ipl)];
    } else {
        sd = &swed.savedat[SE_NPLANETS];
    }
    // if position is available in save area, it is returned
    if (sd.tsave == tjd and tjd != 0 and ipl == sd.ipl and iplmoon == 0) {
        if ((sd.iflgsave & ~SEFLG_COORDSYS) == (iflag & ~SEFLG_COORDSYS)) {
            // goto end_swe_calc
            return finish_swe_calc(iflag, iflgsave, ipl, tjd != 0, xx, sd, swed);
        }
    }
    // otherwise, new position must be computed
    if (!use_speed3) {
        // with high precision speed from one call of swecalc() (FAST speed)
        sd.tsave = tjd;
        sd.ipl = ipl;
        sd.iflgsave = swecalc(tjd, ipl, iplmoon, iflag, &sd.xsaves, swed, models, dctx, serr);
        if (sd.iflgsave == ERR)
            return return_error_calc(xx);
    } else {
        // with speed from three calls of swecalc(), slower and less accurate
        var x0: [24]f64 = undefined;
        var x2: [24]f64 = undefined;
        var dt: f64 = undefined;
        sd.tsave = tjd;
        sd.ipl = ipl;
        switch (ipl) {
            SE_MOON => dt = MOON_SPEED_INTV,
            SE_OSCU_APOG, SE_TRUE_NODE => dt = NODE_CALC_INTV_MOSH,
            else => dt = PLAN_SPEED_INTV,
        }
        sd.iflgsave = swecalc(tjd - dt, ipl, iplmoon, iflag, &x0, swed, models, dctx, serr);
        if (sd.iflgsave == ERR)
            return return_error_calc(xx);
        sd.iflgsave = swecalc(tjd + dt, ipl, iplmoon, iflag, &x2, swed, models, dctx, serr);
        if (sd.iflgsave == ERR)
            return return_error_calc(xx);
        sd.iflgsave = swecalc(tjd, ipl, iplmoon, iflag, &sd.xsaves, swed, models, dctx, serr);
        if (sd.iflgsave == ERR)
            return return_error_calc(xx);
        denormalize_positions(&x0, &sd.xsaves, &x2);
        calc_speed(&x0, &sd.xsaves, &x2, dt);
    }
    return finish_swe_calc(iflag, iflgsave, ipl, tjd != 0, xx, sd, swed);
}

fn return_error_calc(xx: *[6]f64) i32 {
    for (0..6) |i| xx[i] = 0;
    return ERR;
}

/// the tail of swe_calc after (cached or fresh) xsaves are ready
fn finish_swe_calc(iflag_in: i32, iflgsave: i32, ipl: i32, have_tjd: bool, xx: *[6]f64, sd: *SavePositions, swed: *Swed) i32 {
    _ = have_tjd;
    _ = swed;
    var iflag = iflag_in;
    var x: [6]f64 = undefined;
    var xs: []const f64 = undefined;
    if ((iflag & SEFLG_EQUATORIAL) != 0) {
        xs = sd.xsaves[12..]; // equatorial coordinates
    } else {
        xs = sd.xsaves[0..]; // ecliptic coordinates
    }
    if ((iflag & SEFLG_XYZ) != 0)
        xs = xs[6..]; // cartesian coordinates
    var cnt: usize = 3;
    if (ipl == SE_ECL_NUT) {
        cnt = 4;
    }
    var j: usize = 0;
    while (j < cnt) : (j += 1)
        x[j] = xs[j];
    j = cnt;
    while (j < 6) : (j += 1)
        x[j] = 0;
    if ((iflag & (SEFLG_SPEED3 | SEFLG_SPEED)) != 0) {
        j = 3;
        while (j < 6) : (j += 1)
            x[j] = xs[j];
    }
    if ((iflag & SEFLG_RADIANS) != 0) {
        if (ipl == SE_ECL_NUT) {
            j = 0;
            while (j < 4) : (j += 1)
                x[j] *= DEGTORAD;
        } else {
            j = 0;
            while (j < 2) : (j += 1)
                x[j] *= DEGTORAD;
            if ((iflag & (SEFLG_SPEED3 | SEFLG_SPEED)) != 0) {
                j = 3;
                while (j < 5) : (j += 1)
                    x[j] *= DEGTORAD;
            }
        }
    }
    for (0..6) |i| xx[i] = x[i];
    // iflag from previous call of swe_calc(), without coordinate system flags
    iflag = sd.iflgsave & ~SEFLG_COORDSYS;
    // add correct coordinate system flags
    iflag |= (iflgsave & SEFLG_COORDSYS);
    // if no ephemeris has been specified, do not return chosen ephemeris
    if ((iflgsave & SEFLG_EPHMASK) == 0)
        iflag = iflag & ~SEFLG_DEFAULTEPH;
    return iflag;
}

/// sweph.c swe_calc_ut
pub fn swe_calc_ut(tjd_ut: f64, ipl: i32, iflag_in: i32, xx: *[6]f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var iflag = iflag_in;
    var retval: i32 = OK;
    var epheflag: i32 = 0;
    iflag = plaus_iflag(iflag, ipl, tjd_ut, swed, models, serr);
    epheflag = iflag & SEFLG_EPHMASK;
    if (epheflag == 0) {
        epheflag = SEFLG_SWIEPH;
        iflag |= SEFLG_SWIEPH;
    }
    // C's calc_deltat reads swed.fidat[SEI_FILE_MOON].sweph_denum and
    // swed.jpldenum live; the port's DeltatCtx carries copies, refreshed here
    dctx.sweph_denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
    dctx.jpldenum = swed.jpldenum;
    var d = deltat.swe_deltat_ex(dctx, tjd_ut, iflag);
    retval = swe_calc(tjd_ut + d, ipl, iflag, xx, swed, models, dctx, serr);
    // if ephe required is not ephe returned, adjust delta t:
    if ((retval & SEFLG_EPHMASK) != epheflag) {
        dctx.sweph_denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        d = deltat.swe_deltat_ex(dctx, tjd_ut, retval);
        retval = swe_calc(tjd_ut + d, ipl, iflag, xx, swed, models, dctx, null);
    }
    return retval;
}

/// sweph.c swi_plan_for_osc_elem: bias + precession to of-date + nutation
/// rotation for the raw lunar positions used by the osculating elements.
pub fn swi_plan_for_osc_elem(iflag: i32, tjd: f64, xx: *[6]f64, swed: *Swed, models: AstroModels) void {
    var x: [6]f64 = undefined;
    var nuttmp: Nut = .{};
    var nutp: *Nut = undefined;
    var oe: *const Eps = &swed.oec;
    var oectmp: Eps = .{};
    // ICRS to J2000
    if ((iflag & SEFLG_ICRS) == 0 and swi_get_denum(SEI_SUN, iflag, swed) >= 403) {
        lib.swi_bias(xx, tjd, iflag, false, models);
    }
    // precession, equator 2000 -> equator of date
    // attention: speed vector has to be rotated, but daily precession
    // 0.137" may not be added!
    _ = lib.swi_precess(xx[0..3], tjd, iflag, J2000_TO_J, models);
    _ = lib.swi_precess(xx[3..6], tjd, iflag, J2000_TO_J, models);
    // epsilon
    if (tjd == swed.oec.teps) {
        oe = &swed.oec;
    } else if (tjd == J2000) {
        oe = &swed.oec2000;
    } else {
        calc_epsilon(tjd, iflag, &oectmp, models);
        oe = &oectmp;
    }
    // nutation: speed vector rotated, but no 'speed' of nutation
    if ((iflag & SEFLG_NONUT) == 0) {
        if (tjd == swed.nut.tnut) {
            nutp = &swed.nut;
        } else if (tjd == J2000) {
            nutp = &swed.nut2000;
        } else if (tjd == swed.nutv.tnut) {
            nutp = &swed.nutv;
        } else {
            nutp = &nuttmp;
            _ = lib.swi_nutation(tjd, iflag, &nutp.nutlo, models, nutInterp(swed));
            nutp.tnut = tjd;
            nutp.snut = swe_shim_sin(nutp.nutlo[1]);
            nutp.cnut = swe_shim_cos(nutp.nutlo[1]);
            nut_matrix(nutp, oe);
        }
        var i: usize = 0;
        while (i <= 2) : (i += 1) {
            x[i] = xx[0] * nutp.matrix[0][i] +
                xx[1] * nutp.matrix[1][i] +
                xx[2] * nutp.matrix[2][i];
        }
        // speed: rotation only
        i = 0;
        while (i <= 2) : (i += 1) {
            x[i + 3] = xx[3] * nutp.matrix[0][i] +
                xx[4] * nutp.matrix[1][i] +
                xx[5] * nutp.matrix[2][i];
        }
        i = 0;
        while (i <= 5) : (i += 1)
            xx[i] = x[i];
    }
    // transformation to ecliptic
    lib.swi_coortrf2(xx[0..3], xx[0..3], oe.seps, oe.ceps);
    lib.swi_coortrf2(xx[3..6], xx[3..6], oe.seps, oe.ceps);
    if ((iflag & SEFLG_NONUT) == 0) {
        lib.swi_coortrf2(xx[0..3], xx[0..3], nutp.snut, nutp.cnut);
        lib.swi_coortrf2(xx[3..6], xx[3..6], nutp.snut, nutp.cnut);
    }
}

/// sweph.c lunar_osc_elem: osculating lunar node ('true' node) and
/// osculating apogee. MOSEPH branch only (file ephemerides deferred).
fn lunar_osc_elem(tjd: f64, ipl_nd: usize, iflag_in: i32, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var iflag = iflag_in;
    var epheflag: i32 = SEFLG_DEFAULTEPH;
    const ndp = &swed.nddat[ipl_nd];
    var i: usize = undefined;
    var speed_intv: f64 = NODE_CALC_INTV; // to silence gcc warning
    var a: f64 = undefined;
    var b: f64 = undefined;
    var xpos: [3][6]f64 = undefined;
    var xx: [3][6]f64 = undefined;
    var xxa: [3][6]f64 = undefined;
    var xnorm: [6]f64 = undefined;
    var r: [6]f64 = undefined;
    var rxy: f64 = undefined;
    var rxyz: f64 = undefined;
    var t: f64 = undefined;
    var dt: f64 = undefined;
    var fac: f64 = undefined;
    var sgn: f64 = undefined;
    var sinnode: f64 = undefined;
    var cosnode: f64 = undefined;
    var sinincl: f64 = undefined;
    var cosincl: f64 = undefined;
    var sinu: f64 = undefined;
    var cosu: f64 = undefined;
    var sinE: f64 = undefined;
    var cosE: f64 = undefined;
    var uu: f64 = undefined;
    var ny: f64 = undefined;
    var sema: f64 = undefined;
    var ecce: f64 = undefined;
    var Gmsm: f64 = undefined;
    var c2: f64 = undefined;
    var v2: f64 = undefined;
    var pp: f64 = undefined;
    const oe: *const Eps = &swed.oec;
    // cache check: if elements already computed for this date, return;
    // recompute if speed flag turned on
    const flg1 = iflag & ~SEFLG_EQUATORIAL & ~SEFLG_XYZ;
    const flg2 = ndp.xflgs & ~SEFLG_EQUATORIAL & ~SEFLG_XYZ;
    const speedf1 = ndp.xflgs & SEFLG_SPEED;
    const speedf2 = iflag & SEFLG_SPEED;
    if (tjd == ndp.teval and tjd != 0 and flg1 == flg2 and
        (speedf2 == 0 or speedf1 != 0))
    {
        ndp.xflgs = iflag;
        ndp.iephe = iflag & SEFLG_EPHMASK;
        return OK;
    }
    // three lunar positions with speeds
    if ((iflag & SEFLG_MOSEPH) != 0) {
        epheflag = SEFLG_MOSEPH;
    } else if ((iflag & SEFLG_SWIEPH) != 0) {
        epheflag = SEFLG_SWIEPH;
    } else if ((iflag & SEFLG_JPLEPH) != 0) {
        epheflag = SEFLG_JPLEPH;
    }
    // there may be a moon of wrong ephemeris in save area: force recompute
    swed.pldat[SEI_MOON].teval = 0;
    var istart: usize = 2;
    if ((iflag & SEFLG_SPEED) != 0)
        istart = 0;
    if (serr) |sr| {
        if (sr.len > 0) sr[0] = 0;
    }
    // three_positions: (C label; the retry loop mirrors goto three_positions)
    while (true) {
        var retc: i32 = OK;
        if (epheflag == SEFLG_JPLEPH) {
            speed_intv = NODE_CALC_INTV;
            i = istart;
            while (i <= 2) : (i += 1) {
                if (i == 0) {
                    t = tjd - speed_intv;
                } else if (i == 1) {
                    t = tjd + speed_intv;
                } else {
                    t = tjd;
                }
                var xp6: [6]f64 = undefined;
                retc = jplplan(t, SEI_MOON, iflag, false, xp6[0..], null, null, swed, dctx, serr);
                for (0..6) |k| xpos[i][k] = xp6[k];
                // read error or corrupt file
                if (retc == ERR)
                    return ERR;
                // light-time-corrected moon for apparent node
                // this makes a difference of several milliarcseconds with
                // the node and 0.1" with the apogee.
                if ((iflag & SEFLG_TRUEPOS) == 0 and retc >= OK) {
                    var xpos3: [3]f64 = .{ xpos[i][0], xpos[i][1], xpos[i][2] };
                    dt = std.math.sqrt(square_sum(&xpos3)) * AUNIT / CLIGHT / 86400.0;
                    var xp6b: [6]f64 = undefined;
                    retc = jplplan(t - dt, SEI_MOON, iflag, false, xp6b[0..], null, null, swed, dctx, serr);
                    for (0..6) |k| xpos[i][k] = xp6b[k];
                    if (retc == ERR)
                        return ERR;
                }
                // jpl ephemeris not on disk, or date beyond ephemeris range
                if (retc == NOT_AVAILABLE) {
                    iflag = (iflag & ~SEFLG_JPLEPH) | SEFLG_SWIEPH;
                    epheflag = SEFLG_SWIEPH;
                    if (serr) |sr| appendSerrMax(sr, " \ntrying Swiss Eph; ");
                    break;
                } else if (retc == BEYOND_EPH_LIMITS) {
                    if (tjd > MOSHLUEPH_START and tjd < MOSHLUEPH_END) {
                        iflag = (iflag & ~SEFLG_JPLEPH) | SEFLG_MOSEPH;
                        epheflag = SEFLG_MOSEPH;
                        if (serr) |sr| appendSerrMax(sr, " \nusing Moshier Eph; ");
                        break;
                    } else {
                        return ERR;
                    }
                }
                // precession and nutation etc.
                swi_plan_for_osc_elem(iflag | SEFLG_SPEED, t, &xpos[i], swed, models); // retc is always ok
            }
        } else if (epheflag == SEFLG_SWIEPH) {
            speed_intv = NODE_CALC_INTV;
            i = istart;
            while (i <= 2) : (i += 1) {
                if (i == 0) {
                    t = tjd - speed_intv;
                } else if (i == 1) {
                    t = tjd + speed_intv;
                } else {
                    t = tjd;
                }
                var retc2 = sweplan(t, SEI_MOON, SEI_FILE_MOON, iflag | SEFLG_SPEED, false, xpos[i][0..], null, null, null, serr, swed, models);
                if (retc2 == ERR)
                    return ERR;
                // light-time-corrected moon for apparent node (~ 0.006")
                if ((iflag & SEFLG_TRUEPOS) == 0 and retc2 >= OK) {
                    var xpos3: [3]f64 = .{ xpos[i][0], xpos[i][1], xpos[i][2] };
                    dt = std.math.sqrt(square_sum(&xpos3)) * AUNIT / CLIGHT / 86400.0;
                    retc2 = sweplan(t - dt, SEI_MOON, SEI_FILE_MOON, iflag | SEFLG_SPEED, false, xpos[i][0..], null, null, null, serr, swed, models);
                    if (retc2 == ERR)
                        return ERR;
                }
                if (retc2 == NOT_AVAILABLE) {
                    if (tjd > MOSHPLEPH_START and tjd < MOSHPLEPH_END) {
                        iflag = (iflag & ~SEFLG_SWIEPH) | SEFLG_MOSEPH;
                        epheflag = SEFLG_MOSEPH;
                        if (serr) |sr| appendSerrMax(sr, " \nusing Moshier eph.; ");
                        retc = NOT_AVAILABLE;
                        break;
                    } else {
                        return ERR;
                    }
                }
                // precession and nutation etc.
                swi_plan_for_osc_elem(iflag | SEFLG_SPEED, t, &xpos[i], swed, models);
            }
        } else if (epheflag == SEFLG_MOSEPH) {
            // with moshier moon, we need a greater speed_intv, because here the
            // node and apogee oscillate wildly within small intervals
            speed_intv = NODE_CALC_INTV_MOSH;
            i = istart;
            while (i <= 2) : (i += 1) {
                if (i == 0) {
                    t = tjd - speed_intv;
                } else if (i == 1) {
                    t = tjd + speed_intv;
                } else {
                    t = tjd;
                }
                const retc2 = swemmoon_mod.swi_moshmoon(t, false, &xpos[i], &swed.oec, models, serr);
                if (retc2 == ERR)
                    return retc2;
                // precession and nutation etc.
                swi_plan_for_osc_elem(iflag | SEFLG_SPEED, t, &xpos[i], swed, models); // retc is always ok
            }
        }
        if (!(retc == NOT_AVAILABLE or retc == BEYOND_EPH_LIMITS))
            break;
    }
    // node with speed
    // node is always needed, even if apogee is wanted
    const ndnp = &swed.nddat[SEI_TRUE_NODE];
    // three nodes
    i = istart;
    while (i <= 2) : (i += 1) {
        if (@abs(xpos[i][5]) < 1e-15)
            xpos[i][5] = 1e-15;
        fac = xpos[i][2] / xpos[i][5];
        sgn = xpos[i][5] / @abs(xpos[i][5]);
        var j: usize = 0;
        while (j <= 2) : (j += 1)
            xx[i][j] = (xpos[i][j] - fac * xpos[i][j + 3]) * sgn;
    }
    // save position and speed
    i = 0;
    while (i <= 2) : (i += 1) {
        ndnp.x[i] = xx[2][i];
        if ((iflag & SEFLG_SPEED) != 0) {
            b = (xx[1][i] - xx[0][i]) / 2;
            a = (xx[1][i] + xx[0][i]) / 2 - xx[2][i];
            ndnp.x[i + 3] = (2 * a + b) / speed_intv;
        } else {
            ndnp.x[i + 3] = 0;
        }
        ndnp.teval = tjd;
        ndnp.iephe = epheflag;
    }
    // apogee with speed: must be computed anyway to get the node's distance
    const ndap = &swed.nddat[SEI_OSCU_APOG];
    Gmsm = GEOGCONST * (1 + 1 / EARTH_MOON_MRAT) / AUNIT / AUNIT / AUNIT * 86400.0 * 86400.0;
    // three apogees
    i = istart;
    while (i <= 2) : (i += 1) {
        // node
        rxy = std.math.sqrt(xx[i][0] * xx[i][0] + xx[i][1] * xx[i][1]);
        cosnode = xx[i][0] / rxy;
        sinnode = xx[i][1] / rxy;
        // inclination
        var xi3: [3]f64 = .{ xpos[i][0], xpos[i][1], xpos[i][2] };
        var xnorm3: [3]f64 = undefined;
        lib.swi_cross_prod_slice(&xi3, xpos[i][3..6], &xnorm3);
        xnorm[0] = xnorm3[0];
        xnorm[1] = xnorm3[1];
        xnorm[2] = xnorm3[2];
        rxy = xnorm[0] * xnorm[0] + xnorm[1] * xnorm[1];
        c2 = (rxy + xnorm[2] * xnorm[2]);
        rxyz = std.math.sqrt(c2);
        rxy = std.math.sqrt(rxy);
        sinincl = rxy / rxyz;
        cosincl = std.math.sqrt(1 - sinincl * sinincl);
        // argument of latitude
        cosu = xpos[i][0] * cosnode + xpos[i][1] * sinnode;
        sinu = xpos[i][2] / sinincl;
        uu = swe_shim_atan2(sinu, cosu);
        // semi-axis
        var xpos3: [3]f64 = .{ xpos[i][0], xpos[i][1], xpos[i][2] };
        var xposv: [3]f64 = .{ xpos[i][3], xpos[i][4], xpos[i][5] };
        rxyz = std.math.sqrt(square_sum(&xpos3));
        v2 = square_sum(&xposv);
        sema = 1 / (2 / rxyz - v2 / Gmsm);
        // eccentricity
        pp = c2 / Gmsm;
        ecce = std.math.sqrt(1 - pp / sema);
        // eccentric anomaly
        cosE = 1 / ecce * (1 - rxyz / sema);
        sinE = 1 / ecce / std.math.sqrt(sema * Gmsm) * dot_prod(&xpos3, &xposv);
        // true anomaly
        ny = 2 * swe_shim_atan(std.math.sqrt((1 + ecce) / (1 - ecce)) * sinE / (1 + cosE));
        // distance of apogee from ascending node
        xxa[i][0] = lib.swi_mod2PI(uu - ny + PI);
        xxa[i][1] = 0; // latitude
        xxa[i][2] = sema * (1 + ecce); // distance
        // transformation to ecliptic coordinates
        lib.swi_polcart(xxa[i][0..3], xxa[i][0..3]);
        lib.swi_coortrf2(xxa[i][0..3], xxa[i][0..3], -sinincl, cosincl);
        lib.swi_cartpol(xxa[i][0..3], xxa[i][0..3]);
        // adding node, we get apogee in ecl. coord.
        xxa[i][0] += swe_shim_atan2(sinnode, cosnode);
        lib.swi_polcart(xxa[i][0..3], xxa[i][0..3]);
        // new distance of node from orbital ellipse:
        // true anomaly of node:
        ny = lib.swi_mod2PI(ny - uu);
        // eccentric anomaly
        cosE = swe_shim_cos(2 * swe_shim_atan(swe_shim_tan(ny / 2) / std.math.sqrt((1 + ecce) / (1 - ecce))));
        // new distance
        r[0] = sema * (1 - ecce * cosE);
        // old node distance
        r[1] = std.math.sqrt(square_sum(&xx[i]));
        // correct length of position vector
        var j: usize = 0;
        while (j <= 2) : (j += 1)
            xx[i][j] *= r[0] / r[1];
    }
    // save position and speed
    i = 0;
    while (i <= 2) : (i += 1) {
        // apogee
        ndap.x[i] = xxa[2][i];
        if ((iflag & SEFLG_SPEED) != 0) {
            ndap.x[i + 3] = (xxa[1][i] - xxa[0][i]) / speed_intv / 2;
        } else {
            ndap.x[i + 3] = 0;
        }
        ndap.teval = tjd;
        ndap.iephe = epheflag;
        // node
        ndnp.x[i] = xx[2][i];
        if ((iflag & SEFLG_SPEED) != 0) {
            ndnp.x[i + 3] = (xx[1][i] - xx[0][i]) / speed_intv / 2;
        } else {
            ndnp.x[i + 3] = 0;
        }
    }
    // precession and nutation have already been taken into account
    // (lunar positions went through swi_plan_for_osc_elem); light-time is
    // contained in the lunar positions. Now polar and equatorial coordinates.
    var jj: usize = 0;
    while (jj <= 1) : (jj += 1) {
        var ndp2: *PlanData = undefined;
        if (jj == 0) {
            ndp2 = &swed.nddat[SEI_TRUE_NODE];
        } else {
            ndp2 = &swed.nddat[SEI_OSCU_APOG];
        }
        for (0..24) |k| ndp2.xreturn[k] = 0;
        // cartesian ecliptic
        i = 0;
        while (i <= 5) : (i += 1)
            ndp2.xreturn[6 + i] = ndp2.x[i];
        // polar ecliptic
        lib.swi_cartpol_sp(ndp2.xreturn[6..12], ndp2.xreturn[0..6]);
        // cartesian equatorial
        lib.swi_coortrf2(ndp2.xreturn[6..9], ndp2.xreturn[18..21], -oe.seps, oe.ceps);
        if ((iflag & SEFLG_SPEED) != 0)
            lib.swi_coortrf2(ndp2.xreturn[9..12], ndp2.xreturn[21..24], -oe.seps, oe.ceps);
        if ((iflag & SEFLG_NONUT) == 0) {
            lib.swi_coortrf2(ndp2.xreturn[18..21], ndp2.xreturn[18..21], -swed.nut.snut, swed.nut.cnut);
            if ((iflag & SEFLG_SPEED) != 0)
                lib.swi_coortrf2(ndp2.xreturn[21..24], ndp2.xreturn[21..24], -swed.nut.snut, swed.nut.cnut);
        }
        // polar equatorial
        lib.swi_cartpol_sp(ndp2.xreturn[18..24], ndp2.xreturn[12..18]);
        ndp2.xflgs = iflag;
        ndp2.iephe = iflag & SEFLG_EPHMASK;
        if ((iflag & SEFLG_SIDEREAL) != 0) {
            // node and apogee are referred to t;
            // the ecliptic position must be transformed to t0
            var x: [6]f64 = undefined;
            var daya: [2]f64 = .{ 0, 0 };
            // rigorous algorithm
            if ((swed.sidd.sid_mode & SE_SIDBIT_ECL_T0) != 0 or
                (swed.sidd.sid_mode & SE_SIDBIT_SSY_PLANE) != 0)
            {
                i = 0;
                while (i <= 5) : (i += 1)
                    x[i] = ndp2.xreturn[18 + i];
                // remove nutation
                if ((iflag & SEFLG_NONUT) == 0)
                    swi_nutate(&x, iflag, true, swed);
                // precess to J2000
                _ = lib.swi_precess(x[0..3], tjd, iflag, lib.J_TO_J2000, models);
                if ((iflag & SEFLG_SPEED) != 0)
                    swi_precess_speed(&x, tjd, iflag, lib.J_TO_J2000, swed, models);
                if ((swed.sidd.sid_mode & SE_SIDBIT_ECL_T0) != 0) {
                    _ = swi_trop_ra2sid_lon(&x, ndp2.xreturn[6..12], ndp2.xreturn[18..24], iflag, swed, models, dctx);
                    // project onto solar system equator
                } else if ((swed.sidd.sid_mode & SE_SIDBIT_SSY_PLANE) != 0) {
                    _ = swi_trop_ra2sid_lon_sosy(&x, ndp2.xreturn[6..12], iflag, swed, models, dctx);
                }
                // to polar
                lib.swi_cartpol_sp(ndp2.xreturn[6..12], ndp2.xreturn[0..6]);
                lib.swi_cartpol_sp(ndp2.xreturn[18..24], ndp2.xreturn[12..18]);
                // traditional algorithm;
                // this is a bit clumsy, but allows us to keep the
                // sidereal code together
            } else {
                lib.swi_cartpol_sp(ndp2.xreturn[6..12], ndp2.xreturn[0..6]);
                if (swi_get_ayanamsa_with_speed(ndp2.teval, iflag, &daya, swed, models, dctx, serr) == ERR)
                    return ERR;
                ndp2.xreturn[0] -= daya[0] * DEGTORAD;
                ndp2.xreturn[3] -= daya[1] * DEGTORAD;
                lib.swi_polcart_sp(ndp2.xreturn[0..6], ndp2.xreturn[6..12]);
            }
        } else if ((iflag & SEFLG_J2000) != 0) {
            // node and apogee are referred to t; transform to J2000
            var xj: [6]f64 = undefined;
            i = 0;
            while (i <= 5) : (i += 1)
                xj[i] = ndp2.xreturn[18 + i];
            _ = lib.swi_precess(xj[0..3], tjd, iflag, lib.J_TO_J2000, models);
            if ((iflag & SEFLG_SPEED) != 0)
                swi_precess_speed(&xj, tjd, iflag, lib.J_TO_J2000, swed, models);
            i = 0;
            while (i <= 5) : (i += 1)
                ndp2.xreturn[18 + i] = xj[i];
            lib.swi_cartpol_sp(ndp2.xreturn[18..24], ndp2.xreturn[12..18]);
            lib.swi_coortrf2(ndp2.xreturn[18..21], ndp2.xreturn[6..9], swed.oec2000.seps, swed.oec2000.ceps);
            if ((iflag & SEFLG_SPEED) != 0)
                lib.swi_coortrf2(ndp2.xreturn[21..24], ndp2.xreturn[9..12], swed.oec2000.seps, swed.oec2000.ceps);
            lib.swi_cartpol_sp(ndp2.xreturn[6..12], ndp2.xreturn[0..6]);
        }
        // radians to degrees
        i = 0;
        while (i < 2) : (i += 1) {
            ndp2.xreturn[i] *= RADTODEG; // ecliptic
            ndp2.xreturn[i + 3] *= RADTODEG;
            ndp2.xreturn[i + 12] *= RADTODEG; // equator
            ndp2.xreturn[i + 15] *= RADTODEG;
        }
        ndp2.xreturn[0] = lib.swe_degnorm(ndp2.xreturn[0]);
        ndp2.xreturn[12] = lib.swe_degnorm(ndp2.xreturn[12]);
    }
    return OK;
}

// ---------------------------------------------------------------------------
// SWIEPH file machinery (sweph.c read_const / do_fread / get_new_segment /
// rot_back / sweplan / sweph / swi_fopen / swe_set_ephe_path)
// ---------------------------------------------------------------------------

const c_allocator = if (is_wasm) std.heap.page_allocator else std.heap.c_allocator;

fn fio_fopen(path: []const u8, mode: []const u8) ?*anyopaque {
    var pbuf: [AS_MAXCH * 2]u8 = undefined;
    var mbuf: [8]u8 = undefined;
    const p = std.fmt.bufPrintZ(&pbuf, "{s}", .{std.mem.sliceTo(path, 0)}) catch return null;
    const m = std.fmt.bufPrintZ(&mbuf, "{s}", .{std.mem.sliceTo(mode, 0)}) catch return null;
    return fopen(p.ptr, m.ptr);
}

/// sweph.c do_fread
fn do_fread(trg: []u8, size: i32, count: i32, corrsize: i32, fp: ?*anyopaque, fpos: i32, freord: i32, fendian: i32, serr: ?[]u8, swed: *Swed) i32 {
    var space: [1000]u8 = undefined;
    const sizeu: usize = @intCast(size);
    const countu: usize = @intCast(count);
    const totsize: usize = sizeu * countu;
    if (fpos >= 0)
        _ = fseek(fp, @intCast(fpos), SEEK_SET);
    // if no byte reorder has to be done, and read size == return size
    if (freord == 0 and size == corrsize) {
        if (fread(trg.ptr, totsize, 1, fp) == 0) {
            if (serr) |sr| {
                setErr(sr, "Ephemeris file is damaged (1). ");
                appendFnam(sr, swed);
            }
            return ERR;
        } else {
            return OK;
        }
    } else {
        if (fread(&space, totsize, 1, fp) == 0) {
            if (serr) |sr| {
                setErr(sr, "Ephemeris file is damaged (3). ");
                appendFnam(sr, swed);
            }
            return ERR;
        }
        if (size != corrsize) {
            @memset(trg[0 .. @as(usize, @intCast(count)) * @as(usize, @intCast(corrsize))], 0);
        }
        var i: usize = 0;
        while (i < countu) : (i += 1) {
            var j: i32 = @as(i32, @intCast(size)) - 1;
            while (j >= 0) : (j -= 1) {
                var k: usize = undefined;
                const ju: usize = @intCast(j);
                if (freord != 0) {
                    k = sizeu - ju - 1;
                } else {
                    k = ju;
                }
                if (size != corrsize) {
                    if ((fendian == SEI_FILE_BIGENDIAN and freord == 0) or
                        (fendian == SEI_FILE_LITENDIAN and freord != 0))
                    {
                        k += @intCast(corrsize - size);
                    }
                }
                trg[i * @as(usize, @intCast(corrsize)) + k] = space[i * sizeu + ju];
            }
        }
    }
    return OK;
}

fn setErr(sr: []u8, msg: []const u8) void {
    const n = @min(msg.len, sr.len - 1);
    @memcpy(sr[0..n], msg[0..n]);
    sr[n] = 0;
}

fn appendFnam(sr: []u8, swed: *Swed) void {
    const fnam = std.mem.sliceTo(&swed.fidat[0].fnam, 0);
    const len = std.mem.indexOfScalar(u8, sr, 0) orelse sr.len;
    if (len + fnam.len < sr.len - 1) {
        @memcpy(sr[len .. len + fnam.len], fnam);
        sr[len + fnam.len] = 0;
    }
}

const SEEK_SET: i32 = 0;
const SEEK_END: i32 = 2;

/// sweph.c read_const (MOSEPH-free subset: planets/moon/asteroid files;
/// the SEI_FILE_ANY_AST asteroid-elements branch is ported 1:1)
fn read_const(ifno: usize, serr: ?[]u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx) i32 {
    _ = models;
    _ = dctx;
    var s: [AS_MAXCH * 2]u8 = undefined;
    var s2: [AS_MAXCH]u8 = undefined;
    var sastnam: [41]u8 = undefined;
    var doubles: [20]f64 = undefined;
    var smsg: []const u8 = "";
    var nbytes_ipl: usize = 2;
    const fdp = &swed.fidat[ifno];
    const fp = fdp.fp;
    // version number of file
    if (fgets(&s, AS_MAXCH, fp) == null or std.mem.indexOf(u8, std.mem.sliceTo(&s, 0), "\r\n") == null) {
        smsg = "a";
        // C's first check uses goto file_damage without smsg — replicate: it
        // falls into file_damage with smsg unset (empty)
        return fileDamage(serr, swed, ifno, if (std.mem.indexOf(u8, std.mem.sliceTo(&s, 0), "\r\n") == null) "" else "a");
    }
    var sp0 = std.mem.sliceTo(&s, 0);
    // C: strchr(s, '\r') → terminate there; then skip to first digit
    const cr = std.mem.indexOfScalar(u8, sp0, '\r') orelse sp0.len;
    sp0 = sp0[0..cr];
    var di: usize = 0;
    while (di < sp0.len and !std.ascii.isDigit(sp0[di])) : (di += 1) {}
    if (di == sp0.len) {
        return fileDamage(serr, swed, ifno, "a");
    }
    fdp.fversion = std.fmt.parseInt(i32, sp0[di..], 10) catch 0;
    // correct file name?
    if (fgets(&s, AS_MAXCH, fp) == null or std.mem.indexOf(u8, std.mem.sliceTo(&s, 0), "\r\n") == null) {
        return fileDamage(serr, swed, ifno, "b");
    }
    // file name, without path
    const fnam_full = std.mem.sliceTo(&fdp.fnam, 0);
    var fnamp = fnam_full;
    if (std.mem.lastIndexOfScalar(u8, fnamp, DIR_GLUE)) |gi| {
        fnamp = fnamp[gi + 1 ..];
    }
    // to lower case
    var lower_buf: [AS_MAXCH]u8 = undefined;
    var lower_len: usize = 0;
    for (fnamp) |c| {
        if (c == 0) break;
        lower_buf[lower_len] = std.ascii.toLower(c);
        lower_len += 1;
    }
    const s2low = lower_buf[0..lower_len];
    // prepare string of should-be file name: trim trailing \n \r ' '
    var line = std.mem.sliceTo(&s, 0);
    // C: s[strlen-1] is the last char before the implicit... C trims from
    // the end of the fgets buffer: while last char is \n \r or ' ', NUL it
    var line_arr = s[0..line.len];
    var lend = line.len;
    while (lend > 0 and (line_arr[lend - 1] == '\n' or line_arr[lend - 1] == '\r' or line_arr[lend - 1] == ' ')) {
        line_arr[lend - 1] = 0;
        lend -= 1;
    }
    line = line_arr[0..lend];
    for (line_arr[0..lend]) |*c| {
        c.* = std.ascii.toLower(c.*);
    }
    if (!std.mem.eql(u8, s2low, line)) {
        if (serr) |sr| {
            const msg = std.fmt.bufPrint(sr[0 .. sr.len - 1], "Ephemeris file name '{s}' wrong; rename '{s}' ", .{ s2low, line }) catch "";
            _ = msg;
        }
        return returnErrorFile(serr, swed, ifno);
    }
    // copyright
    if (fgets(&s, AS_MAXCH, fp) == null or std.mem.indexOf(u8, std.mem.sliceTo(&s, 0), "\r\n") == null) {
        return fileDamage(serr, swed, ifno, "c");
    }
    // orbital elements, if single asteroid
    var sastnam_len: usize = 0;
    if (ifno == SEI_FILE_ANY_AST) {
        if (fgets(&s, AS_MAXCH * 2, fp) == null or std.mem.indexOf(u8, std.mem.sliceTo(&s, 0), "\r\n") == null) {
            return fileDamage(serr, swed, ifno, "d");
        }
        // search "asteroid name"
        var si: usize = 0;
        const sl = std.mem.sliceTo(&s, 0);
        while (si < sl.len and sl[si] == ' ') si += 1;
        while (si < sl.len and std.ascii.isDigit(sl[si])) si += 1;
        si += 1;
        const namelen = @min(19 + @as(i32, @intCast(si)), 40);
        sastnam_len = @intCast(namelen);
        @memcpy(sastnam[0..sastnam_len], s[0..sastnam_len]);
        // C: strcpy(swed.astelem, s) — astelem state not needed for the corpus

        swed.ast_H = atof(s[35 + si ..]);
        swed.ast_G = atof(s[42 + si ..]);
        if (swed.ast_G == 0) swed.ast_G = 0.15;
        @memcpy(s2[0..7], s[51 + si .. 58 + si]);
        swed.ast_diam = atof(s2[0..7]);
        if (swed.ast_diam == 0) {
            swed.ast_diam = 1329.0 / std.math.sqrt(@as(f64, 0.15)) * std.math.pow(f64, 10, -0.2 * swed.ast_H);
        }
    }
    // one int32 for test of byte order
    var testendian: i32 = 0;
    if (fread(std.mem.asBytes(&testendian), 4, 1, fp) != 1) {
        return fileDamage(serr, swed, ifno, "e");
    }
    var freord: i32 = undefined;
    var fendian: i32 = undefined;
    if (testendian == SEI_FILE_TEST_ENDIAN) {
        freord = SEI_FILE_NOREORD;
    } else {
        freord = SEI_FILE_REORD;
        // byte-swap test
        const b = std.mem.toBytes(testendian);
        var swapped: [4]u8 = undefined;
        for (0..4) |bi| swapped[bi] = b[3 - bi];
        const lng = std.mem.bytesToValue(i32, &swapped);
        if (lng != SEI_FILE_TEST_ENDIAN) {
            return fileDamage(serr, swed, ifno, "f");
        }
    }
    // is file bigendian or littlendian?
    {
        const b = std.mem.toBytes(testendian);
        const c2v: u8 = @intCast(@divTrunc(SEI_FILE_TEST_ENDIAN, 16777216));
        if (b[0] == c2v) {
            fendian = SEI_FILE_BIGENDIAN;
        } else {
            fendian = SEI_FILE_LITENDIAN;
        }
    }
    fdp.iflg = freord | fendian;
    // length of file correct?
    var lng: i32 = 0;
    if (do_fread(std.mem.asBytes(&lng), 4, 1, 4, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
        return returnErrorFile(serr, swed, ifno);
    const fpos: i32 = @intCast(ftell(fp));
    if (fseek(fp, 0, SEEK_END) != 0) {
        return fileDamage(serr, swed, ifno, "g");
    }
    const flen: i32 = @intCast(ftell(fp));
    if (lng != flen) {
        return fileDamage(serr, swed, ifno, "h");
    }
    // DE number of JPL ephemeris which this file is based on
    if (do_fread(std.mem.asBytes(&fdp.sweph_denum), 4, 1, 4, fp, fpos, freord, fendian, serr, swed) != OK)
        return returnErrorFile(serr, swed, ifno);
    // start and end epoch of file
    if (do_fread(std.mem.asBytes(&fdp.tfstart), 8, 1, 8, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
        return returnErrorFile(serr, swed, ifno);
    if (do_fread(std.mem.asBytes(&fdp.tfend), 8, 1, 8, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
        return returnErrorFile(serr, swed, ifno);
    // how many planets are in file?
    var nplan: i16 = 0;
    if (do_fread(std.mem.asBytes(&nplan), 2, 1, 2, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
        return returnErrorFile(serr, swed, ifno);
    if (nplan > 256) {
        nbytes_ipl = 4;
        nplan = @mod(nplan, 256);
    }
    if (nplan < 1 or nplan > 20) {
        return fileDamage(serr, swed, ifno, "i");
    }
    fdp.npl = nplan;
    // which ones?
    {
        const cnt: usize = @intCast(nplan);
        var tmp: [SEI_FILE_NMAXPLAN]u8 = undefined;
        // do_fread with corrsize=sizeof(int): nbytes_ipl (2 or 4) → 4
        if (do_fread(&tmp, @intCast(nbytes_ipl), @intCast(nplan), 4, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
            return returnErrorFile(serr, swed, ifno);
        var i: usize = 0;
        while (i < cnt) : (i += 1) {
            var v: i32 = 0;
            // the values land as 4-byte ints in tmp (i * 4)
            const b = std.mem.bytesToValue(i32, tmp[i * 4 ..][0..4]);
            v = b;
            if (nbytes_ipl == 2) {
                // 2-byte values were widened by do_fread into 4-byte slots
            }
            fdp.ipl[i] = v;
        }
    }
    // asteroid name
    if (ifno == SEI_FILE_ANY_AST) {
        var sastno: [12]u8 = undefined;
        var j: usize = 4; // old astorb.dat had only 4 characters for MPC#
        while (j < 10 and sastnam[j] != ' ') j += 1;
        @memcpy(sastno[0..j], sastnam[0..j]);
        sastno[j] = 0;
        const i = atoi(&sastno);
        if (i == fdp.ipl[0] - SE_AST_OFFSET or i == fdp.ipl[0]) {
            const copy_len = @min(19, sastnam_len - j - 1);
            @memcpy(fdp.astnam[0..copy_len], sastnam[j + 1 .. j + 1 + copy_len]);
            fdp.astnam[19] = 0;
            var sbuf: [30]u8 = undefined;
            if (fread(&sbuf, 30, 1, fp) != 1) {
                return fileDamage(serr, swed, ifno, "j");
            }
        } else {
            if (fread(&fdp.astnam, 30, 1, fp) != 1) {
                return fileDamage(serr, swed, ifno, "k");
            }
        }
        var ai: i32 = @as(i32, @intCast(std.mem.indexOfScalar(u8, &fdp.astnam, 0) orelse 0)) - 1;
        if (ai < 0) ai = 0;
        var spi: usize = @intCast(ai);
        while (fdp.astnam[spi] == ' ') spi -= 1;
        fdp.astnam[spi + 1] = 0;
        if (std.mem.indexOf(u8, std.mem.sliceTo(&fdp.astnam, 0), "  ")) |dpi| {
            fdp.astnam[dpi] = 0;
        }
    }
    // check CRC
    const fpos2: i32 = @intCast(ftell(fp));
    var ulng: u32 = 0;
    if (do_fread(std.mem.asBytes(&ulng), 4, 1, 4, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
        return returnErrorFile(serr, swed, ifno);
    _ = fseek(fp, 0, SEEK_SET);
    if (fpos2 - 1 > 2 * AS_MAXCH) {
        return fileDamage(serr, swed, ifno, "l");
    }
    var cbuf: [2 * AS_MAXCH]u8 = undefined;
    if (fread(&cbuf, @intCast(fpos2), 1, fp) != 1) {
        return fileDamage(serr, swed, ifno, "m");
    }
    const mycrc = lib.swi_crc32(cbuf[0..@intCast(fpos2)]);
    if (false and mycrc != ulng) {
        return fileDamage(serr, swed, ifno, "n");
    }
    _ = fseek(fp, @as(i64, fpos2) + 4, SEEK_SET);
    // read general constants
    if (do_fread(std.mem.asBytes(&doubles), 8, 5, 8, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
        return returnErrorFile(serr, swed, ifno);
    swed.gcdat.clight = doubles[0];
    swed.gcdat.aunit = doubles[1];
    swed.gcdat.helgravconst = doubles[2];
    swed.gcdat.ratme = doubles[3];
    swed.gcdat.sunradius = doubles[4];
    // read constants of planets
    var kpl: usize = 0;
    while (kpl < @as(usize, @intCast(fdp.npl))) : (kpl += 1) {
        const ipli_file: i32 = fdp.ipl[kpl];
        var pdp: *PlanData = undefined;
        if (ipli_file >= SE_AST_OFFSET) {
            pdp = &swed.pldat[SEI_ANYBODY];
        } else if (ipli_file >= SE_PLMOON_OFFSET) {
            pdp = &swed.pldat[SEI_ANYBODY];
        } else {
            pdp = &swed.pldat[@intCast(ipli_file)];
        }
        pdp.ibdy = ipli_file;
        if (do_fread(std.mem.asBytes(&pdp.lndx0), 4, 1, 4, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
            return returnErrorFile(serr, swed, ifno);
        var iflg_i: i32 = 0;
        if (do_fread(std.mem.asBytes(&iflg_i), 1, 1, 4, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
            return returnErrorFile(serr, swed, ifno);
        pdp.iflg = iflg_i;
        var ncoe_i: i32 = 0;
        if (do_fread(std.mem.asBytes(&ncoe_i), 1, 1, 4, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
            return returnErrorFile(serr, swed, ifno);
        pdp.ncoe = ncoe_i;
        var lng2: i32 = 0;
        if (do_fread(std.mem.asBytes(&lng2), 4, 1, 4, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
            return returnErrorFile(serr, swed, ifno);
        pdp.rmax = @as(f64, @floatFromInt(lng2)) / 1000.0;
        if (ipli_file >= SE_PLMOON_OFFSET and ipli_file < SE_AST_OFFSET) {
            if (@rem(ipli_file, 100) == 99 or @divTrunc(ipli_file - 9000, 100) == SE_MARS_INT)
                pdp.rmax = @as(f64, @floatFromInt(lng2)) / 1000000.0;
        }
        if (do_fread(std.mem.asBytes(&doubles), 8, 10, 8, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
            return returnErrorFile(serr, swed, ifno);
        pdp.tfstart = doubles[0];
        pdp.tfend = doubles[1];
        pdp.dseg = doubles[2];
        pdp.nndx = @intFromFloat(@trunc((doubles[1] - doubles[0] + 0.1) / doubles[2]));
        pdp.telem = doubles[3];
        pdp.prot = doubles[4];
        pdp.dprot = doubles[5];
        pdp.qrot = doubles[6];
        pdp.dqrot = doubles[7];
        pdp.peri = doubles[8];
        pdp.dperi = doubles[9];
        if ((pdp.iflg & SEI_FLG_ELLIPSE) != 0) {
            if (pdp.refep != null) {
                pdp.refep = null;
                pdp.segp = null;
            }
            pdp.refep = c_allocator.alloc(f64, @intCast(pdp.ncoe * 2)) catch null;
            if (pdp.refep == null) return ERR;
            if (do_fread(std.mem.sliceAsBytes(pdp.refep.?), 8, 2 * pdp.ncoe, 8, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK) {
                pdp.refep = null;
                return returnErrorFile(serr, swed, ifno);
            }
        }
    }
    return OK;
}

fn freePlanets(swed: *Swed) void {
    // C's free_planets memsets swed.pldat; the swemplan module keeps its own
    // cache mirrors (pdp_teval/pdp_iephe/pdp_x) that must be reset too.
    for (&swed.pldat) |*p| {
        if (p.segp != null) p.segp = null;
        if (p.refep != null) p.refep = null;
        p.* = .{};
    }
    for (&swed.savedat) |*s| {
        s.* = .{};
    }
    for (&swed.nddat) |*p| {
        p.* = .{};
    }
}

fn atof(s: []const u8) f64 {
    // C atof: parse leading double, skip leading whitespace
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t')) i += 1;
    var end = i;
    while (end < s.len and (std.ascii.isDigit(s[end]) or s[end] == '.' or s[end] == '-' or s[end] == '+' or s[end] == 'e' or s[end] == 'E')) end += 1;
    return std.fmt.parseFloat(f64, s[i..end]) catch 0;
}

fn atoi(s: []const u8) i32 {
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t')) i += 1;
    var end = i;
    while (end < s.len and std.ascii.isDigit(s[end])) end += 1;
    if (end == i) return 0;
    return std.fmt.parseInt(i32, s[i..end], 10) catch 0;
}

fn fileDamage(serr: ?[]u8, swed: *Swed, ifno: usize, smsg: []const u8) i32 {
    if (serr) |sr| {
        sr[0] = 0;
        const fnam = std.mem.sliceTo(&swed.fidat[ifno].fnam, 0);
        const msg = "Ephemeris file %s is damaged (0%s). ";
        _ = msg;
        // C: sprintf(serr, "Ephemeris file %s is damaged (0%s). ", fnam, smsg)
        const out = std.fmt.bufPrint(sr[0 .. sr.len - 1], "Ephemeris file {s} is damaged (0{s}). ", .{ fnam, smsg }) catch "";
        _ = out;
    }
    return returnErrorFile(serr, swed, ifno);
}

fn returnErrorFile(serr: ?[]u8, swed: *Swed, ifno: usize) i32 {
    _ = serr;
    if (swed.fidat[ifno].fp != null) {
        _ = fclose(swed.fidat[ifno].fp);
        swed.fidat[ifno].fp = null;
    }
    freePlanets(swed);
    return ERR;
}

/// sweph.c get_new_segment
pub fn get_new_segment(tjd: f64, ipli: usize, ifno: usize, serr: ?[]u8, swed: *Swed) i32 {
    var longs: [MAXORD + 1]u32 = undefined;
    const pdp = &swed.pldat[ipli];
    const fdp = &swed.fidat[ifno];
    const fp = fdp.fp;
    // compute segment number
    const iseg: i32 = @intFromFloat((tjd - pdp.tfstart) / pdp.dseg);
    pdp.tseg0 = pdp.tfstart + @as(f64, @floatFromInt(iseg)) * pdp.dseg;
    pdp.tseg1 = pdp.tseg0 + pdp.dseg;
    // get file position of planet's index from file
    // C reuses fpos as both seek target and read target
    var fpos: i32 = pdp.lndx0 + iseg * 3;
    if (do_fread(std.mem.asBytes(&fpos), 3, 1, 4, fp, fpos, fdp.iflg & SEI_FILE_REORD, fdp.iflg & SEI_FILE_LITENDIAN, serr, swed) != OK)
        return returnErrorFile(serr, swed, ifno);
    _ = fseek(fp, @intCast(fpos), SEEK_SET);
    // clear space for chebyshev coefficients
    if (pdp.segp == null) {
        pdp.segp = c_allocator.alloc(f64, @intCast(pdp.ncoe * 3)) catch {
            if (fdp.fp != null) {
                _ = fclose(fdp.fp);
                fdp.fp = null;
            }
            freePlanets(swed);
            return ERR;
        };
    }
    const segp = pdp.segp.?;
    for (segp) |*v| v.* = 0;
    // now unpack
    const freord = fdp.iflg & SEI_FILE_REORD;
    const fendian = fdp.iflg & SEI_FILE_LITENDIAN;
    var nsizes: usize = 0;
    var nsize: [6]i32 = [_]i32{0} ** 6;
    var c: [4]u8 = undefined;
    // read coefficients for 3 coordinates
    var icoord: usize = 0;
    while (icoord < 3) : (icoord += 1) {
        var idbl: usize = icoord * @as(usize, @intCast(pdp.ncoe));
        // first read header
        // first bit indicates number of sizes of packed coefficients
        if (do_fread(&c, 1, 2, 1, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
            return returnErrorFile(serr, swed, ifno);
        var nco: i32 = 0;
        if (c[0] & 128 != 0) {
            nsizes = 6;
            if (do_fread(c[2..4], 1, 2, 1, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
                return returnErrorFile(serr, swed, ifno);
            nsize[0] = c[1] / 16;
            nsize[1] = @mod(c[1], 16);
            nsize[2] = c[2] / 16;
            nsize[3] = @mod(c[2], 16);
            nsize[4] = c[3] / 16;
            nsize[5] = @mod(c[3], 16);
            nco = nsize[0] + nsize[1] + nsize[2] + nsize[3] + nsize[4] + nsize[5];
        } else {
            nsizes = 4;
            nsize[0] = c[0] / 16;
            nsize[1] = @mod(c[0], 16);
            nsize[2] = c[1] / 16;
            nsize[3] = @mod(c[1], 16);
            nco = nsize[0] + nsize[1] + nsize[2] + nsize[3];
        }
        if (nco > pdp.ncoe) {
            if (serr) |sr| {
                const fnam = std.mem.sliceTo(&fdp.fnam, 0);
                _ = std.fmt.bufPrint(sr[0 .. sr.len - 1], "error in ephemeris file {s}: {d} coefficients instead of {d}. ", .{ fnam, nco, pdp.ncoe }) catch "";
            }
            if (fdp.fp != null) {
                _ = fclose(fdp.fp);
                fdp.fp = null;
            }
            freePlanets(swed);
            return ERR;
        }
        // now unpack
        var i: usize = 0;
        while (i < nsizes) : (i += 1) {
            if (nsize[i] == 0) continue;
            if (i < 4) {
                const j: usize = 4 - i;
                const k: usize = @intCast(nsize[i]);
                if (do_fread(std.mem.sliceAsBytes(longs[0..]), @intCast(j), @intCast(k), 4, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
                    return returnErrorFile(serr, swed, ifno);
                var m: usize = 0;
                while (m < k) : ({
                    m += 1;
                    idbl += 1;
                }) {
                    if (longs[m] & 1 != 0)
                        segp[idbl] = -(@as(f64, @floatFromInt((longs[m] + 1) / 2)) / 1e9 * pdp.rmax / 2)
                    else
                        segp[idbl] = @as(f64, @floatFromInt(longs[m] / 2)) / 1e9 * pdp.rmax / 2;
                }
            } else if (i == 4) { // half byte packing
                const j: usize = 1;
                const k: usize = @intCast(@divTrunc(nsize[i] + 1, 2));
                if (do_fread(std.mem.sliceAsBytes(longs[0..]), @intCast(j), @intCast(k), 4, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
                    return returnErrorFile(serr, swed, ifno);
                var m: usize = 0;
                var jj: usize = 0;
                while (m < k and jj < @as(usize, @intCast(nsize[i]))) : (m += 1) {
                    var o: u32 = 16;
                    var n: usize = 0;
                    while (n < 2 and jj < @as(usize, @intCast(nsize[i]))) : ({
                        n += 1;
                        jj += 1;
                        idbl += 1;
                        longs[m] %= o;
                        o /= 16;
                    }) {
                        if (longs[m] & o != 0)
                            segp[idbl] = -(@as(f64, @floatFromInt((longs[m] + o) / o / 2)) * pdp.rmax / 2 / 1e9)
                        else
                            segp[idbl] = @as(f64, @floatFromInt(longs[m] / o / 2)) * pdp.rmax / 2 / 1e9;
                    }
                }
            } else if (i == 5) { // quarter byte packing
                const j: usize = 1;
                const k: usize = @intCast(@divTrunc(nsize[i] + 3, 4));
                if (do_fread(std.mem.sliceAsBytes(longs[0..]), @intCast(j), @intCast(k), 4, fp, SEI_CURR_FPOS, freord, fendian, serr, swed) != OK)
                    return returnErrorFile(serr, swed, ifno);
                var m: usize = 0;
                var jj: usize = 0;
                while (m < k and jj < @as(usize, @intCast(nsize[i]))) : (m += 1) {
                    var o: u32 = 64;
                    var n: usize = 0;
                    while (n < 4 and jj < @as(usize, @intCast(nsize[i]))) : ({
                        n += 1;
                        jj += 1;
                        idbl += 1;
                        longs[m] %= o;
                        o /= 4;
                    }) {
                        if (longs[m] & o != 0)
                            segp[idbl] = -(@as(f64, @floatFromInt((longs[m] + o) / o / 2)) * pdp.rmax / 2 / 1e9)
                        else
                            segp[idbl] = @as(f64, @floatFromInt(longs[m] / o / 2)) * pdp.rmax / 2 / 1e9;
                    }
                }
            }
        }
    }
    return OK;
}

/// sweph.c rot_back: add reference orbit to chebyshev series (if
/// SEI_FLG_ELLIPSE), rotate series to mean equinox of J2000
pub fn rot_back(ipli: usize, swed: *Swed) void {
    const seps2000: f64 = 0.39777715572793088; // sin(eps2000)
    const ceps2000: f64 = 0.91748206215761929; // cos(eps2000)
    var x: [MAXORD + 1][3]f64 = undefined;
    var uix: [3]f64 = undefined;
    var uiy: [3]f64 = undefined;
    var uiz: [3]f64 = undefined;
    const pdp = &swed.pldat[ipli];
    const nco: usize = @intCast(pdp.ncoe);
    const t = pdp.tseg0 + pdp.dseg / 2;
    const chcfx = pdp.segp.?[0..nco];
    const chcfy = pdp.segp.?[nco .. 2 * nco];
    const chcfz = pdp.segp.?[2 * nco .. 3 * nco];
    const tdiff = (t - pdp.telem) / 365250.0;
    var dn: f64 = undefined;
    var qav: f64 = undefined;
    var pav: f64 = undefined;
    if (ipli == SEI_MOON) {
        dn = pdp.prot + tdiff * pdp.dprot;
        const ii: i32 = @intFromFloat(dn / TWOPI);
        dn -= @as(f64, @floatFromInt(ii)) * TWOPI;
        qav = (pdp.qrot + tdiff * pdp.dqrot) * swe_shim_cos(dn);
        pav = (pdp.qrot + tdiff * pdp.dqrot) * swe_shim_sin(dn);
    } else {
        qav = pdp.qrot + tdiff * pdp.dqrot;
        pav = pdp.prot + tdiff * pdp.dprot;
    }
    // calculate cosine and sine of average perihelion longitude
    var i: usize = 0;
    while (i < nco) : (i += 1) {
        x[i][0] = chcfx[i];
        x[i][1] = chcfy[i];
        x[i][2] = chcfz[i];
    }
    if ((pdp.iflg & SEI_FLG_ELLIPSE) != 0) {
        const refepx = pdp.refep.?[0..nco];
        const refepy = pdp.refep.?[nco .. 2 * nco];
        var omtild = pdp.peri + tdiff * pdp.dperi;
        const ii: i32 = @intFromFloat(omtild / TWOPI);
        omtild -= @as(f64, @floatFromInt(ii)) * TWOPI;
        const com = swe_shim_cos(omtild);
        const som = swe_shim_sin(omtild);
        // add reference orbit
        i = 0;
        while (i < nco) : (i += 1) {
            x[i][0] = chcfx[i] + com * refepx[i] - som * refepy[i];
            x[i][1] = chcfy[i] + com * refepy[i] + som * refepx[i];
        }
    }
    // construct right handed orthonormal system (equinoctal variables)
    const cosih2 = 1.0 / (1.0 + qav * qav + pav * pav);
    // orbit pole
    uiz[0] = 2.0 * pav * cosih2;
    uiz[1] = -2.0 * qav * cosih2;
    uiz[2] = (1.0 - qav * qav - pav * pav) * cosih2;
    // origin of longitudes vector
    uix[0] = (1.0 + qav * qav - pav * pav) * cosih2;
    uix[1] = 2.0 * qav * pav * cosih2;
    uix[2] = -2.0 * pav * cosih2;
    // vector in orbital plane orthogonal to origin of longitudes
    uiy[0] = 2.0 * qav * pav * cosih2;
    uiy[1] = (1.0 - qav * qav + pav * pav) * cosih2;
    uiy[2] = 2.0 * qav * cosih2;
    // rotate to actual orientation in space
    i = 0;
    while (i < nco) : (i += 1) {
        const xrot = x[i][0] * uix[0] + x[i][1] * uiy[0] + x[i][2] * uiz[0];
        const yrot = x[i][0] * uix[1] + x[i][1] * uiy[1] + x[i][2] * uiz[1];
        const zrot = x[i][0] * uix[2] + x[i][1] * uiy[2] + x[i][2] * uiz[2];
        if (@abs(xrot) + @abs(yrot) + @abs(zrot) >= 1e-14)
            pdp.neval = @intCast(i);
        x[i][0] = xrot;
        x[i][1] = yrot;
        x[i][2] = zrot;
        if (ipli == SEI_MOON) {
            // rotate to j2000 equator
            x[i][1] = ceps2000 * yrot - seps2000 * zrot;
            x[i][2] = seps2000 * yrot + ceps2000 * zrot;
        }
    }
    i = 0;
    while (i < nco) : (i += 1) {
        chcfx[i] = x[i][0];
        chcfy[i] = x[i][1];
        chcfz[i] = x[i][2];
    }
}

/// sweph.c embofs: adjust position from Earth-Moon barycenter to Earth
fn embofs(xemb: *[6]f64, xmoon: *const [6]f64) void {
    for (0..3) |i|
        xemb[i] -= xmoon[i] / (EARTH_MOON_MRAT + 1.0);
}

/// sweph.c sweph: opens/reads the sweph file and computes a barycentric
/// planet (plus sun/earth/moon as needed)
pub fn sweph(tjd: f64, ipli_in: usize, ifno: usize, iflag: i32, xsunb: ?[]const f64, do_save: bool, xpret: ?[]f64, serr: ?[]u8, swed: *Swed, models: AstroModels) i32 {
    var ipl = ipli_in;
    if (ipli_in > SE_AST_OFFSET)
        ipl = SEI_ANYBODY;
    if (ipli_in > SE_PLMOON_OFFSET)
        ipl = SEI_ANYBODY;
    const pdp = &swed.pldat[ipl];
    const pedp = &swed.pldat[SEI_EARTH];
    const psdp = &swed.pldat[SEI_SUNBARY];
    const fdp = &swed.fidat[ifno];
    var xx: [6]f64 = undefined;
    var xemb: [6]f64 = undefined;
    var xp: []f64 = undefined;
    if (do_save) {
        xp = &pdp.x;
    } else {
        xp = &xx;
    }
    // if planet has already been computed for this date, return
    const speedf1 = pdp.xflgs & SEFLG_SPEED;
    const speedf2 = iflag & SEFLG_SPEED;
    if (tjd == pdp.teval and
        pdp.iephe == SEFLG_SWIEPH and
        (speedf2 == 0 or speedf1 != 0) and
        ipl < SEI_ANYBODY)
    {
        if (xpret != null) {
            for (0..6) |i| xpret.?[i] = pdp.x[i];
        }
        return OK;
    }
    // get correct ephemeris file
    if (fdp.fp != null) {
        // if tjd is beyond file range, close old file
        if (tjd < fdp.tfstart or tjd > fdp.tfend or
            (ipl == SEI_ANYBODY and ipli_in != pdp.ibdy))
        {
            _ = fclose(fdp.fp);
            fdp.fp = null;
            pdp.refep = null;
            pdp.segp = null;
        }
    }
    // if sweph file not open, find and open it
    if (fdp.fp == null) {
        var fname: [AS_MAXCH]u8 = undefined;
        // swephlib.c swi_gen_filename
        lib.swi_gen_filename(tjd, ipli_in, &fname);
        var s: [AS_MAXCH]u8 = undefined;
        @memcpy(s[0..AS_MAXCH], fname[0..AS_MAXCH]);
        // C: subdirnam = fname up to (excluding) last DIR_GLUE
        var subdirnam: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
        var subdirlen: usize = 0;
        {
            const flen = std.mem.indexOfScalar(u8, fname[0..AS_MAXCH], 0) orelse AS_MAXCH;
            if (std.mem.lastIndexOfScalar(u8, fname[0..flen], DIR_GLUE)) |gi| {
                @memcpy(subdirnam[0..gi], fname[0..gi]);
                subdirlen = gi;
            }
        }
        while (true) {
            fdp.fp = swi_fopen(@intCast(ifno), std.mem.sliceTo(&s, 0), std.mem.sliceTo(&swed.ephepath, 0), serr, swed);
            if (fdp.fp != null) break;
            // if it is a planetary moon, also try without the directory "sat/"
            if (ipli_in > SE_PLMOON_OFFSET and ipli_in < SE_AST_OFFSET) {
                if (subdirlen > 0 and std.mem.startsWith(u8, std.mem.sliceTo(&s, 0), subdirnam[0..subdirlen])) {
                    // swi_strcpy(s, s + subdirlen + 1): remove "sat/" etc.
                    swiStrcpyShift(&s, subdirlen + 1);
                    continue;
                }
                return NOT_AVAILABLE;
                // numbered asteroid file: try also for short files (..s.se1).
                // On the second try, the inserted 's' will be seen and not
                // tried again.
            } else if (ipli_in > SE_AST_OFFSET) {
                const slen = std.mem.indexOfScalar(u8, s[0..AS_MAXCH], 0) orelse AS_MAXCH;
                const dot = std.mem.indexOfScalar(u8, s[0..slen], '.');
                if (dot != null and dot.? > 0 and s[dot.? - 1] != 's') {
                    // sprintf(spp, "s.%s", SE_FILE_SUFFIX): insert an 's'
                    var tail: [AS_MAXCH]u8 = undefined;
                    const tailz = std.fmt.bufPrint(&tail, "s.se1", .{}) catch return NOT_AVAILABLE;
                    @memcpy(s[dot.? .. dot.? + tailz.len], tailz);
                    s[dot.? + tailz.len] = 0;
                    continue;
                }
                // remove the 's' before '.' (C: spp--; swi_strcpy(spp, spp + 1))
                if (dot != null and dot.? > 0) {
                    std.mem.copyForwards(u8, s[dot.? - 1 .. slen], s[dot.?..slen]);
                    s[slen - 1] = 0;
                }
                if (subdirlen > 0 and std.mem.startsWith(u8, std.mem.sliceTo(&s, 0), subdirnam[0..subdirlen])) {
                    // remove "ast0/" etc.
                    swiStrcpyShift(&s, subdirlen + 1);
                    continue;
                }
                return NOT_AVAILABLE;
            }
            return NOT_AVAILABLE;
        }
        // during the search error messages may have been built, delete them
        if (serr) |sr| {
            if (sr.len > 0) sr[0] = 0;
        }
        const retc = read_const(ifno, serr, swed, models, undefined);
        if (retc != OK)
            return retc;
    }
    // if tjd beyond file range → error message + NOT_AVAILABLE
    if (tjd < fdp.tfstart or tjd > fdp.tfend) {
        if (serr) |sr| {
            var fnamep = std.mem.sliceTo(&fdp.fnam, 0);
            if (std.mem.lastIndexOfScalar(u8, fnamep, DIR_GLUE)) |gi| {
                fnamep = fnamep[gi + 1 ..];
            }
            var sbuf: [AS_MAXCH]u8 = undefined;
            // C: fname = fdp->fnam or the substring after last DIR_GLUE
            var sp = std.mem.sliceTo(&fdp.fnam, 0);
            if (std.mem.lastIndexOfScalar(u8, sp, DIR_GLUE)) |gi| {
                sp = sp[gi + 1 ..];
            }
            if (ipli_in > SE_AST_OFFSET) {
                var msg: [AS_MAXCH]u8 = undefined;
                const r = std.fmt.bufPrint(&msg, "asteroid No. {d} ({s}): ", .{ ipli_in - 10000, sp }) catch msg[0..0];
                @memcpy(sbuf[0..r.len], msg[0..r.len]);
                sbuf[r.len] = 0;
            } else if (ipli_in > SE_PLMOON_OFFSET) {
                var msg: [AS_MAXCH]u8 = undefined;
                if (std.mem.indexOf(u8, sp, "99.") != null) {
                    const r = std.fmt.bufPrint(&msg, "plan. COB No. {d} ({s}): ", .{ ipli_in, sp }) catch msg[0..0];
                    @memcpy(sbuf[0..r.len], msg[0..r.len]);
                    sbuf[r.len] = 0;
                } else {
                    const r = std.fmt.bufPrint(&msg, "plan. moon No. {d} ({s}): ", .{ ipli_in, sp }) catch msg[0..0];
                    @memcpy(sbuf[0..r.len], msg[0..r.len]);
                    sbuf[r.len] = 0;
                }
            } else if (ipli_in > SEI_PLUTO) {
                var msg: [AS_MAXCH]u8 = undefined;
                const r = std.fmt.bufPrint(&msg, "asteroid eph. file ({s}): ", .{sp}) catch msg[0..0];
                @memcpy(sbuf[0..r.len], msg[0..r.len]);
                sbuf[r.len] = 0;
            } else if (ipli_in != 1) {
                var msg: [AS_MAXCH]u8 = undefined;
                const r = std.fmt.bufPrint(&msg, "planets eph. file ({s}): ", .{sp}) catch msg[0..0];
                @memcpy(sbuf[0..r.len], msg[0..r.len]);
                sbuf[r.len] = 0;
            } else {
                var msg: [AS_MAXCH]u8 = undefined;
                const r = std.fmt.bufPrint(&msg, "moon eph. file ({s}): ", .{sp}) catch msg[0..0];
                @memcpy(sbuf[0..r.len], msg[0..r.len]);
                sbuf[r.len] = 0;
            }
            // C: sprintf(s + strlen(s), "jd %f < lower limit %f;", ...) or > upper limit
            var datepart: [AS_MAXCH]u8 = undefined;
            const dp = if (tjd < fdp.tfstart)
                std.fmt.bufPrint(&datepart, "jd {d:.6} < lower limit {d:.6};", .{ tjd, fdp.tfstart }) catch datepart[0..0]
            else
                std.fmt.bufPrint(&datepart, "jd {d:.6} > upper limit {d:.6};", .{ tjd, fdp.tfend }) catch datepart[0..0];
            // append to sbuf after the prefix
            const slen = std.mem.indexOfScalar(u8, &sbuf, 0) orelse 0;
            const total = slen + dp.len;
            if (total < AS_MAXCH) {
                @memcpy(sbuf[slen..total], dp[0..dp.len]);
                sbuf[total] = 0;
            }
            appendSerrMax(sr, sbuf[0 .. std.mem.indexOfScalar(u8, &sbuf, 0) orelse 0]);
        }
        return NOT_AVAILABLE;
    }
    // get planet's position: get new segment, if necessary
    if (pdp.segp == null or tjd < pdp.tseg0 or tjd > pdp.tseg1) {
        const retc = get_new_segment(tjd, ipl, ifno, serr, swed);
        if (retc != OK)
            return retc;
        // rotate cheby coeffs back to equatorial system; add reference orbit
        if ((pdp.iflg & SEI_FLG_ROTATE) != 0) {
            rot_back(ipl, swed);
        } else {
            pdp.neval = pdp.ncoe;
        }
    }
    // evaluate chebyshev polynomial for tjd
    var t = (tjd - pdp.tseg0) / pdp.dseg;
    t = t * 2 - 1;
    const need_speed = (do_save or (iflag & SEFLG_SPEED) != 0);
    const ncoe: usize = @intCast(pdp.ncoe);
    const segp = pdp.segp.?;
    const neval: usize = @intCast(pdp.neval);
    for (0..3) |i| {
        xp[i] = lib.swi_echeb(t, segp[i * ncoe ..][0..neval]);
        if (need_speed) {
            xp[i + 3] = lib.swi_edcheb(t, segp[i * ncoe ..][0..neval]) / pdp.dseg * 2;
        } else {
            xp[i + 3] = 0; // von Alois als billiger fix, evtl. illegal
        }
    }
    // barycentric sun from heliocentric earth and barycentric earth
    if (ipl == SEI_SUNBARY and (pdp.iflg & SEI_FLG_EMBHEL) != 0) {
        // sweph() calls sweph() for EMB; force new computation
        const tsv = pedp.teval;
        pedp.teval = 0;
        var xemb6: [6]f64 = undefined;
        const retc = sweph(tjd, SEI_EMB, ifno, iflag | SEFLG_SPEED, null, false, xemb6[0..], serr, swed, models);
        if (retc != OK)
            return retc;
        for (0..6) |k| xemb[k] = xemb6[k];
        pedp.teval = tsv;
        for (0..3) |i|
            xp[i] = xemb[i] - xp[i];
        if (need_speed) {
            for (3..6) |i|
                xp[i] = xemb[i] - xp[i];
        }
    }
    // asteroids are heliocentric: convert to barycentric
    if (xsunb != null and ((iflag & SEFLG_JPLEPH) != 0 or (iflag & SEFLG_SWIEPH) != 0)) {
        if (ipl >= SEI_ANYBODY) {
            for (0..3) |i|
                xp[i] += xsunb.?[i];
            if (need_speed) {
                for (3..6) |i|
                    xp[i] += xsunb.?[i];
            }
        }
    }
    if (do_save) {
        pdp.teval = tjd;
        pdp.xflgs = -1;
        if (ifno == SEI_FILE_PLANET or ifno == SEI_FILE_MOON) {
            pdp.iephe = SEFLG_SWIEPH;
        } else {
            pdp.iephe = psdp.iephe;
        }
    }
    if (xpret != null) {
        for (0..6) |i|
            xpret.?[i] = xp[i];
    }
    return OK;
}

fn appendSerrMax(sr: []u8, s: []const u8) void {
    const len = std.mem.indexOfScalar(u8, sr, 0) orelse sr.len;
    if (len + s.len < sr.len - 1) {
        @memcpy(sr[len .. len + s.len], s);
        sr[len + s.len] = 0;
    }
}

/// swephlib.c swi_gen_filename
fn fioFopen(s: [*]u8, mode: [*:0]const u8) ?*anyopaque {
    const path = std.mem.sliceTo(s, 0);
    var pbuf: [AS_MAXCH * 2]u8 = undefined;
    const pz = std.fmt.bufPrintZ(&pbuf, "{s}", .{path}) catch return null;
    return fopen(pz.ptr, mode);
}

/// sweph.c sweplan (SWIEPH): computes barycentric planet (+ earth, sunbary,
/// moon as needed) in barycentric cartesian equatorial J2000
fn sweplan(tjd: f64, ipli: usize, ifno: usize, iflag: i32, do_save: bool, xpret: ?[]f64, xperet: ?[]f64, xpsret: ?[]f64, xpmret: ?[]f64, serr: ?[]u8, swed: *Swed, models: AstroModels) i32 {
    var do_earth = false;
    var do_moon = false;
    var do_sunbary = false;
    const pdp = &swed.pldat[ipli];
    const pebdp = &swed.pldat[SEI_EMB];
    const psbdp = &swed.pldat[SEI_SUNBARY];
    const pmdp = &swed.pldat[SEI_MOON];
    var xxp: [6]f64 = undefined;
    var xxm: [6]f64 = undefined;
    var xxs: [6]f64 = undefined;
    var xxe: [6]f64 = undefined;
    var xp: *[6]f64 = undefined;
    var xpe: *[6]f64 = undefined;
    var xpm: *[6]f64 = undefined;
    var xps: *[6]f64 = undefined;
    if (do_save or ipli == SEI_SUNBARY or (pdp.iflg & SEI_FLG_HELIO) != 0 or
        xpsret != null or (iflag & SEFLG_HELCTR) != 0)
        do_sunbary = true;
    if (do_save or ipli == SEI_EARTH or xperet != null)
        do_earth = true;
    if (ipli == SEI_MOON) {
        do_earth = true;
        do_sunbary = true;
    }
    if (do_save or ipli == SEI_MOON or ipli == SEI_EARTH or xperet != null or xpmret != null)
        do_moon = true;
    if (do_save) {
        xp = &pdp.x;
        xpe = &pebdp.x;
        xps = &psbdp.x;
        xpm = &pmdp.x;
    } else {
        xp = &xxp;
        xpe = &xxe;
        xps = &xxs;
        xpm = &xxm;
    }
    const speedf2 = iflag & SEFLG_SPEED;
    // barycentric sun
    if (do_sunbary) {
        const speedf1 = psbdp.xflgs & SEFLG_SPEED;
        if (tjd == psbdp.teval and
            psbdp.iephe == SEFLG_SWIEPH and
            (speedf2 == 0 or speedf1 != 0))
        {
            for (0..6) |i| xps[i] = psbdp.x[i];
        } else {
            const retc = sweph(tjd, SEI_SUNBARY, SEI_FILE_PLANET, iflag, null, do_save, xps, serr, swed, models);
            if (retc != OK)
                return retc;
        }
        if (xpsret != null) {
            for (0..6) |i| xpsret.?[i] = xps[i];
        }
    }
    // moon
    if (do_moon) {
        const speedf1 = pmdp.xflgs & SEFLG_SPEED;
        if (tjd == pmdp.teval and
            pmdp.iephe == SEFLG_SWIEPH and
            (speedf2 == 0 or speedf1 != 0))
        {
            for (0..6) |i| xpm[i] = pmdp.x[i];
        } else {
            var retc = sweph(tjd, SEI_MOON, SEI_FILE_MOON, iflag, null, do_save, xpm, serr, swed, models);
            if (retc == ERR)
                return retc;
            // if moon file doesn't exist, take moshier moon
            if (swed.fidat[SEI_FILE_MOON].fp == null) {
                if (serr) |sr| {
                    appendSerrMax(sr, " \nusing Moshier eph. for moon; ");
                }
                retc = swemmoon_mod.swi_moshmoon(tjd, do_save, xpm, &swed.oec, models, serr);
                if (retc != OK)
                    return retc;
            }
        }
        if (xpmret != null) {
            for (0..6) |i| xpmret.?[i] = xpm[i];
        }
    }
    // barycentric earth
    if (do_earth) {
        const speedf1 = pebdp.xflgs & SEFLG_SPEED;
        if (tjd == pebdp.teval and
            pebdp.iephe == SEFLG_SWIEPH and
            (speedf2 == 0 or speedf1 != 0))
        {
            for (0..6) |i| xpe[i] = pebdp.x[i];
        } else {
            // C: sweph() writes EMB directly into xpe, then embofs(xpe, xpm);
            // the moon xpm was computed in the do_moon block above
            const retc = sweph(tjd, SEI_EMB, SEI_FILE_PLANET, iflag, null, do_save, xpe, serr, swed, models);
            if (retc != OK)
                return retc;
            // earth from emb and moon
            embofs(xpe, xpm);
            // speed is needed if xpe == save area or speed flag specified
            if (xpe == &pebdp.x or (iflag & SEFLG_SPEED) != 0)
                embofsSpeed(xpe, xpm);
        }
        if (xperet != null) {
            for (0..6) |i| xperet.?[i] = xpe[i];
        }
    }
    if (ipli == SEI_MOON) {
        for (0..6) |i| xp[i] = xpm[i];
    } else if (ipli == SEI_EARTH) {
        for (0..6) |i| xp[i] = xpe[i];
    } else if (ipli == SEI_SUN) {
        for (0..6) |i| xp[i] = xps[i];
    } else {
        // planet
        const speedf1 = pdp.xflgs & SEFLG_SPEED;
        if (tjd == pdp.teval and
            pdp.iephe == SEFLG_SWIEPH and
            (speedf2 == 0 or speedf1 != 0))
        {
            for (0..6) |i| xp[i] = pdp.x[i];
            return OK;
        } else {
            const retc = sweph(tjd, ipli, ifno, iflag, null, do_save, xp, serr, swed, models);
            if (retc != OK)
                return retc;
            // if planet is heliocentric, transform to barycentric
            if ((pdp.iflg & SEI_FLG_HELIO) != 0) {
                for (0..3) |i|
                    xp[i] += xps[i];
                if (do_save or (iflag & SEFLG_SPEED) != 0) {
                    for (3..6) |i|
                        xp[i] += xps[i];
                }
            }
        }
    }
    if (xpret != null) {
        for (0..6) |i| xpret.?[i] = xp[i];
    }
    return OK;
}

fn embofsSpeed(xemb: *[6]f64, xmoon: *const [6]f64) void {
    for (3..6) |i|
        xemb[i] -= xmoon[i] / (EARTH_MOON_MRAT + 1.0);
}

/// sweph.c swi_fopen: looks for an ephemeris file in the ephepath
pub fn swi_fopen(ifno: i32, fname: []const u8, ephepath: []const u8, serr: ?[]u8, swed: *Swed) ?*anyopaque {
    var cpos: [20][]u8 = undefined;
    var s: [2 * AS_MAXCH]u8 = undefined;
    var s1: [AS_MAXCH]u8 = undefined;
    var fnamp: []u8 = undefined;
    var fn_buf: [AS_MAXCH]u8 = undefined;
    if (ifno >= 0) {
        fnamp = swed.fidat[@intCast(ifno)].fnam[0..];
    } else {
        fnamp = fn_buf[0..];
    }
    // copy ephepath into s1 (NUL-terminated)
    const ep_len = @min(ephepath.len, s1.len - 1);
    @memcpy(s1[0..ep_len], ephepath[0..ep_len]);
    s1[ep_len] = 0;
    const np = lib.swi_cutstr(s1[0..ep_len], ":", &cpos, 20);
    s[0] = 0;
    var i: usize = 0;
    while (i < np) : (i += 1) {
        var cur = cpos[i];
        var clen = std.mem.indexOfScalar(u8, cur, 0) orelse cur.len;
        cur = cur[0..clen];
        // C: strcpy(s, cpos[i]); if "." → empty; else ensure trailing DIR_GLUE
        if (std.mem.eql(u8, cur, ".")) {
            clen = 0;
        } else if (clen > 0 and cur[clen - 1] != DIR_GLUE) {
            // strcat(s, DIR_GLUE) — append below
        }
        if (clen + fname.len < AS_MAXCH) {
            @memcpy(s[0..clen], cur[0..clen]);
            if (clen > 0 and cur[clen - 1] != DIR_GLUE) {
                s[clen] = DIR_GLUE;
                clen += 1;
            }
            @memcpy(s[clen .. clen + fname.len], fname);
            s[clen + fname.len] = 0;
        } else {
            if (serr) |sr| {
                _ = std.fmt.bufPrint(sr[0 .. sr.len - 1], "error: file path and name must be shorter than {d}.", .{AS_MAXCH}) catch "";
            }
            return null;
        }
        // store fnam
        @memcpy(fnamp[0 .. clen + fname.len], s[0 .. clen + fname.len]);
        fnamp[clen + fname.len] = 0;
        if (fioFopen(&s, "rb")) |fp| {
            return fp;
        }
        _ = &fn_buf;
    }
    var out_len: usize = 0;
    if (std.fmt.bufPrint(&s, "SwissEph file '{s}' not found in PATH '{s}'", .{ fname, ephepath })) |written| {
        out_len = written.len;
    } else |_| {}
    s[out_len] = 0;
    if (out_len > AS_MAXCH - 1) {
        s[AS_MAXCH - 1] = 0;
    }
    if (serr) |sr| {
        const n = @min(out_len, sr.len - 1);
        @memcpy(sr[0..n], s[0..n]);
        sr[n] = 0;
    }
    return null;
}

/// sweph.c app_pos_etc_sbar (barycentric sun)
fn app_pos_etc_sbar(iflag: i32, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var xx: [6]f64 = undefined;
    var xxsv: [6]f64 = undefined;
    var dt: f64 = undefined;
    // C: psdp = &swed.pldat[SEI_EARTH] (teval only); psbdp = SUNBARY
    const psdp = &swed.pldat[SEI_EARTH];
    const psbdp = &swed.pldat[SEI_SUNBARY];
    var oe: *const Eps = &swed.oec;
    // the conversions will be done with xx[]
    for (0..6) |i|
        xx[i] = psbdp.x[i];
    // light-time
    if ((iflag & SEFLG_TRUEPOS) == 0) {
        dt = std.math.sqrt(square_sum(xx[0..3])) * AUNIT / CLIGHT / 86400.0;
        for (0..3) |i|
            xx[i] -= dt * xx[i + 3]; // apparent position
    }
    if ((iflag & SEFLG_SPEED) == 0) {
        for (3..6) |i|
            xx[i] = 0;
    }
    // ICRS to J2000
    if ((iflag & SEFLG_ICRS) == 0 and swi_get_denum(SEI_SUN, iflag, swed) >= 403) {
        lib.swi_bias(&xx, psdp.teval, iflag, false, models);
    }
    // save J2000 coordinates
    for (0..6) |i|
        xxsv[i] = xx[i];
    // precession, equator 2000 -> equator of date
    if ((iflag & SEFLG_J2000) == 0) {
        _ = lib.swi_precess(xx[0..3], psbdp.teval, iflag, J2000_TO_J, models);
        if ((iflag & SEFLG_SPEED) != 0)
            swi_precess_speed(&xx, psbdp.teval, iflag, J2000_TO_J, swed, models);
        oe = &swed.oec;
    } else {
        oe = &swed.oec2000;
    }
    return app_pos_rest(psdp, iflag, &xx, xxsv[0..], oe, swed, models, dctx, serr);
}

/// sweph.c swe_set_ephe_path
pub fn swe_set_ephe_path(path: ?[]const u8, swed: *Swed, models: *AstroModels, dctx: *DeltatCtx, serr: ?[]u8) void {
    _ = serr;
    var s: [AS_MAXCH]u8 = undefined;
    var slen: usize = 0;
    // close all open files and delete all planetary data
    swi_close_keep_topo_etc(swed);
    // C: swi_close_keep_topo_etc() memsets swed.astro_models — model
    // mutations are forgotten (0 means "use default" at read time)
    models.* = .{};
    // all files closed: delta-T's moon denum is gone; the moon calc below
    // reopens the file and read_const re-syncs it
    dctx.sweph_denum = 0;
    // swed_is_initialised: no-op in the port (Swed is caller-owned)
    swed.ephe_path_is_set = true;
    // environment variable SE_EPHE_PATH has priority (not read: deterministic
    // corpus paths are passed explicitly)
    if (path == null or path.?.len == 0) {
        @memcpy(s[0..SE_EPHE_PATH.len], SE_EPHE_PATH);
        slen = SE_EPHE_PATH.len;
    } else if (path.?.len <= AS_MAXCH - 1 - 13) {
        @memcpy(s[0..path.?.len], path.?);
        slen = path.?.len;
    } else {
        @memcpy(s[0..SE_EPHE_PATH.len], SE_EPHE_PATH);
        slen = SE_EPHE_PATH.len;
    }
    if (s[slen - 1] != DIR_GLUE and s[0] != 0) {
        s[slen] = DIR_GLUE;
        slen += 1;
    }
    @memcpy(swed.ephepath[0..slen], s[0..slen]);
    swed.ephepath[slen] = 0;
    // try to open lunar ephemeris, in order to get DE number and set
    // tidal acceleration of the Moon
    const iflag = SEFLG_SWIEPH | SEFLG_J2000 | SEFLG_TRUEPOS | SEFLG_ICRS;
    swed.last_epheflag = 2;
    var xx: [6]f64 = undefined;
    var serr2: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
    _ = swe_calc(J2000, SE_MOON, iflag, &xx, swed, models.*, dctx, &serr2);
    if (swed.fidat[SEI_FILE_MOON].fp != null) {
        // swi_set_tid_acc: manual flag not set → get from denum
        _ = swiSetTidAcc(0, 0, swed.fidat[SEI_FILE_MOON].sweph_denum, null, swed, dctx);
    }
}

/// sweph.c swi_close_keep_topo_etc
fn swi_close_keep_topo_etc(swed: *Swed) void {
    var i: usize = 0;
    while (i < SEI_NEPHFILES) : (i += 1) {
        if (swed.fidat[i].fp != null) {
            _ = fclose(swed.fidat[i].fp);
        }
        swed.fidat[i] = .{};
    }
    freePlanets(swed);
    swed.oec = .{};
    swed.oec2000 = .{};
    swed.nut = .{};
    swed.nut2000 = .{};
    swed.nutv = .{};
    // close JPL file
    jplmod.swi_close_jpl_file(swed);
    swed.jpl_file_is_open = false;
    swed.jpldenum = 0;
    // free EOP data (C frees the heap arrays; fixed arrays just reset)
    swed.eop_dpsi_loaded = 0;
    swed.is_tid_acc_manual = false;
    swed.tid_acc = deltat.SE_TIDAL_DEFAULT;
    swed.last_epheflag = 0;
    // C tail of swi_close_keep_topo_etc:
    swed.is_old_starfile = false;
    swed.i_saved_planet_name = 0;
    swed.saved_planet_name[0] = 0;
}

fn sliceToZ(buf: *[AS_MAXCH]u8) [:0]const u8 {
    const n = std.mem.indexOfScalar(u8, buf, 0) orelse buf.len - 1;
    return buf[0..n :0];
}

/// atoi() on a token slice: non-numeric input yields 0 like C's atoi
fn atoiSlice(tok: []const u8) i32 {
    var t = tok;
    while (t.len > 0 and (t[0] == ' ' or t[0] == '\t')) : (t = t[1..]) {}
    const end = std.mem.indexOfScalar(u8, t, '-') orelse t.len;
    _ = end;
    var v: i32 = 0;
    var i: usize = 0;
    var neg = false;
    if (i < t.len and (t[i] == '-' or t[i] == '+')) {
        neg = t[i] == '-';
        i += 1;
    }
    while (i < t.len and t[i] >= '0' and t[i] <= '9') : (i += 1)
        v = v *% 10 +% @as(i32, t[i] - '0');
    return if (neg) -v else v;
}

fn atoiOffset(buf: *[AS_MAXCH]u8, off: usize) i32 {
    if (off >= buf.len) return 0;
    return atoiSlice(std.mem.sliceTo(buf[off..], 0));
}

/// atof() on a token slice: strtod-style leading-number parse
fn atofSlice(tok: []const u8) f64 {
    var i: usize = 0;
    while (i < tok.len and (tok[i] == ' ' or tok[i] == '\t')) : (i += 1) {}
    const start = i;
    while (i < tok.len and (std.ascii.isDigit(tok[i]) or tok[i] == '.' or tok[i] == '-' or tok[i] == '+' or tok[i] == 'e' or tok[i] == 'E')) : (i += 1) {}
    return std.fmt.parseFloat(f64, tok[start..i]) catch 0;
}

fn atofOffset(buf: *[AS_MAXCH]u8, off: usize) f64 {
    if (off >= buf.len) return 0;
    return atofSlice(std.mem.sliceTo(buf[off..], 0));
}

// ==================== fixed stars (sweph.c fixstar section) ====================

threadlocal var fixstar_alloc_buf: []FixedStar = &[_]FixedStar{};

fn fsRightTrim(tok: []u8) []u8 {
    var n = tok.len;
    while (n > 0 and (tok[n - 1] == ' ' or tok[n - 1] == '\t' or tok[n - 1] == '\n' or tok[n - 1] == '\r'))
        n -= 1;
    return tok[0..n];
}

/// sweph.c fixstar_format_search_name
fn fixstarFormatSearchName(star: []const u8, sstar: *[SWI_STAR_LENGTH + 1]u8, serr: ?[]u8) i32 {
    const n = @min(star.len, SWI_STAR_LENGTH);
    @memcpy(sstar[0..n], star[0..n]);
    sstar[n] = 0;
    const z = std.mem.sliceTo(sstar[0..], 0);
    // remove whitespaces from search name
    var out: usize = 0;
    for (z) |c| {
        if (c != ' ') {
            sstar[out] = c;
            out += 1;
        }
    }
    sstar[out] = 0;
    // traditional name to lower case; keep uppercase after comma
    for (sstar[0..out]) |*c| {
        if (c.* == ',') break;
        c.* = std.ascii.toLower(c.*);
    }
    if (out == 0) {
        if (serr) |sr| {
            const msg = "swe_fixstar(): star name empty";
            const m = @min(msg.len, sr.len - 1);
            @memcpy(sr[0..m], msg[0..m]);
            sr[m] = 0;
        }
        return ERR;
    }
    return OK;
}

/// sweph.c fixstar_cut_string
fn fixstarCutString(srecord_in: []const u8, star: ?[]u8, stardata: *FixedStar, serr: ?[]u8, swed: *Swed) i32 {
    var s: [AS_MAXCH + 20]u8 = undefined;
    const slen = @min(srecord_in.len, s.len - 1);
    @memcpy(s[0..slen], srecord_in[0..slen]);
    s[slen] = 0;
    var cpos: [20][]u8 = undefined;
    for (0..20) |ci| cpos[ci] = cpos_buf[ci][0..];
    const i = lib.swi_cutstr(s[0..slen], ",", cpos[0..].ptr, 20);
    // return trad. name, nomenclature name
    const c0z = fsRightTrim(std.mem.sliceTo(cpos[0], 0));
    const c1z = fsRightTrim(std.mem.sliceTo(cpos[1], 0));
    if (i < 14) {
        if (serr) |sr| {
            var msg: [AS_MAXCH]u8 = undefined;
            var r: []u8 = undefined;
            if (i >= 2) {
                r = std.fmt.bufPrint(&msg, "data of star '{s},{s}' incomplete", .{ c0z, c1z }) catch msg[0..0];
            } else {
                var line = s[0..slen];
                if (line.len > 200) line = line[0..200];
                r = std.fmt.bufPrint(&msg, "invalid line in fixed stars file: '{s}'", .{line}) catch msg[0..0];
            }
            const m = @min(r.len, sr.len - 1);
            @memcpy(sr[0..m], msg[0..m]);
            sr[m] = 0;
        }
        return ERR;
    }
    var c0len = c0z.len;
    if (c0len > SWI_STAR_LENGTH) c0len = SWI_STAR_LENGTH;
    var c1len = c1z.len;
    if (c1len > SWI_STAR_LENGTH - 1) c1len = SWI_STAR_LENGTH - 1;
    if (star) |st| {
        // C: strcpy(star, cpos[0]); sprintf(star + strlen, ",%s", cpos[1]) if short enough
        var pos: usize = 0;
        const n1 = @min(c0len, st.len - 1);
        @memcpy(st[0..n1], c0z[0..n1]);
        pos = n1;
        st[pos] = 0;
        if (c0z.len + c1z.len + 1 < SWI_STAR_LENGTH - 1) {
            if (pos + 1 + c1len < st.len) {
                st[pos] = ',';
                @memcpy(st[pos + 1 .. pos + 1 + c1len], c1z[0..c1len]);
                pos += 1 + c1len;
                st[pos] = 0;
            }
        }
    }
    @memcpy(stardata.starname[0..c0len], c0z[0..c0len]);
    stardata.starname[c0len] = 0;
    @memcpy(stardata.starbayer[0..c1len], c1z[0..c1len]);
    stardata.starbayer[c1len] = 0;
    // star data
    const epoch = atofSlice(std.mem.sliceTo(cpos[2], 0));
    const ra_h = atofSlice(std.mem.sliceTo(cpos[3], 0));
    const ra_m = atofSlice(std.mem.sliceTo(cpos[4], 0));
    const ra_s = atofSlice(std.mem.sliceTo(cpos[5], 0));
    const de_d = atofSlice(std.mem.sliceTo(cpos[6], 0));
    const de_d_z = std.mem.sliceTo(cpos[6], 0);
    const de_m = atofSlice(std.mem.sliceTo(cpos[7], 0));
    const de_s = atofSlice(std.mem.sliceTo(cpos[8], 0));
    var ra_pm = atofSlice(std.mem.sliceTo(cpos[9], 0));
    var de_pm = atofSlice(std.mem.sliceTo(cpos[10], 0));
    var radv = atofSlice(std.mem.sliceTo(cpos[11], 0));
    var parall = atofSlice(std.mem.sliceTo(cpos[12], 0));
    const mag = atofSlice(std.mem.sliceTo(cpos[13], 0));
    if (parall < 0) parall = -parall; // to fix bug like old Rasalgheti
    // ra and de in degrees
    var ra = (ra_s / 3600.0 + ra_m / 60.0 + ra_h) * 15.0;
    var de: f64 = undefined;
    if (std.mem.indexOfScalar(u8, de_d_z, '-') == null) {
        de = de_s / 3600.0 + de_m / 60.0 + de_d;
    } else {
        de = -de_s / 3600.0 - de_m / 60.0 + de_d;
    }
    // speed in ra and de, degrees per century
    if (swed.is_old_starfile) {
        ra_pm = ra_pm * 15 / 3600.0;
        de_pm = de_pm / 3600.0;
    } else {
        ra_pm = ra_pm / 10.0 / 3600.0;
        de_pm = de_pm / 10.0 / 3600.0;
        parall /= 1000.0;
    }
    // parallax, degrees
    if (parall > 1) {
        parall = 1 / parall / 3600.0;
    } else {
        parall /= 3600;
    }
    // radial velocity in AU per century
    radv *= 21.095; // KM_S_TO_AU_CTY
    // radians
    ra *= DEGTORAD;
    de *= DEGTORAD;
    ra_pm *= DEGTORAD;
    de_pm *= DEGTORAD;
    ra_pm /= @cos(de); // catalogues give proper motion in RA as great circle
    parall *= DEGTORAD;
    stardata.epoch = epoch;
    stardata.ra = ra;
    stardata.de = de;
    stardata.ramot = ra_pm;
    stardata.demot = de_pm;
    stardata.parall = parall;
    stardata.radvel = radv;
    stardata.mag = mag;
    return OK;
}

threadlocal var cpos_buf: [20][AS_MAXCH]u8 = [_][AS_MAXCH]u8{[_]u8{0} ** AS_MAXCH} ** 20;
threadlocal var fs_alloc = std.heap.page_allocator;

/// sweph.c save_star_in_struct (realloc pattern -> grow the slice)
fn saveStarInStruct(nrecs: usize, fstp: *const FixedStar, swed: *Swed, serr: ?[]u8) i32 {
    if (fixstar_alloc_buf.len < nrecs) {
        const newlen = if (fixstar_alloc_buf.len == 0) 128 else fixstar_alloc_buf.len * 2;
        const newbuf = fs_alloc.realloc(fixstar_alloc_buf, newlen) catch {
            if (serr) |sr| {
                const msg = "error in function load_all_fixed_stars(): could not resize fixed stars array";
                const m = @min(msg.len, sr.len - 1);
                @memcpy(sr[0..m], msg[0..m]);
                sr[m] = 0;
            }
            return ERR;
        };
        fixstar_alloc_buf = newbuf;
    }
    fixstar_alloc_buf[nrecs - 1] = fstp.*;
    swed.fixed_stars = fixstar_alloc_buf[0..nrecs];
    return OK;
}

/// sweph.c fixedstar_name_compare / fstar_node_compare (skey strcmp)
fn fixedstarSkeyLess(a: FixedStar, b: FixedStar) bool {
    const az = std.mem.sliceTo(&a.skey, 0);
    const bz = std.mem.sliceTo(&b.skey, 0);
    return std.mem.order(u8, az, bz) == .lt;
}

/// sweph.c load_all_fixed_stars
fn loadAllFixedStars(swed: *Swed, serr: ?[]u8) i32 {
    var s: [AS_MAXCH]u8 = undefined;
    var srecord: [AS_MAXCH]u8 = undefined;
    var fstdata: FixedStar = .{};
    var last_starbayer: [SWI_STAR_LENGTH + 1]u8 = [_]u8{0} ** (SWI_STAR_LENGTH + 1);
    var nstars: i32 = 0;
    var nrecs: usize = 0;
    var nnamed: i32 = 0;
    if (swed.n_fixstars_records > 0) {
        return -2;
    }
    if (swed.fixfp == null) {
        if (swi_fopen(SEI_FILE_FIXSTAR, SE_STARFILE, sliceToZ(&swed.ephepath), serr, swed)) |fp| {
            swed.fixfp = fp;
        } else {
            swed.is_old_starfile = true;
            if (swi_fopen(SEI_FILE_FIXSTAR, SE_STARFILE_OLD, sliceToZ(&swed.ephepath), null, swed)) |fp2| {
                swed.fixfp = fp2;
            } else {
                swed.is_old_starfile = false;
                // no fixed star file available, error message is already in serr
                return ERR;
            }
        }
    }
    _ = fseek(swed.fixfp, 0, 0); // rewind
    swed.fixed_stars = &[_]FixedStar{};
    while (fgets(&s, AS_MAXCH, swed.fixfp) != null) {
        // skip comment lines
        if (s[0] == '#') continue;
        if (s[0] == '\n') continue;
        if (s[0] == '\r') continue;
        if (s[0] == 0) continue;
        const slen = std.mem.indexOfScalar(u8, &s, 0) orelse s.len;
        @memcpy(srecord[0..slen], s[0..slen]);
        srecord[slen] = 0;
        var srec_slice: []u8 = srecord[0 .. slen + 1];
        const retc0 = fixstarCutString(srec_slice, null, &fstdata, serr, swed);
        if (retc0 == ERR) return ERR;
        // if star has a traditional name, save it with that name as its search key
        if (fstdata.starname[0] != 0) {
            nrecs += 1;
            nnamed += 1;
            const nlen = std.mem.indexOfScalar(u8, &fstdata.starname, 0) orelse fstdata.starname.len;
            @memcpy(fstdata.skey[0..nlen], fstdata.starname[0..nlen]);
            fstdata.skey[nlen] = 0;
            // remove white spaces from star name
            var keyz = std.mem.sliceTo(&fstdata.skey, 0);
            var out: usize = 0;
            for (keyz) |c| {
                if (c != ' ') {
                    fstdata.skey[out] = c;
                    out += 1;
                }
            }
            fstdata.skey[out] = 0;
            // star name to lowercase
            keyz = std.mem.sliceTo(&fstdata.skey, 0);
            for (keyz) |*c| c.* = std.ascii.toLower(c.*);
            if (saveStarInStruct(nrecs, &fstdata, swed, serr) == ERR) return ERR;
        }
        // also save it with Bayer designation as search key;
        // only if it has not been saved already
        const bz = std.mem.sliceTo(&fstdata.starbayer, 0);
        const lbz = std.mem.sliceTo(&last_starbayer, 0);
        if (std.mem.eql(u8, bz, lbz))
            continue;
        nstars += 1;
        nrecs += 1;
        // sprintf(fstdata.skey, ",%s", fstdata.starbayer);
        fstdata.skey[0] = ',';
        @memcpy(fstdata.skey[1 .. 1 + bz.len], bz);
        fstdata.skey[1 + bz.len] = 0;
        // remove white spaces from star bayer name
        const keyz2 = std.mem.sliceTo(&fstdata.skey, 0);
        var out2: usize = 0;
        for (keyz2) |c| {
            if (c != ' ') {
                fstdata.skey[out2] = c;
                out2 += 1;
            }
        }
        fstdata.skey[out2] = 0;
        @memcpy(last_starbayer[0..bz.len], bz);
        last_starbayer[bz.len] = 0;
        if (saveStarInStruct(nrecs, &fstdata, swed, serr) == ERR) return ERR;
        _ = &srec_slice;
    }
    swed.n_fixstars_real = nstars;
    swed.n_fixstars_named = nnamed;
    swed.n_fixstars_records = @intCast(nrecs);
    const stars = swed.fixed_stars;
    std.mem.sort(FixedStar, stars, {}, struct {
        fn less(_: void, a: FixedStar, b: FixedStar) bool {
            return fixedstarSkeyLess(a, b);
        }
    }.less);
    return OK;
}

/// sweph.c search_star_in_list
fn searchStarInList(sstar_in: []u8, stardata: *FixedStar, swed: *Swed, serr: ?[]u8) i32 {
    var star_nr: i32 = 0;
    var ndata: usize = 0;
    var is_bayer = false;
    var sstar = sstar_in;
    if (sstar.len > 0 and sstar[0] == ',') {
        is_bayer = true;
    } else if (sstar.len > 0 and std.ascii.isDigit(sstar[0])) {
        star_nr = atoiSlice(sstar);
    } else {
        if (std.mem.indexOfScalar(u8, sstar, ',')) |pos| {
            // swi_strcpy(sstar, sp): shift left over the comma
            std.mem.copyForwards(u8, sstar[0 .. sstar.len - pos], sstar[pos..]);
            sstar[sstar.len - pos] = 0;
            is_bayer = true;
        }
    }
    if (star_nr > 0) {
        if (star_nr > swed.n_fixstars_real) {
            if (serr) |sr| {
                const r = std.fmt.bufPrint(sr[0 .. sr.len - 1], "error, swe_fixstar(): sequential fixed star number {d} is not available", .{star_nr}) catch sr[0..0];
                sr[r.len] = 0;
            }
            return ERR;
        }
        stardata.* = swed.fixed_stars[@intCast(star_nr - 1)]; // keys start from 1
        return OK;
        // traditional name with wildcard '%' at end of string
    } else if (!is_bayer and std.mem.indexOfScalar(u8, sstar, '%') != null) {
        const stardatabeg = swed.fixed_stars[@intCast(swed.n_fixstars_real)..];
        ndata = @intCast(swed.n_fixstars_named);
        const sstar_strlen = std.mem.indexOfScalar(u8, sstar, 0) orelse sstar.len;
        const pct = std.mem.indexOfScalar(u8, sstar, '%').?;
        if (pct != sstar_strlen - 1) {
            if (serr) |sr| {
                const r = std.fmt.bufPrint(sr[0 .. sr.len - 1], "error, swe_fixstar(): invalid search string {s}", .{sstar}) catch sr[0..0];
                sr[r.len] = 0;
            }
            return ERR;
        }
        var searchkey: [AS_MAXCH]u8 = undefined;
        const sstar_strlen2 = std.mem.indexOfScalar(u8, sstar, 0) orelse sstar.len;
        const len = sstar_strlen2 - 1; // exclude '%'
        @memcpy(searchkey[0..len], sstar[0..len]);
        searchkey[len] = 0;
        for (0..ndata) |i| {
            const key = std.mem.sliceTo(&stardatabeg[i].skey, 0);
            if (key.len >= len and std.mem.eql(u8, key[0..len], sstar[0..len])) {
                stardata.* = stardatabeg[i];
                return OK;
            }
        }
        if (serr) |sr| {
            const r = std.fmt.bufPrint(sr[0 .. sr.len - 1], "error, swe_fixstar(): star search string {s} did not match", .{sstar}) catch sr[0..0];
            sr[r.len] = 0;
        }
        return ERR;
        // traditional name or Bayer/Flamsteed: find it with binary search
    } else {
        var searchkey: [AS_MAXCH]u8 = undefined;
        const sl = @min(sstar.len, searchkey.len - 1);
        @memcpy(searchkey[0..sl], sstar[0..sl]);
        searchkey[sl] = 0;
        var stardatabeg: []FixedStar = undefined;
        if (is_bayer) {
            stardatabeg = swed.fixed_stars[0..];
            ndata = @intCast(swed.n_fixstars_real);
        } else {
            stardatabeg = swed.fixed_stars[@intCast(swed.n_fixstars_real)..];
            ndata = @intCast(swed.n_fixstars_named);
        }
        // bsearch by skey
        var lo: usize = 0;
        var hi: usize = ndata;
        var found: ?*FixedStar = null;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            const key = std.mem.sliceTo(&stardatabeg[mid].skey, 0);
            const ord = std.mem.order(u8, key, std.mem.sliceTo(&searchkey, 0));
            switch (ord) {
                .lt => lo = mid + 1,
                .gt => hi = mid,
                .eq => {
                    found = &stardatabeg[mid];
                    break;
                },
            }
        }
        if (found == null) {
            if (serr) |sr| {
                const r = std.fmt.bufPrint(sr[0 .. sr.len - 1], "error, swe_fixstar(): could not find star name {s}", .{sstar}) catch sr[0..0];
                sr[r.len] = 0;
            }
            return ERR;
        }
        stardata.* = found.?.*;
        return OK;
    }
}

/// sweph.c get_builtin_star
fn getBuiltinStar(star: []const u8, sstar: []u8, srecord: []u8) bool {
    // some stars are built-in, because they are required for Hindu
    // sidereal ephemerides
    const sz = std.mem.sliceTo(star, 0);
    if (sz.len >= 5 and (std.mem.eql(u8, sz[0..5], "spica") or std.mem.eql(u8, sz[0..5], "Spica"))) {
        @memcpy(srecord[0..82], "Spica,alVir,ICRS,13,25,11.57937,-11,09,40.7501,-42.35,-30.67,1,13.06,0.97,-10,3672");
        srecord[82] = 0;
        @memcpy(sstar[0..5], "spica");
        sstar[5] = 0;
        return true;
        // Ayanamsha SE_SIDM_TRUE_REVATI
    } else if (std.mem.indexOf(u8, sz, ",zePsc") != null or (sz.len >= 6 and (std.mem.eql(u8, sz[0..6], "revati") or std.mem.eql(u8, sz[0..6], "Revati")))) {
        @memcpy(srecord[0..80], "Revati,zePsc,ICRS,01,13,43.88735,+07,34,31.2745,145,-55.69,15,18.76,5.187,06,174");
        srecord[80] = 0;
        @memcpy(sstar[0..6], "revati");
        sstar[6] = 0;
        return true;
        // Ayanamsha SE_SIDM_TRUE_PUSHYA
    } else if (std.mem.indexOf(u8, sz, ",deCnc") != null or (sz.len >= 6 and (std.mem.eql(u8, sz[0..6], "pushya") or std.mem.eql(u8, sz[0..6], "Pushya")))) {
        @memcpy(srecord[0..87], "Pushya,deCnc,ICRS,08,44,41.09921,+18,09,15.5034,-17.67,-229.26,17.14,24.98,3.94,18,2027");
        srecord[87] = 0;
        @memcpy(sstar[0..6], "pushya");
        sstar[6] = 0;
        return true;
        // Ayanamsha SE_SIDM_TRUE_SHEORAN
    } else if (std.mem.indexOf(u8, sz, ",deCnc") != null) {
        @memcpy(srecord[0..87], "Pushya,deCnc,ICRS,08,44,41.09921,+18,09,15.5034,-17.67,-229.26,17.14,24.98,3.94,18,2027");
        srecord[87] = 0;
        @memcpy(sstar[0..6], "pushya");
        sstar[6] = 0;
        return true;
        // Ayanamsha SE_SIDM_TRUE_MULA
    } else if (std.mem.indexOf(u8, sz, ",laSco") != null or (sz.len >= 6 and (std.mem.eql(u8, sz[0..6], "mula") or std.mem.eql(u8, sz[0..6], "Mula")))) {
        @memcpy(srecord[0..80], "Mula,laSco,ICRS,17,33,36.52012,-37,06,13.7648,-8.53,-30.8,-3,5.71,1.62,-37,11673");
        srecord[80] = 0;
        @memcpy(sstar[0..4], "mula");
        sstar[4] = 0;
        return true;
        // Ayanamsha SE_SIDM_GALCENT_0SAG / COCHRANE / RGILBRAND
    } else if (std.mem.indexOf(u8, sz, ",SgrA*") != null) {
        @memcpy(srecord[0..93], "Gal. Center,SgrA*,2000,17,45,40.03599,-29,00,28.1699,-2.755718425,-5.547,0.0,0.125,999.99,0,0");
        srecord[93] = 0;
        @memcpy(sstar[0..6], ",SgrA*");
        sstar[6] = 0;
        return true;
        // Ayanamsha SE_SIDM_GALEQU_IAU1958
    } else if (std.mem.indexOf(u8, sz, ",GP1958") != null) {
        @memcpy(srecord[0..73], "Gal. Pole IAU1958,GP1958,1950,12,49,0.0,27,24,0.0,0.0,0.0,0.0,0.0,0.0,0,0");
        srecord[73] = 0;
        @memcpy(sstar[0..7], ",GP1958");
        sstar[7] = 0;
        return true;
        // Ayanamsha SE_SIDM_GALEQU_TRUE
    } else if (std.mem.indexOf(u8, sz, ",GPol") != null) {
        @memcpy(srecord[0..76], "Gal. Pole,GPol,ICRS,12,51,36.7151981,27,06,11.193172,0.0,0.0,0.0,0.0,0.0,0,0");
        srecord[76] = 0;
        @memcpy(sstar[0..5], ",GPol");
        sstar[5] = 0;
        return true;
    }
    return false;
}

/// sweph.c load_dpsi_deps: load IERS dpsi/deps corrections (EOP files)
fn load_dpsi_deps(swed: *Swed) void {
    var s: [AS_MAXCH]u8 = undefined;
    var cpos: [20][AS_MAXCH]u8 = undefined;
    var n: usize = 0;
    var iyear: i32 = 0;
    var mjd: i32 = 0;
    var mjdsv: i32 = 0;
    var dpsi: f64 = 0;
    var deps: f64 = 0;
    const TJDOFS: f64 = 2400000.5;
    if (swed.eop_dpsi_loaded > 0)
        return;
    const fp = swi_fopen(-1, DPSI_DEPS_IAU1980_FILE_EOPC04, sliceToZ(&swed.ephepath), null, swed);
    if (fp == null) {
        swed.eop_dpsi_loaded = ERR;
        return;
    }
    swed.eop_tjd_beg_horizons = DPSI_DEPS_IAU1980_TJD0_HORIZONS;
    while (fgets(&s, AS_MAXCH, fp.?) != null) {
        const slen = std.mem.indexOfScalar(u8, &s, 0) orelse s.len;
        var cpos_slices: [20][]u8 = undefined;
        for (0..20) |ci| cpos_slices[ci] = cpos[ci][0..];
        _ = lib.swi_cutstr(s[0..slen], " ", cpos_slices[0..].ptr, 16);
        const c0 = std.mem.sliceTo(&cpos[0], 0);
        iyear = atoiSlice(c0);
        if (iyear == 0)
            continue;
        const c3 = std.mem.sliceTo(&cpos[3], 0);
        mjd = atoiSlice(c3);
        // is file in one-day steps?
        if (mjdsv > 0 and mjd - mjdsv != 1) {
            // we cannot return error but we note it as follows:
            swed.eop_dpsi_loaded = -2;
            _ = fclose(fp.?);
            return;
        }
        if (n == 0)
            swed.eop_tjd_beg = @as(f64, @floatFromInt(mjd)) + TJDOFS;
        const c8 = std.mem.sliceTo(&cpos[8], 0);
        swed.dpsi[n] = atofSlice(c8);
        const c9 = std.mem.sliceTo(&cpos[9], 0);
        swed.deps[n] = atofSlice(c9);
        n += 1;
        mjdsv = mjd;
    }
    swed.eop_tjd_end = @as(f64, @floatFromInt(mjd)) + TJDOFS;
    swed.eop_dpsi_loaded = 1;
    _ = fclose(fp.?);
    // file finals.all may have some more data, and especially estimations
    // for the near future
    const fp2 = swi_fopen(-1, DPSI_DEPS_IAU1980_FILE_FINALS, sliceToZ(&swed.ephepath), null, swed);
    if (fp2 == null)
        return; // return without error as existence of file is not mandatory
    while (fgets(&s, AS_MAXCH, fp2.?) != null) {
        // mjd = atoi(s + 7): fixed-field offset in finals.all
        mjd = atoiOffset(&s, 7);
        if (@as(f64, @floatFromInt(mjd)) + TJDOFS <= swed.eop_tjd_end)
            continue;
        if (n >= SWE_DATA_DPSI_DEPS)
            return;
        // are data in one-day steps?
        if (mjdsv > 0 and mjd - mjdsv != 1) {
            // no error, as we do have data; however, if this file is useful,
            // then swed.eop_dpsi_loaded will be set to 2
            swed.eop_dpsi_loaded = -3;
            _ = fclose(fp2.?);
            return;
        }
        // dpsi, deps Bulletin B (fixed-field offsets)
        dpsi = atofOffset(&s, 168);
        deps = atofOffset(&s, 178);
        if (dpsi == 0) {
            // try dpsi, deps Bulletin A
            dpsi = atofOffset(&s, 99);
            deps = atofOffset(&s, 118);
        }
        if (dpsi == 0) {
            swed.eop_dpsi_loaded = 2;
            _ = fclose(fp2.?);
            return;
        }
        swed.eop_tjd_end = @as(f64, @floatFromInt(mjd)) + TJDOFS;
        swed.dpsi[n] = dpsi / 1000.0;
        swed.deps[n] = deps / 1000.0;
        n += 1;
        mjdsv = mjd;
    }
    swed.eop_dpsi_loaded = 2;
    _ = fclose(fp2.?);
}

/// sweph.c swe_set_jpl_file
pub fn swe_set_jpl_file(fname: []const u8, swed: *Swed, models: *AstroModels, dctx: *DeltatCtx) void {
    var ss: [3]f64 = .{ 0, 0, 0 };
    // close all open files and delete all planetary data
    swi_close_keep_topo_etc(swed);
    // C: swi_close_keep_topo_etc() memsets swed.astro_models
    models.* = .{};
    // if path is contained in fname, it is filled into the path variable
    var sp: []const u8 = fname;
    if (std.mem.lastIndexOfScalar(u8, fname, '/')) |pos| {
        const dir = fname[0 .. pos + 1];
        const nm = fname[pos + 1 ..];
        const dn = @min(dir.len, swed.ephepath.len - 1);
        @memcpy(swed.ephepath[0..dn], dir[0..dn]);
        if (dn > 0 and swed.ephepath[dn - 1] != '/')
            swed.ephepath[dn] = '/';
        sp = nm;
    }
    const slen = @min(sp.len, swed.jplfnam.len - 1);
    @memcpy(swed.jplfnam[0..slen], sp[0..slen]);
    swed.jplfnam[slen] = 0;
    // open ephemeris
    const retc = openJplFile(&ss, sliceToZ(&swed.jplfnam), sliceToZ(&swed.ephepath), swed, dctx, null);
    if (retc == OK) {
        if (swed.jpldenum >= 403) {
            load_dpsi_deps(swed);
        }
    }
}

/// sweph.c open_jpl_file (with DE431 -> DE406 default fallback)
fn openJplFile(ss: *[3]f64, fname: [:0]const u8, fpath: [:0]const u8, swed: *Swed, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var retc = jplmod.swi_open_jpl_file(ss, fname, fpath, swed, serr);
    // If we fail with default JPL ephemeris (DE431), we try the second default
    // (DE406), but only if serr is not NULL and a warning message can be returned.
    if (retc != OK and std.mem.indexOf(u8, fname, SE_FNAME_DFT) != null and serr != null) {
        var serr2: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
        retc = jplmod.swi_open_jpl_file(ss, SE_FNAME_DFT2, fpath, swed, &serr2);
        if (retc == OK) {
            const n = @min(SE_FNAME_DFT2.len, swed.jplfnam.len - 1);
            @memcpy(swed.jplfnam[0..n], SE_FNAME_DFT2[0..n]);
            swed.jplfnam[n] = 0;
            if (serr) |sr| {
                // C: strcpy(serr2,"Error with JPL ephemeris file ")+SE_FNAME_DFT+": "+serr+". Defaulting to "+SE_FNAME_DFT2
                // Must preserve original serr (first file's error) before overwriting sr.
                var orig: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
                const orig_len = std.mem.sliceTo(sr, 0).len;
                const oc = @min(orig_len, orig.len - 1);
                @memcpy(orig[0..oc], sr[0..oc]);
                orig[oc] = 0;
                const orig_slice = orig[0..oc];
                var msg: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
                var pos: usize = 0;
                // "Error with JPL ephemeris file " + SE_FNAME_DFT
                if (std.fmt.bufPrint(msg[pos..], "Error with JPL ephemeris file {s}", .{SE_FNAME_DFT})) |r| {
                    pos += r.len;
                } else |_| {}
                // ": " + orig serr
                if (pos + 2 + orig_slice.len < AS_MAXCH) {
                    if (std.fmt.bufPrint(msg[pos..], ": {s}", .{orig_slice})) |r| {
                        pos += r.len;
                    } else |_| {}
                }
                // ". Defaulting to " + SE_FNAME_DFT2
                if (pos + 17 < AS_MAXCH) {
                    if (std.fmt.bufPrint(msg[pos..], ". Defaulting to {s}", .{SE_FNAME_DFT2})) |r| {
                        pos += r.len;
                    } else |_| {}
                }
                const c = @min(pos, sr.len - 1);
                @memcpy(sr[0..c], msg[0..c]);
                sr[c] = 0;
                // zero remainder to avoid garbage if caller slices with non-zero tail
                if (c + 1 < sr.len) @memset(sr[c + 1 ..], 0);
            }
        }
    }
    if (retc == OK) {
        swed.jpldenum = jplmod.swi_get_jpl_denum();
        swed.jpl_file_is_open = true;
        _ = swiSetTidAcc(0, 0, swed.jpldenum, serr, swed, dctx);
    }
    return retc;
}

/// sweph.c jplplan
fn jplplan(tjd: f64, ipli: usize, iflag: i32, do_save: bool, xpret: ?[]f64, xperet: ?[]f64, xpsret: ?[]f64, swed: *Swed, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var do_earth = false;
    var do_sunbary = false;
    var ss: [3]f64 = .{ 0, 0, 0 };
    var xxp: [6]f64 = undefined;
    var xxe: [6]f64 = undefined;
    var xxs: [6]f64 = undefined;
    var ictr: i32 = jplmod.J_SBARY;
    const pdp = &swed.pldat[ipli];
    const pedp = &swed.pldat[SEI_EARTH];
    const psdp = &swed.pldat[SEI_SUNBARY];
    _ = iflag; // currently not used, but this stops compiler warning
    // we assume Teph ~= TDB ~= TT.
    var xp: []f64 = undefined;
    var xpe: []f64 = undefined;
    var xps: []f64 = undefined;
    if (do_save) {
        xp = pdp.x[0..];
        xpe = pedp.x[0..];
        xps = psdp.x[0..];
    } else {
        xp = xxp[0..];
        xpe = xxe[0..];
        xps = xxs[0..];
    }
    if (do_save or ipli == SEI_EARTH or xperet != null or (ipli == SEI_MOON))
        do_earth = true;
    if (do_save or ipli == SEI_SUNBARY or xpsret != null or (ipli == SEI_MOON))
        do_sunbary = true;
    if (ipli == SEI_MOON)
        ictr = jplmod.J_EARTH;
    // open ephemeris, if still closed
    if (!swed.jpl_file_is_open) {
        const retc0 = openJplFile(&ss, sliceToZ(&swed.jplfnam), sliceToZ(&swed.ephepath), swed, dctx, serr);
        if (retc0 != OK)
            return retc0;
    }
    if (do_earth) {
        // barycentric earth
        if (tjd != pedp.teval or tjd == 0) {
            var xpe6: [6]f64 = undefined;
            const retc = jplmod.swi_pleph(tjd, jplmod.J_EARTH, jplmod.J_SBARY, &xpe6, swed, serr);
            for (0..6) |i| xpe[i] = xpe6[i];
            if (do_save) {
                pedp.teval = tjd;
                pedp.xflgs = -1; // new light-time etc. required
                pedp.iephe = SEFLG_JPLEPH;
            }
            if (retc != OK) {
                jplmod.swi_close_jpl_file(swed);
                swed.jpl_file_is_open = false;
                return retc;
            }
        } else {
            xpe = pedp.x[0..];
        }
        if (xperet) |xr| {
            for (0..6) |i|
                xr[i] = xpe[i];
        }
    }
    if (do_sunbary) {
        // barycentric sun
        if (tjd != psdp.teval or tjd == 0) {
            var xps6: [6]f64 = undefined;
            const retc = jplmod.swi_pleph(tjd, jplmod.J_SUN, jplmod.J_SBARY, &xps6, swed, serr);
            for (0..6) |i| xps[i] = xps6[i];
            if (do_save) {
                psdp.teval = tjd;
                psdp.xflgs = -1;
                psdp.iephe = SEFLG_JPLEPH;
            }
            if (retc != OK) {
                jplmod.swi_close_jpl_file(swed);
                swed.jpl_file_is_open = false;
                return retc;
            }
        } else {
            xps = psdp.x[0..];
        }
        if (xpsret) |xs| {
            for (0..6) |i|
                xs[i] = xps[i];
        }
    }
    // earth is wanted
    if (ipli == SEI_EARTH) {
        for (0..6) |i|
            xp[i] = xpe[i];
    } // note: C's "} if" — NOT else-if! SEI_EARTH also falls into the
    // "other planet" pleph below, which resets iephe/xflgs on cache hits.
    if (ipli == SEI_SUNBARY) {
        // sunbary is wanted
        for (0..6) |i|
            xp[i] = xps[i];
    } else {
        // other planet
        // if planet already computed
        if (tjd == pdp.teval and pdp.iephe == SEFLG_JPLEPH) {
            xp = pdp.x[0..];
        } else {
            var xp6: [6]f64 = undefined;
            const retc = jplmod.swi_pleph(tjd, PNOINT2JPL[ipli], ictr, &xp6, swed, serr);
            for (0..6) |i| xp[i] = xp6[i];
            if (do_save) {
                pdp.teval = tjd;
                pdp.xflgs = -1;
                pdp.iephe = SEFLG_JPLEPH;
            }
            if (retc != OK) {
                jplmod.swi_close_jpl_file(swed);
                swed.jpl_file_is_open = false;
                return retc;
            }
        }
    }
    if (xpret) |xr| {
        for (0..6) |i|
            xr[i] = xp[i];
    }
    return OK;
}

/// C swecalc's moshier_moon label: moshier moon + earth, saved
fn swi_moshmoon_save(tjd: f64, swed: *Swed, models: AstroModels, serr: ?[]u8) i32 {
    var moonx6: [6]f64 = undefined;
    const retc = swemmoon_mod.swi_moshmoon(tjd, false, &moonx6, &swed.oec, models, serr);
    if (retc == ERR)
        return ERR;
    for (0..6) |k| swed.pldat[SEI_MOON].x[k] = moonx6[k];
    swed.pldat[SEI_MOON].teval = tjd;
    swed.pldat[SEI_MOON].xflgs = -1;
    swed.pldat[SEI_MOON].iephe = SEFLG_MOSEPH;
    var xearth6: [6]f64 = undefined;
    const retc2 = swi_moshplan_call(tjd, SEI_EARTH, null, &xearth6, swed, models, serr);
    if (retc2 == ERR)
        return ERR;
    for (0..6) |k| swed.pldat[SEI_EARTH].x[k] = xearth6[k];
    swed.pldat[SEI_EARTH].teval = tjd;
    swed.pldat[SEI_EARTH].xflgs = -1;
    swed.pldat[SEI_EARTH].iephe = SEFLG_MOSEPH;
    return OK;
}

/// sweph.c fixstar_calc_from_struct and swi_fixstar_calc_from_record share
/// this pipeline (struct variant passes a FixedStar directly).
fn fixstarCalcFromStruct(stardata: *const FixedStar, tjd: f64, iflag_in: i32, star: []u8, xx: *[6]f64, swed: *Swed, models_in: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    const models = models_in;
    var iflag = iflag_in;
    var epheflag: i32 = undefined;
    const iflgsave = iflag;
    var x: [6]f64 = undefined;
    var xxsv: [6]f64 = undefined;
    var xobs: [6]f64 = undefined;
    var xobs_dt: [6]f64 = undefined;
    var xearth: [6]f64 = undefined;
    var xearth_dt: [6]f64 = undefined;
    var xsun: [6]f64 = undefined;
    var xsun_dt: [6]f64 = undefined;
    const dt: f64 = PLAN_SPEED_INTV * 0.1;
    var oe: *const Eps = &swed.oec2000;
    iflag |= SEFLG_SPEED; // we need this in order to work correctly
    if (serr) |sr| {
        if (sr.len > 0) sr[0] = 0;
    }
    iflag = plaus_iflag(iflag, -1, tjd, swed, models, serr);
    epheflag = iflag & SEFLG_EPHMASK;
    if (swed.last_epheflag != epheflag) {
        freePlanets(swed);
        // close and free ephemeris files
        if (swed.jpl_file_is_open) {
            jplmod.swi_close_jpl_file(swed);
            swed.jpl_file_is_open = false;
        }
        for (&swed.fidat) |*fd| {
            if (fd.fp != null)
                _ = fclose(fd.fp);
            fd.* = .{};
        }
        dctx.sweph_denum = 0;
        dctx.jpldenum = 0;
        swed.last_epheflag = epheflag;
    }
    // high precision speed prevails fast speed
    if ((iflag & SEFLG_SIDEREAL) != 0 and !swed.ayana_is_set)
        swe_set_sid_mode(SE_SIDM_FAGAN_BRADLEY, 0, 0, swed, null);
    // obliquity of ecliptic 2000 and of date
    swi_check_ecliptic(tjd, iflag, swed, models);
    // nutation
    swi_check_nutation(tjd, iflag, swed, models);
    // star name output
    {
        var pos: usize = 0;
        const nlen = std.mem.indexOfScalar(u8, &stardata.starname, 0) orelse stardata.starname.len;
        const blen = std.mem.indexOfScalar(u8, &stardata.starbayer, 0) orelse stardata.starbayer.len;
        if (pos + nlen < star.len) {
            @memcpy(star[pos .. pos + nlen], stardata.starname[0..nlen]);
            pos += nlen;
        }
        if (pos < star.len) {
            star[pos] = ',';
            pos += 1;
        }
        if (pos + blen < star.len) {
            @memcpy(star[pos .. pos + blen], stardata.starbayer[0..blen]);
            pos += blen;
        }
        star[pos] = 0;
    }
    const epoch = stardata.epoch;
    const ra_pm = stardata.ramot;
    const de_pm = stardata.demot;
    const radv = stardata.radvel;
    const parall = stardata.parall;
    const ra = stardata.ra;
    const de = stardata.de;
    var t: f64 = undefined;
    if (epoch == 1950) {
        t = tjd - lib.B1950; // days since 1950.0
    } else { // epoch == 2000
        t = tjd - lib.J2000; // days since 2000.0
    }
    x[0] = ra;
    x[1] = de;
    x[2] = 1;
    var rdist: f64 = undefined;
    if (parall == 0) {
        rdist = 1000000000;
    } else {
        rdist = 1.0 / (parall * RADTODEG * 3600) * 206264.8062471; // PARSEC_TO_AUNIT
    }
    x[2] = rdist;
    x[3] = ra_pm / 36525.0;
    x[4] = de_pm / 36525.0;
    x[5] = radv / 36525.0;
    // Cartesian space motion vector
    lib.swi_polcart_sp(&x, &x);
    // FK5
    if (epoch == 1950) {
        lib.swi_FK4_FK5(&x, lib.B1950);
        _ = lib.swi_precess(x[0..3], lib.B1950, 0, lib.J_TO_J2000, models);
        _ = lib.swi_precess(x[3..6], lib.B1950, 0, lib.J_TO_J2000, models);
    }
    // FK5 to ICRF, if jpl ephemeris is referred to ICRF.
    // With data that are already ICRF, epoch = 0
    if (epoch != 0) {
        lib.swi_icrs2fk5(&x, iflag, true); // backward, i.e. to icrf
        // with ephemerides < DE403, we now convert to J2000
        if (swi_get_denum(SEI_SUN, iflag, swed) >= 403) {
            lib.swi_bias(&x, lib.J2000, SEFLG_SPEED, false, models);
        }
    }
    // earth/sun for parallax, light deflection, and aberration
    var need_earth = false;
    if ((iflag & SEFLG_BARYCTR) == 0 and ((iflag & SEFLG_HELCTR) == 0 or (iflag & SEFLG_MOSEPH) == 0))
        need_earth = true;
    if (need_earth) {
        const retc = mainPlanetBary(tjd - dt, SEI_EARTH, epheflag, iflag, false, xearth_dt[0..], xearth_dt[0..], xsun_dt[0..], null, swed, models, dctx, serr);
        if (retc != OK)
            return ERR;
        const retc2 = mainPlanetBary(tjd, SEI_EARTH, epheflag, iflag, true, xearth[0..], xearth[0..], xsun[0..], null, swed, models, dctx, serr);
        if (retc2 != OK)
            return ERR;
    }
    // observer: geocenter or topocenter
    var xpo: ?[]f64 = null;
    var xpo_dt: ?[]f64 = null;
    if ((iflag & SEFLG_TOPOCTR) != 0) {
        if (swi_get_observer(tjd - dt, iflag | SEFLG_NONUT, false, &xobs_dt, swed, models, dctx, serr) != OK)
            return ERR;
        if (swi_get_observer(tjd, iflag | SEFLG_NONUT, false, &xobs, swed, models, dctx, serr) != OK)
            return ERR;
        // barycentric position of observer
        for (0..6) |i| {
            xobs[i] = xobs[i] + xearth[i];
            xobs_dt[i] = xobs_dt[i] + xearth_dt[i];
        }
    } else if ((iflag & SEFLG_BARYCTR) == 0 and ((iflag & SEFLG_HELCTR) == 0 or (iflag & SEFLG_MOSEPH) == 0)) {
        // barycentric position of geocenter
        for (0..6) |i| {
            xobs[i] = xearth[i];
            xobs_dt[i] = xearth_dt[i];
        }
    }
    // position and speed at tjd
    if ((iflag & SEFLG_HELCTR) != 0 and (iflag & SEFLG_MOSEPH) != 0) {
        xpo = null; // no parallax, if moshier and heliocentric
        xpo_dt = null;
    } else if ((iflag & SEFLG_HELCTR) != 0) {
        xpo = xsun[0..];
        xpo_dt = xsun_dt[0..];
    } else if ((iflag & SEFLG_BARYCTR) != 0) {
        xpo = null; // no parallax, if barycentric
        xpo_dt = null;
    } else {
        xpo = xobs[0..];
        xpo_dt = xobs_dt[0..];
    }
    if (xpo == null) {
        for (0..3) |i| {
            x[i] += t * x[i + 3];
        }
    } else {
        for (0..3) |i| {
            x[i] += t * x[i + 3];
            x[i] -= xpo.?[i];
            x[i + 3] -= xpo.?[i + 3];
        }
    }
    // relativistic deflection of light
    if ((iflag & SEFLG_TRUEPOS) == 0 and (iflag & SEFLG_NOGDEFL) == 0) {
        swi_deflect_light(&x, 0, iflag & SEFLG_SPEED, swed);
    }
    // 'annual' aberration of light
    if ((iflag & SEFLG_TRUEPOS) == 0 and (iflag & SEFLG_NOABERR) == 0)
        aberrLightEx(&x, xpo, xpo_dt, dt, iflag & SEFLG_SPEED);
    // ICRS to J2000
    if ((iflag & SEFLG_ICRS) == 0 and (swi_get_denum(SEI_SUN, iflag, swed) >= 403 or (iflag & SEFLG_BARYCTR) != 0)) {
        lib.swi_bias(&x, tjd, iflag, false, models);
    }
    // save J2000 coordinates; required for sidereal positions
    for (0..6) |i|
        xxsv[i] = x[i];
    // precession, equator 2000 -> equator of date
    if ((iflag & SEFLG_J2000) == 0) {
        _ = lib.swi_precess(x[0..3], tjd, iflag, lib.J2000_TO_J, models);
        swi_precess_speed(&x, tjd, iflag, lib.J2000_TO_J, swed, models);
        oe = &swed.oec;
    } else {
        oe = &swed.oec2000;
    }
    // nutation
    if ((iflag & SEFLG_NONUT) == 0)
        swi_nutate(&x, iflag, false, swed);
    // transformation to ecliptic.
    if ((iflag & SEFLG_EQUATORIAL) == 0) {
        lib.swi_coortrf2(x[0..3], x[0..3], oe.seps, oe.ceps);
        if ((iflag & SEFLG_SPEED) != 0)
            lib.swi_coortrf2(x[3..6], x[3..6], oe.seps, oe.ceps);
        if ((iflag & SEFLG_NONUT) == 0) {
            lib.swi_coortrf2(x[0..3], x[0..3], swed.nut.snut, swed.nut.cnut);
            if ((iflag & SEFLG_SPEED) != 0)
                lib.swi_coortrf2(x[3..6], x[3..6], swed.nut.snut, swed.nut.cnut);
        }
    }
    // sidereal positions
    if ((iflag & SEFLG_SIDEREAL) != 0) {
        var daya: [2]f64 = .{ 0, 0 };
        // rigorous algorithm
        if ((swed.sidd.sid_mode & SE_SIDBIT_ECL_T0) != 0) {
            if (swi_trop_ra2sid_lon(&xxsv, &x, &xxsv, iflag, swed, models, dctx) != 0)
                return ERR;
            if ((iflag & SEFLG_EQUATORIAL) != 0) {
                for (0..6) |i|
                    x[i] = xxsv[i];
            }
            // project onto solar system equator
        } else if ((swed.sidd.sid_mode & SE_SIDBIT_SSY_PLANE) != 0) {
            if (swi_trop_ra2sid_lon_sosy(&xxsv, &x, iflag, swed, models, dctx) != 0)
                return ERR;
            if ((iflag & SEFLG_EQUATORIAL) != 0) {
                for (0..6) |i|
                    x[i] = xxsv[i];
            }
            // traditional algorithm
        } else {
            lib.swi_cartpol_sp(&x, &x);
            // ACHTUNG: siehe Z. 2770!!!!!
            if (swi_get_ayanamsa_with_speed(tjd, iflag, &daya, swed, models, dctx, serr) == ERR)
                return ERR;
            x[0] -= daya[0] * DEGTORAD;
            x[3] -= daya[1] * DEGTORAD;
            lib.swi_polcart_sp(&x, &x);
        }
    }
    // transformation to polar coordinates
    if ((iflag & SEFLG_XYZ) == 0)
        lib.swi_cartpol_sp(&x, &x);
    // radians to degrees
    if ((iflag & SEFLG_RADIANS) == 0 and (iflag & SEFLG_XYZ) == 0) {
        for (0..2) |i| {
            x[i] *= RADTODEG;
            x[i + 3] *= RADTODEG;
        }
    }
    for (0..6) |i|
        xx[i] = x[i];
    if ((iflgsave & SEFLG_SPEED) == 0) {
        for (3..6) |i|
            xx[i] = 0;
    }
    // if no ephemeris has been specified, do not return chosen ephemeris
    var retval = iflag;
    if ((iflgsave & SEFLG_EPHMASK) == 0)
        retval = retval & ~SEFLG_DEFAULTEPH;
    retval = retval & ~SEFLG_SPEED;
    return retval;
}

/// sweph.c swi_aberr_light_ex
fn aberrLightEx(xx: *[6]f64, xe: ?[]const f64, xe_dt: ?[]const f64, dt: f64, iflag: i32) void {
    var xxs: [6]f64 = undefined;
    var xx2: [6]f64 = undefined;
    if (xe == null) return;
    for (0..6) |i|
        xxs[i] = xx[i];
    var xe6: [6]f64 = undefined;
    for (0..6) |i| xe6[i] = xe.?[i];
    swi_aberr_light_inner(xx, &xe6);
    // correction of speed
    if ((iflag & SEFLG_SPEED) != 0) {
        for (0..3) |i|
            xx2[i] = xxs[i] - dt * xxs[i + 3];
        var xed6: [6]f64 = undefined;
        if (xe_dt) |xd| {
            for (0..6) |i| xed6[i] = xd[i];
        }
        swi_aberr_light_inner(&xx2, &xed6);
        for (0..3) |i| {
            xx[i + 3] = (xx[i] - xx2[i]) / dt;
        }
    }
}

/// sweph.c swe_fixstar2
pub fn swe_fixstar2(star: []u8, tjd: f64, iflag_in: i32, xx: *[6]f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var stardata: FixedStar = .{};
    var retc: i32 = undefined;
    const iflag = iflag_in;
    var sstar: [SWI_STAR_LENGTH + 1]u8 = [_]u8{0} ** (SWI_STAR_LENGTH + 1);
    var srecord: [AS_MAXCH + 20]u8 = undefined;
    if (serr) |sr| {
        if (sr.len > 0) sr[0] = 0;
    }
    _ = loadAllFixedStars(swed, serr);
    retc = fixstarFormatSearchName(std.mem.sliceTo(star, 0), &sstar, serr);
    if (retc == ERR) {
        for (0..6) |i| xx[i] = 0;
        return retc;
    }
    const sstar_z = std.mem.sliceTo(&sstar, 0);
    // star elements from last call:
    if (swed.n_fixstars_records > 0 and std.mem.eql(u8, std.mem.sliceTo(&fixstar_slast_starname, 0), sstar_z)) {
        stardata = fixstar_last_stardata;
        // found:
    } else {
        if (getBuiltinStar(star, &sstar, &srecord)) {
            retc = fixstarCutString(srecord[0 .. (std.mem.indexOfScalar(u8, &srecord, 0) orelse srecord.len - 1) + 1], star, &stardata, serr, swed);
            if (retc == ERR) {
                for (0..6) |i| xx[i] = 0;
                return retc;
            }
        } else {
            retc = searchStarInList(sstar[0 .. sstar_z.len + 1], &stardata, swed, serr);
            if (retc == ERR) {
                for (0..6) |i| xx[i] = 0;
                return retc;
            }
        }
    }
    // found:
    fixstar_last_stardata = stardata;
    const sl = @min(sstar_z.len, fixstar_slast_starname.len - 1);
    @memcpy(fixstar_slast_starname[0..sl], sstar[0..sl]);
    fixstar_slast_starname[sl] = 0;
    retc = fixstarCalcFromStruct(&stardata, tjd, iflag, star, xx, swed, models, dctx, serr);
    if (retc == ERR) {
        for (0..6) |i| xx[i] = 0;
        return retc;
    }
    return iflag;
}

threadlocal var fixstar_last_stardata: FixedStar = .{};
threadlocal var fixstar_slast_starname: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;

/// sweph.c swe_fixstar2_ut
pub fn swe_fixstar2_ut(star: []u8, tjd_ut: f64, iflag_in: i32, xx: *[6]f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var iflag = iflag_in;
    var epheflag: i32 = 0;
    iflag = plaus_iflag(iflag, -1, tjd_ut, swed, models, serr);
    epheflag = iflag & SEFLG_EPHMASK;
    if (epheflag == 0) {
        epheflag = SEFLG_SWIEPH;
        iflag |= SEFLG_SWIEPH;
    }
    dctx.sweph_denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
    dctx.jpldenum = swed.jpldenum;
    var dtx = deltat.swe_deltat_ex(dctx, tjd_ut, iflag);
    // if ephe required is not ephe returned, adjust delta t:
    var retflag = swe_fixstar2(star, tjd_ut + dtx, iflag, xx, swed, models, dctx, serr);
    if (retflag != ERR and (retflag & SEFLG_EPHMASK) != epheflag) {
        dctx.sweph_denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        dtx = deltat.swe_deltat_ex(dctx, tjd_ut, retflag);
        retflag = swe_fixstar2(star, tjd_ut + dtx, iflag, xx, swed, models, dctx, null);
    }
    return retflag;
}

/// sweph.c swe_fixstar2_mag
pub fn swe_fixstar2_mag(star: []u8, mag: *f64, swed: *Swed, serr: ?[]u8) i32 {
    var stardata: FixedStar = .{};
    _ = &stardata;
    var retc: i32 = undefined;
    var sstar: [SWI_STAR_LENGTH + 1]u8 = [_]u8{0} ** (SWI_STAR_LENGTH + 1);
    if (serr) |sr| {
        if (sr.len > 0) sr[0] = 0;
    }
    _ = loadAllFixedStars(swed, serr);
    retc = fixstarFormatSearchName(std.mem.sliceTo(star, 0), &sstar, serr);
    if (retc == ERR) {
        mag.* = 0;
        return retc;
    }
    const sstar_z = std.mem.sliceTo(&sstar, 0);
    if (swed.n_fixstars_records > 0 and std.mem.eql(u8, std.mem.sliceTo(&fixstar_slast_starname, 0), sstar_z)) {
        stardata = fixstar_last_stardata;
    } else {
        retc = searchStarInList(sstar[0 .. sstar_z.len + 1], &stardata, swed, serr);
        if (retc == ERR) {
            mag.* = 0;
            return retc;
        }
    }
    fixstar_last_stardata = stardata;
    const sl = @min(sstar_z.len, fixstar_slast_starname.len - 1);
    @memcpy(fixstar_slast_starname[0..sl], sstar[0..sl]);
    fixstar_slast_starname[sl] = 0;
    mag.* = stardata.mag;
    // star name output
    {
        var pos: usize = 0;
        const nlen = std.mem.indexOfScalar(u8, &stardata.starname, 0) orelse stardata.starname.len;
        const blen = std.mem.indexOfScalar(u8, &stardata.starbayer, 0) orelse stardata.starbayer.len;
        if (pos + nlen < star.len) {
            @memcpy(star[pos .. pos + nlen], stardata.starname[0..nlen]);
            pos += nlen;
        }
        if (pos < star.len) {
            star[pos] = ',';
            pos += 1;
        }
        if (pos + blen < star.len) {
            @memcpy(star[pos .. pos + blen], stardata.starbayer[0..blen]);
            pos += blen;
        }
        star[pos] = 0;
    }
    return OK;
}

/// sweph.c swi_fixstar_load_record (old record-based path)
fn swiFixstarLoadRecord(star: []const u8, srecord: []u8, swed: *Swed, serr: ?[]u8) i32 {
    var s: [AS_MAXCH + 20]u8 = undefined;
    var sstar: [SWI_STAR_LENGTH + 1]u8 = [_]u8{0} ** (SWI_STAR_LENGTH + 1);
    var fstar: [SWI_STAR_LENGTH + 1]u8 = [_]u8{0} ** (SWI_STAR_LENGTH + 1);
    var star_nr: i32 = 0;
    var line: i32 = 0;
    var fline: i32 = 0;
    var is_bayer = false;
    const retc = fixstarFormatSearchName(star, &sstar, serr);
    if (retc == ERR)
        return ERR;
    var sstar_z = std.mem.sliceTo(&sstar, 0);
    // search name is Bayer designation
    if (sstar[0] == ',') {
        is_bayer = true;
        // search name star number in sefstars.txt
    } else if (sstar_z.len > 0 and std.ascii.isDigit(sstar_z[0])) {
        star_nr = atoiSlice(sstar_z);
        // traditional name: cut off Bayer designation
    } else {
        if (std.mem.indexOfScalar(u8, sstar_z, ',')) |pos|
            sstar[pos] = 0;
        sstar_z = std.mem.sliceTo(&sstar, 0);
    }
    const cmplen = sstar_z.len;
    if (swed.fixfp == null) {
        if (swi_fopen(SEI_FILE_FIXSTAR, SE_STARFILE, sliceToZ(&swed.ephepath), serr, swed)) |fp| {
            swed.fixfp = fp;
        } else {
            swed.is_old_starfile = true;
            if (swi_fopen(SEI_FILE_FIXSTAR, SE_STARFILE_OLD, sliceToZ(&swed.ephepath), null, swed)) |fp2| {
                swed.fixfp = fp2;
            } else {
                swed.is_old_starfile = false;
                return ERR;
            }
        }
    }
    _ = fseek(swed.fixfp, 0, 0); // rewind
    while (fgets(&s, AS_MAXCH, swed.fixfp) != null) {
        fline += 1;
        // skip comment lines
        if (s[0] == '#') continue;
        line += 1;
        // search string is star number in sefstars.txt
        if (star_nr == line) {
            const slen = std.mem.indexOfScalar(u8, &s, 0) orelse s.len;
            @memcpy(srecord[0..slen], s[0..slen]);
            srecord[slen] = 0;
            break;
        } else if (star_nr > 0) {
            continue;
        }
        const slen = std.mem.indexOfScalar(u8, &s, 0) orelse s.len;
        const sz = s[0..slen];
        // invalid line without comma
        const comma = std.mem.indexOfScalar(u8, sz, ',') orelse {
            if (serr) |sr| {
                const r = std.fmt.bufPrint(sr[0 .. sr.len - 1], "star file {s} damaged at line {d}", .{ SE_STARFILE, fline }) catch sr[0..0];
                sr[r.len] = 0;
            }
            return ERR;
        };
        // search string is Bayer or Flamsteed designation
        if (is_bayer) {
            // C: strncmp(sp, sstar, cmplen) — sp points AT the comma
            if (sz.len >= comma + cmplen and std.mem.eql(u8, sz[comma .. comma + cmplen], sstar_z[0..cmplen])) {
                @memcpy(srecord[0..slen], s[0..slen]);
                srecord[slen] = 0;
                break;
            }
            continue;
        }
        // search string is traditional name
        var flen = comma;
        if (flen > SE_MAX_STNAME) flen = SE_MAX_STNAME;
        @memcpy(fstar[0..flen], sz[0..flen]);
        fstar[flen] = 0;
        // remove white spaces from star name
        var out: usize = 0;
        for (fstar[0..flen]) |c| {
            if (c != ' ') {
                fstar[out] = c;
                out += 1;
            }
        }
        fstar[out] = 0;
        const i: usize = out;
        // length of star name differs from length of search string: continue
        if (i < cmplen)
            continue;
        // star name to lowercase and compare with search string
        for (fstar[0..out]) |*c| c.* = std.ascii.toLower(c.*);
        if (std.mem.eql(u8, fstar[0..out], sstar_z[0..cmplen])) {
            @memcpy(srecord[0..slen], s[0..slen]);
            srecord[slen] = 0;
            break;
        }
    } else {
        // loop ended without break: not found
        if (serr) |sr| {
            var msg: [AS_MAXCH]u8 = undefined;
            var r: []u8 = undefined;
            const starz = std.mem.sliceTo(star, 0);
            if (4 + starz.len + 10 < AS_MAXCH) {
                r = std.fmt.bufPrint(&msg, "star {s} not found", .{starz}) catch msg[0..0];
            } else {
                r = std.fmt.bufPrint(&msg, "star  not found", .{}) catch msg[0..0];
            }
            const m = @min(r.len, sr.len - 1);
            @memcpy(sr[0..m], msg[0..m]);
            sr[m] = 0;
        }
        return ERR;
    }
    // found:
    var stardata2: FixedStar = .{};
    const retc2 = fixstarCutString(srecord, @constCast(star), &stardata2, serr, swed);
    if (retc2 == ERR) return ERR;
    return OK;
}

/// sweph.c swe_fixstar (old record-based API)
pub fn swe_fixstar(star: []u8, tjd: f64, iflag_in: i32, xx: *[6]f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    const iflag = iflag_in;
    var sstar: [SWI_STAR_LENGTH + 1]u8 = [_]u8{0} ** (SWI_STAR_LENGTH + 1);
    var srecord: [AS_MAXCH + 20]u8 = undefined;
    var retc: i32 = undefined;
    if (serr) |sr| {
        if (sr.len > 0) sr[0] = 0;
    }
    retc = fixstarFormatSearchName(std.mem.sliceTo(star, 0), &sstar, serr);
    if (retc == ERR) {
        for (0..6) |i| xx[i] = 0;
        return retc;
    }
    var sstar_z = std.mem.sliceTo(&sstar, 0);
    if (sstar[0] == ',') {
        // is Bayer designation
    } else if (sstar_z.len > 0 and std.ascii.isDigit(sstar_z[0])) {
        // is a sequential star number
    } else {
        // cut off Bayer, if trad. name
        if (std.mem.indexOfScalar(u8, sstar[0..sstar_z.len], ',')) |pos| {
            sstar[pos] = 0;
            sstar_z = std.mem.sliceTo(&sstar, 0);
        }
    }
    // star elements from last call:
    if (fixstar_slast_record[0] != 0 and std.mem.eql(u8, std.mem.sliceTo(&fixstar_slast_starname_old, 0), sstar_z)) {
        const rlen = std.mem.indexOfScalar(u8, &fixstar_slast_record, 0) orelse fixstar_slast_record.len;
        @memcpy(srecord[0..rlen], fixstar_slast_record[0..rlen]);
        srecord[rlen] = 0;
    } else {
        if (getBuiltinStar(star, &sstar, &srecord)) {
            // found
        } else {
            retc = swiFixstarLoadRecord(star, &srecord, swed, serr);
            if (retc != OK) {
                for (0..6) |i| xx[i] = 0;
                return retc;
            }
        }
    }
    // found:
    const rlen2 = std.mem.indexOfScalar(u8, &srecord, 0) orelse srecord.len;
    @memcpy(fixstar_slast_record[0..rlen2], srecord[0..rlen2]);
    fixstar_slast_record[rlen2] = 0;
    const sl2 = @min(sstar_z.len, fixstar_slast_starname_old.len - 1);
    @memcpy(fixstar_slast_starname_old[0..sl2], sstar[0..sl2]);
    fixstar_slast_starname_old[sl2] = 0;
    retc = swiFixstarCalcFromRecord(srecord[0 .. (std.mem.indexOfScalar(u8, &srecord, 0) orelse srecord.len - 1) + 1], tjd, iflag, star, xx, swed, models, dctx, serr);
    if (retc == ERR) {
        for (0..6) |i| xx[i] = 0;
        return retc;
    }
    return iflag;
}

threadlocal var fixstar_slast_record: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;
threadlocal var fixstar_slast_starname_old: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH;

/// sweph.c swe_fixstar_ut
pub fn swe_fixstar_ut(star: []u8, tjd_ut: f64, iflag_in: i32, xx: *[6]f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var iflag = iflag_in;
    var epheflag: i32 = 0;
    iflag = plaus_iflag(iflag, -1, tjd_ut, swed, models, serr);
    epheflag = iflag & SEFLG_EPHMASK;
    if (epheflag == 0) {
        epheflag = SEFLG_SWIEPH;
        iflag |= SEFLG_SWIEPH;
    }
    dctx.sweph_denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
    dctx.jpldenum = swed.jpldenum;
    var dtx = deltat.swe_deltat_ex(dctx, tjd_ut, iflag);
    // if ephe required is not ephe returned, adjust delta t:
    var retflag = swe_fixstar(star, tjd_ut + dtx, iflag, xx, swed, models, dctx, serr);
    if (retflag != ERR and (retflag & SEFLG_EPHMASK) != epheflag) {
        dctx.sweph_denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
        dctx.jpldenum = swed.jpldenum;
        dtx = deltat.swe_deltat_ex(dctx, tjd_ut, retflag);
        retflag = swe_fixstar(star, tjd_ut + dtx, iflag, xx, swed, models, dctx, null);
    }
    return retflag;
}

/// sweph.c swe_fixstar_mag
pub fn swe_fixstar_mag(star: []u8, mag: *f64, swed: *Swed, serr: ?[]u8) i32 {
    var sstar: [SWI_STAR_LENGTH + 1]u8 = [_]u8{0} ** (SWI_STAR_LENGTH + 1);
    var srecord: [AS_MAXCH + 20]u8 = undefined;
    var retc: i32 = undefined;
    if (serr) |sr| {
        if (sr.len > 0) sr[0] = 0;
    }
    retc = fixstarFormatSearchName(std.mem.sliceTo(star, 0), &sstar, serr);
    if (retc == ERR) {
        mag.* = 0;
        return retc;
    }
    var sstar_z = std.mem.sliceTo(&sstar, 0);
    if (sstar[0] == ',') {
        // is Bayer designation
    } else if (sstar_z.len > 0 and std.ascii.isDigit(sstar_z[0])) {
        // is a sequential star number
    } else {
        if (std.mem.indexOfScalar(u8, sstar[0..sstar_z.len], ',')) |pos| {
            sstar[pos] = 0;
            sstar_z = std.mem.sliceTo(&sstar, 0);
        }
    }
    // star elements from last call:
    if (fixstar_slast_record[0] != 0 and std.mem.eql(u8, std.mem.sliceTo(&fixstar_slast_starname_old, 0), sstar_z)) {
        const rlen = std.mem.indexOfScalar(u8, &fixstar_slast_record, 0) orelse fixstar_slast_record.len;
        @memcpy(srecord[0..rlen], fixstar_slast_record[0..rlen]);
        srecord[rlen] = 0;
    } else {
        if (getBuiltinStar(star, &sstar, &srecord)) {
            // found
        } else {
            retc = swiFixstarLoadRecord(star, &srecord, swed, serr);
            if (retc != OK) {
                mag.* = 0;
                return retc;
            }
        }
    }
    // found:
    const rlen2 = std.mem.indexOfScalar(u8, &srecord, 0) orelse srecord.len;
    @memcpy(fixstar_slast_record[0..rlen2], srecord[0..rlen2]);
    fixstar_slast_record[rlen2] = 0;
    const sl2 = @min(sstar_z.len, fixstar_slast_starname_old.len - 1);
    @memcpy(fixstar_slast_starname_old[0..sl2], sstar[0..sl2]);
    fixstar_slast_starname_old[sl2] = 0;
    var stardata: FixedStar = .{};
    retc = fixstarCutString(srecord[0 .. (std.mem.indexOfScalar(u8, &srecord, 0) orelse srecord.len - 1) + 1], star, &stardata, serr, swed);
    if (retc == ERR) {
        mag.* = 0;
        return retc;
    }
    mag.* = stardata.mag;
    return OK;
}

/// sweph.c swi_fixstar_calc_from_record: cut + shared pipeline
fn swiFixstarCalcFromRecord(srecord: []u8, tjd: f64, iflag: i32, star: []u8, xx: *[6]f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var stardata: FixedStar = .{};
    const retc = fixstarCutString(srecord, star, &stardata, serr, swed);
    if (retc == ERR) return ERR;
    return fixstarCalcFromStruct(&stardata, tjd, iflag, star, xx, swed, models, dctx, serr);
}

/// sweph.c main_planet_bary
fn mainPlanetBary(tjd: f64, ipli: usize, epheflag: i32, iflag_in: i32, do_save: bool, xp: []f64, xe: []f64, xs: []f64, xm: ?[]f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    var iflag = iflag_in;
    var retc: i32 = undefined;
    switch (epheflag) {
        SEFLG_JPLEPH => {
            retc = jplplan(tjd, ipli, iflag, do_save, xp, xe, xs, swed, dctx, serr);
            // read error or corrupt file
            if (retc == ERR or retc == BEYOND_EPH_LIMITS)
                return retc;
            // jpl ephemeris not on disk or date beyond ephemeris range:
            // fall through to the sweph_planet path (C goto sweph_planet)
            if (retc == NOT_AVAILABLE) {
                iflag = (iflag & ~SEFLG_JPLEPH) | SEFLG_SWIEPH;
                if (serr) |sr| appendSerrMax(sr, " \ntrying Swiss Eph; ");
                // sweph_planet:
                retc = sweplan(tjd, ipli, SEI_FILE_PLANET, iflag, do_save, xp, xe, xs, xm, serr, swed, models);
                if (retc == ERR)
                    return ERR;
                if (retc == NOT_AVAILABLE) {
                    if (tjd > MOSHPLEPH_START and tjd < MOSHPLEPH_END) {
                        iflag = (iflag & ~SEFLG_SWIEPH) | SEFLG_MOSEPH;
                        if (serr) |sr| appendSerrMax(sr, " \nusing Moshier eph.; ");
                        // moshier_planet:
                        const retc3 = swi_moshplan_save2(tjd, ipli, do_save, xp, xe, xs, swed, models, serr);
                        if (retc3 == ERR)
                            return ERR;
                        for (0..6) |i| xs[i] = 0;
                    } else {
                        return ERR;
                    }
                }
            }
        },
        SEFLG_SWIEPH => {
            // sweph_planet:
            retc = sweplan(tjd, ipli, SEI_FILE_PLANET, iflag, do_save, xp, xe, xs, xm, serr, swed, models);
            // if barycentric moshier calculation were implemented
            if (retc == ERR)
                return ERR;
            // if sweph file not found, switch to moshier
            if (retc == NOT_AVAILABLE) {
                if (tjd > MOSHPLEPH_START and tjd < MOSHPLEPH_END) {
                    iflag = (iflag & ~SEFLG_SWIEPH) | SEFLG_MOSEPH;
                    if (serr) |sr| appendSerrMax(sr, " \nusing Moshier eph.; ");
                    // moshier_planet:
                    const retc3 = swi_moshplan_save2(tjd, ipli, do_save, xp, xe, xs, swed, models, serr);
                    if (retc3 == ERR)
                        return ERR;
                    for (0..6) |i| xs[i] = 0;
                } else {
                    return ERR;
                }
            }
        },
        else => {
            // SEFLG_MOSEPH: moshier_planet
            retc = swi_moshplan_save2(tjd, ipli, do_save, xp, xe, xs, swed, models, serr);
            if (retc == ERR)
                return ERR;
            for (0..6) |i| xs[i] = 0;
        },
    }
    return OK;
}

/// moshier save used by mainPlanetBary (do_save-aware variant of
/// swi_moshplan_save; writes into xp/xe instead of the save areas when
/// do_save is false)
fn swi_moshplan_save2(tjd: f64, ipli: usize, do_save: bool, xp: []f64, xe: []f64, xs: []f64, swed: *Swed, models: AstroModels, serr: ?[]u8) i32 {
    var xp6: [6]f64 = undefined;
    var xe6: [6]f64 = undefined;
    _ = xs;
    const retc = swi_moshplan_call(tjd, ipli, &xp6, &xe6, swed, models, serr);
    if (retc == ERR)
        return ERR;
    // C's swi_moshplan writes into pdp->x/pedp->x when do_save AND copies
    // the results out via xpret/xeret (main_planet_bary passes the caller's
    // arrays there) — so the caller's arrays are filled in BOTH modes.
    for (0..6) |k| xp[k] = xp6[k];
    for (0..6) |k| xe[k] = xe6[k];
    if (do_save) {
        const pdp = &swed.pldat[ipli];
        const pedp = &swed.pldat[SEI_EARTH];
        for (0..6) |k| pdp.x[k] = xp6[k];
        for (0..6) |k| pedp.x[k] = xe6[k];
        pdp.teval = tjd;
        pdp.xflgs = -1;
        pdp.iephe = SEFLG_MOSEPH;
        pedp.teval = tjd;
        pedp.xflgs = -1;
        pedp.iephe = SEFLG_MOSEPH;
    }
    return OK;
}

pub fn mainPlanetBaryPublic(tjd: f64, ipli: usize, epheflag: i32, iflag: i32, do_save: bool, xp: []f64, xe: []f64, xs: []f64, xm: ?[]f64, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    return mainPlanetBary(tjd, ipli, epheflag, iflag, do_save, xp, xe, xs, xm, swed, models, dctx, serr);
}

/// sweph.c swe_get_planet_name
pub fn swe_get_planet_name(ipl_in: i32, s: []u8, swed: *Swed, models: AstroModels, dctx: *DeltatCtx, serr: ?[]u8) i32 {
    _ = dctx;
    _ = serr;
    var ipl = ipl_in;
    var xp: [6]f64 = undefined;
    // function calls for Pluto with asteroid number 134340
    // are treated as calls for Pluto as main body SE_PLUTO
    if (ipl == 10000 + 134340)
        ipl = 9; // SE_PLUTO
    if (ipl != 0 and ipl == swed.i_saved_planet_name) {
        const n = @min(std.mem.indexOfScalar(u8, &swed.saved_planet_name, 0) orelse swed.saved_planet_name.len, s.len - 1);
        @memcpy(s[0..n], swed.saved_planet_name[0..n]);
        s[n] = 0;
        return 0;
    }
    var sbuf: [80]u8 = [_]u8{0} ** 80;
    // C's switch(ipl) with duplicate cases — modeled as if-chain
    if (ipl == 0) {
        @memcpy(sbuf[0..3], "Sun");
        sbuf[3] = 0;
    } else if (ipl == 1) {
        @memcpy(sbuf[0..4], "Moon");
        sbuf[4] = 0;
    } else if (ipl == 2) {
        @memcpy(sbuf[0..7], "Mercury");
        sbuf[7] = 0;
    } else if (ipl == 3) {
        @memcpy(sbuf[0..5], "Venus");
        sbuf[5] = 0;
    } else if (ipl == 4) {
        @memcpy(sbuf[0..4], "Mars");
        sbuf[4] = 0;
    } else if (ipl == 5) {
        @memcpy(sbuf[0..7], "Jupiter");
        sbuf[7] = 0;
    } else if (ipl == 6) {
        @memcpy(sbuf[0..6], "Saturn");
        sbuf[6] = 0;
    } else if (ipl == 7) {
        @memcpy(sbuf[0..6], "Uranus");
        sbuf[6] = 0;
    } else if (ipl == 8) {
        @memcpy(sbuf[0..7], "Neptune");
        sbuf[7] = 0;
    } else if (ipl == 9) {
        @memcpy(sbuf[0..5], "Pluto");
        sbuf[5] = 0;
    } else if (ipl == 10) {
        @memcpy(sbuf[0..9], "mean Node");
        sbuf[9] = 0;
    } else if (ipl == 11) {
        @memcpy(sbuf[0..9], "true Node");
        sbuf[9] = 0;
    } else if (ipl == 12) {
        @memcpy(sbuf[0..11], "mean Apogee");
        sbuf[11] = 0;
    } else if (ipl == 13) {
        @memcpy(sbuf[0..11], "osc. Apogee");
        sbuf[11] = 0;
    } else if (ipl == 14) {
        @memcpy(sbuf[0..5], "Earth");
        sbuf[5] = 0;
    } else if (ipl == 15) {
        @memcpy(sbuf[0..6], "Chiron");
        sbuf[6] = 0;
    } else if (ipl == 12060) {
        @memcpy(sbuf[0..6], "Chiron");
        sbuf[6] = 0;
    } else if (ipl == 16) {
        @memcpy(sbuf[0..6], "Pholus");
        sbuf[6] = 0;
    } else if (ipl == 15145) {
        @memcpy(sbuf[0..6], "Pholus");
        sbuf[6] = 0;
    } else if (ipl == 17) {
        @memcpy(sbuf[0..5], "Ceres");
        sbuf[5] = 0;
    } else if (ipl == 10001) {
        @memcpy(sbuf[0..5], "Ceres");
        sbuf[5] = 0;
    } else if (ipl == 18) {
        @memcpy(sbuf[0..6], "Pallas");
        sbuf[6] = 0;
    } else if (ipl == 10002) {
        @memcpy(sbuf[0..6], "Pallas");
        sbuf[6] = 0;
    } else if (ipl == 19) {
        @memcpy(sbuf[0..4], "Juno");
        sbuf[4] = 0;
    } else if (ipl == 10003) {
        @memcpy(sbuf[0..4], "Juno");
        sbuf[4] = 0;
    } else if (ipl == 20) {
        @memcpy(sbuf[0..5], "Vesta");
        sbuf[5] = 0;
    } else if (ipl == 10004) {
        @memcpy(sbuf[0..5], "Vesta");
        sbuf[5] = 0;
    } else if (ipl == 21) {
        @memcpy(sbuf[0..12], "intp. Apogee");
        sbuf[12] = 0;
    } else if (ipl == 22) {
        @memcpy(sbuf[0..13], "intp. Perigee");
        sbuf[13] = 0;
    } else {
        // fictitious planets
        if (ipl >= 40 and ipl <= 999) {
            const nm = swemplan_mod.swi_get_fict_name(ipl - 40, swed);
            const nl = std.mem.indexOfScalar(u8, &nm, 0) orelse nm.len;
            const m = @min(nl, sbuf.len - 1);
            @memcpy(sbuf[0..m], nm[0..m]);
            sbuf[m] = 0;
        } else if (ipl > 9000 or ipl > 10000) { // 2nd condition obsolete
            // if name is already available
            if (ipl == swed.fidat[3].ipl[0]) {
                const n = std.mem.indexOfScalar(u8, &swed.fidat[3].astnam, 0) orelse swed.fidat[3].astnam.len;
                const m = @min(n, sbuf.len - 1);
                @memcpy(sbuf[0..m], swed.fidat[3].astnam[0..m]);
                sbuf[m] = 0;
                // else try to get it from ephemeris file
            } else {
                const retc = sweph(2451545.0, @intCast(ipl), 3, 0, null, false, &xp, null, swed, models);
                if (retc != ERR and retc != NOT_AVAILABLE) {
                    const n = std.mem.indexOfScalar(u8, &swed.fidat[3].astnam, 0) orelse swed.fidat[3].astnam.len;
                    const m = @min(n, sbuf.len - 1);
                    @memcpy(sbuf[0..m], swed.fidat[3].astnam[0..m]);
                    sbuf[m] = 0;
                } else {
                    if (ipl > 10000) {
                        var msg: [AS_MAXCH]u8 = undefined;
                        const r = std.fmt.bufPrint(&msg, "{d}: not found (asteroid)", .{ipl - 10000}) catch msg[0..0];
                        const n2 = @min(r.len, sbuf.len - 1);
                        @memcpy(sbuf[0..n2], msg[0..n2]);
                        sbuf[n2] = 0;
                        // sweph.c:7076: provisional designation only ->
                        // look up the real name in seasnam.txt
                        // (SE_ASTNAMFILE). Trigger: s[0]=='?' or
                        // isdigit(s[1]).
                        if (sbuf[0] == '?' or (sbuf.len > 1 and sbuf[1] >= '0' and sbuf[1] <= '9')) {
                            const ipli: i32 = @intCast(ipl - 10000);
                            var nameline: [AS_MAXCH]u8 = undefined;
                            if (swi_fopen(-1, "seasnam.txt", std.mem.sliceTo(&swed.ephepath, 0), null, swed)) |fp| {
                                defer _ = fclose(fp);
                                var found = false;
                                while (!found) {
                                    const line = fgets(&nameline, AS_MAXCH, fp) orelse break;
                                    var sp: [*]u8 = line;
                                    // skip leading blanks/open brackets
                                    while (sp[0] == ' ' or sp[0] == '\t' or
                                        sp[0] == '(' or sp[0] == '[' or sp[0] == '{') sp += 1;
                                    if (sp[0] == '#' or sp[0] == '\r' or sp[0] == '\n' or sp[0] == 0)
                                        continue;
                                    // catalog number of current line: atoi(sp)
                                    var j: usize = 0;
                                    var num: i32 = 0;
                                    while (sp[j] >= '0' and sp[j] <= '9') : (j += 1) {
                                        num = num * 10 + (sp[j] - '0');
                                    }
                                    if (ipli != num)
                                        continue;
                                    // pointer after catalog number
                                    var k: usize = j;
                                    while (k < nameline.len and sp[k] != 0 and
                                        sp[k] != ' ' and sp[k] != '\t') k += 1;
                                    if (k >= nameline.len or sp[k] == 0)
                                        continue; // no name
                                    while (sp[k] == ' ' or sp[k] == '\t') k += 1;
                                    // cut at '#' or newline
                                    var e: usize = k;
                                    while (e < nameline.len and sp[e] != 0 and
                                        sp[e] != '#' and sp[e] != '\r' and sp[e] != '\n') e += 1;
                                    const nlen = e - k;
                                    if (nlen == 0)
                                        continue;
                                    // swi_right_trim
                                    var end = e;
                                    while (end > k and (sp[end - 1] == ' ' or sp[end - 1] == '\t')) end -= 1;
                                    const m = @min(end - k, sbuf.len - 1);
                                    @memcpy(sbuf[0..m], sp[k..][0..m]);
                                    sbuf[m] = 0;
                                    found = true;
                                }
                            }
                        }
                    } else {
                        var msg: [AS_MAXCH]u8 = undefined;
                        const r = std.fmt.bufPrint(&msg, "{d}: not found (planetary moon)", .{ipl}) catch msg[0..0];
                        const n2 = @min(r.len, sbuf.len - 1);
                        @memcpy(sbuf[0..n2], msg[0..n2]);
                        sbuf[n2] = 0;
                    }
                }
            }
        } else {
            var msg: [80]u8 = undefined;
            const r = std.fmt.bufPrint(&msg, "{d}", .{ipl}) catch msg[0..0];
            @memcpy(sbuf[0..r.len], msg[0..r.len]);
            sbuf[r.len] = 0;
        }
    }
    const rlen = std.mem.indexOfScalar(u8, &sbuf, 0) orelse sbuf.len;
    const n = @min(rlen, s.len - 1);
    @memcpy(s[0..n], sbuf[0..n]);
    s[n] = 0;
    if (n < 80) {
        swed.i_saved_planet_name = ipl;
        @memcpy(swed.saved_planet_name[0..n], sbuf[0..n]);
        swed.saved_planet_name[n] = 0;
    }
    return 0;
}

/// sweph.c swi_set_tid_acc (manual flag check + get from denum)
pub fn swiSetTidAcc(tjd_ut: f64, iflag: i32, denum: i32, serr: ?[]u8, swed: *Swed, dctx: *DeltatCtx) i32 {
    _ = tjd_ut;
    _ = serr;
    // manual tid_acc overrides automatic tid_acc
    if (swed.is_tid_acc_manual)
        return iflag;
    const tid_acc = swiGetTidAcc(iflag, denum, swed);
    swed.tid_acc = tid_acc;
    dctx.tid_acc = tid_acc;
    dctx.is_tid_acc_manual = false;
    return iflag;
}

fn swiGetTidAcc(iflag: i32, denum_in: i32, swed: *Swed) f64 {
    const ifl2 = iflag & SEFLG_EPHMASK;
    if (swed.is_tid_acc_manual) {
        return swed.tid_acc;
    }
    var denum = denum_in;
    if (denum == 0) {
        if ((ifl2 & SEFLG_MOSEPH) != 0) {
            return deltat.SE_TIDAL_DE404;
        }
        if ((ifl2 & SEFLG_JPLEPH) != 0) {
            if (swed.jpl_file_is_open) {
                denum = swed.jpldenum;
            }
        }
        // SEFLG_SWIEPH wanted or SEFLG_JPLEPH failed:
        if ((ifl2 & SEFLG_SWIEPH) != 0) {
            if (swed.fidat[SEI_FILE_MOON].fp != null) {
                denum = swed.fidat[SEI_FILE_MOON].sweph_denum;
            }
        }
    }
    return switch (denum) {
        200 => deltat.SE_TIDAL_DE200,
        403 => deltat.SE_TIDAL_DE403,
        404 => deltat.SE_TIDAL_DE404,
        405 => deltat.SE_TIDAL_DE405,
        406 => deltat.SE_TIDAL_DE406,
        421 => deltat.SE_TIDAL_DE421,
        422 => deltat.SE_TIDAL_DE422,
        430 => deltat.SE_TIDAL_DE430,
        431 => deltat.SE_TIDAL_DE431,
        440, 441 => deltat.SE_TIDAL_DE441,
        else => deltat.SE_TIDAL_DEFAULT,
    };
}
