//! swisseph — public API facade for the Zig port of Swiss Ephemeris.
//!
//! Import this module as the root entry point:
//! ```zig
//! const swe = @import("swisseph");
//! ```
//!
//! SPDX-License-Identifier: AGPL-3.0-or-later
//! Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris

const std = @import("std");

// Subsystems (re-export the named modules' public API)
pub const swedate = @import("swedate");
pub const deltat = @import("deltat");
pub const swephlib = @import("swephlib");
pub const swemmoon = @import("swemmoon");
pub const swemplan = @import("swemplan");
pub const swejpl = @import("swejpl");
pub const sweph = @import("sweph");
pub const swecl = @import("swecl");
pub const swehouse = @import("swehouse");
pub const swehel = @import("swehel");

// Most-used functions surfaced at the root for convenience
pub const julday = swedate.swe_julday;
pub const revjul = swedate.swe_revjul;
pub const date_conversion = swedate.swe_date_conversion;
pub const utc_time_zone = swedate.swe_utc_time_zone;

pub const deltat_ex = deltat.swe_deltat_ex;

pub const calc = sweph.swe_calc;
pub const calc_ut = sweph.swe_calc_ut;
pub const set_ephe_path = sweph.swe_set_ephe_path;
pub const set_jpl_file = sweph.swe_set_jpl_file;
pub const set_topo = sweph.swe_set_topo;
pub const set_sid_mode = sweph.swe_set_sid_mode;
pub const close = sweph.swe_close; // close(swed)
pub const fixstar = sweph.swe_fixstar;
pub const fixstar_ut = sweph.swe_fixstar_ut;
pub const fixstar_mag = sweph.swe_fixstar_mag;
pub const get_planet_name = sweph.swe_get_planet_name;
pub const get_ayanamsa_ex = sweph.swe_get_ayanamsa_ex;
pub const get_ayanamsa_ex_ut = sweph.swe_get_ayanamsa_ex_ut;

pub const houses_armc = swehouse.swe_houses_armc;
pub const houses_armc_ex2 = swehouse.swe_houses_armc_ex2;
pub const house_pos = swehouse.swe_house_pos;
pub const house_name = swehouse.swe_house_name;
pub const cotrans = swehouse.swe_cotrans;

pub const sol_eclipse_where = swecl.swe_sol_eclipse_where;
pub const sol_eclipse_how = swecl.swe_sol_eclipse_how;
pub const sol_eclipse_when_glob = swecl.swe_sol_eclipse_when_glob;
pub const sol_eclipse_when_loc = swecl.swe_sol_eclipse_when_loc;
pub const lun_eclipse_how = swecl.swe_lun_eclipse_how;
pub const lun_eclipse_when = swecl.swe_lun_eclipse_when;
pub const lun_eclipse_when_loc = swecl.swe_lun_eclipse_when_loc;
pub const lun_occult_where = swecl.swe_lun_occult_where;
pub const lun_occult_when_glob = swecl.swe_lun_occult_when_glob;
pub const lun_occult_when_loc = swecl.swe_lun_occult_when_loc;
pub const pheno = swecl.swe_pheno;
pub const pheno_ut = swecl.swe_pheno_ut;
pub const refrac = swecl.swe_refrac;
pub const refrac_extended = swecl.swe_refrac_extended;
pub const azalt = swecl.swe_azalt;
pub const azalt_rev = swecl.swe_azalt_rev;
pub const rise_trans = swecl.swe_rise_trans;
pub const rise_trans_true_hor = swecl.swe_rise_trans_true_hor;
pub const nod_aps = swecl.swe_nod_aps;
pub const nod_aps_ut = swecl.swe_nod_aps_ut;
pub const get_orbital_elements = swecl.swe_get_orbital_elements;
pub const orbit_max_min_true_distance = swecl.swe_orbit_max_min_true_distance;
pub const gauquelin_sector = swecl.swe_gauquelin_sector;

pub const heliacal_ut = swehel.swe_heliacal_ut;
pub const heliacal_pheno_ut = swehel.swe_heliacal_pheno_ut;
pub const vis_limit_mag = swehel.swe_vis_limit_mag;
pub const heliacal_angle = swehel.swe_heliacal_angle;
pub const topo_arcus_visionis = swehel.swe_topo_arcus_visionis;
