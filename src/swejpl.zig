// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
// Port of swejpl.c: JPL binary ephemeris file I/O and interpolation.
// C statics live in JplCtx (held by Swed.jpl), per instance like C.
const std = @import("std");
const lib = @import("swephlib");
const sweph = @import("sweph");

// JPL body indices (swejpl.h)
pub const J_MERCURY: i32 = 0;
pub const J_VENUS: i32 = 1;
pub const J_EARTH: i32 = 2;
pub const J_MARS: i32 = 3;
pub const J_JUPITER: i32 = 4;
pub const J_SATURN: i32 = 5;
pub const J_URANUS: i32 = 6;
pub const J_NEPTUNE: i32 = 7;
pub const J_PLUTO: i32 = 8;
pub const J_MOON: i32 = 9;
pub const J_SUN: i32 = 10;
pub const J_SBARY: i32 = 11;
pub const J_EMB: i32 = 12;
pub const J_NUT: i32 = 13;
pub const J_LIB: i32 = 14;

const NOT_AVAILABLE: i32 = lib.NOT_AVAILABLE;
const ERR: i32 = lib.ERR;
const OK: i32 = lib.OK;
const AS_MAXCH: usize = sweph.AS_MAXCH;
const BEYOND_EPH_LIMITS: i32 = lib.BEYOND_EPH_LIMITS;

/// struct jpl_save (swejpl.c)
const JplSave = struct {
    jplfname: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH,
    jplfpath: [AS_MAXCH]u8 = [_]u8{0} ** AS_MAXCH,
    jplfptr: ?*anyopaque = null,
    do_reorder: bool = false,
    eh_cval: [400]f64 = [_]f64{0} ** 400,
    eh_ss: [3]f64 = [_]f64{0} ** 3,
    eh_au: f64 = 0,
    eh_emrat: f64 = 0,
    eh_denum: i32 = 0,
    eh_ncon: i32 = 0,
    eh_ipt: [39]i32 = [_]i32{0} ** 39,
    ch_cnam: [6 * 400]u8 = [_]u8{0} ** (6 * 400),
    pv: [78]f64 = [_]f64{0} ** 78,
    pvsun: [6]f64 = [_]f64{0} ** 6,
    buf: [1500]f64 = [_]f64{0} ** 1500,
    pc: [18]f64 = [_]f64{0} ** 18,
    vc: [18]f64 = [_]f64{0} ** 18,
    ac: [18]f64 = [_]f64{0} ** 18,
    jc: [18]f64 = [_]f64{0} ** 18,
    do_km: bool = false,
};

/// Per-instance JPL ephemeris context: swi_open/close state (js) plus the
/// interp()/state() locals of swejpl.c live
/// in Swed so each instance owns its file handle and caches.
pub const JplCtx = struct {
    js: JplSave = .{},
    js_is_init: bool = false,
    // interp() function-local statics (TLS in C)
    np: i32 = 0,
    nv: i32 = 0,
    nac: i32 = 0,
    njk: i32 = 0,
    twot: f64 = 0.0,
    // state() function-local statics (TLS in C); lpt is transient and stays
    // a local, the others persist across calls exactly like the C statics.
    irecsz: i32 = 0,
    nrl: i32 = 0,
    ncoeffs: i32 = 0,
};

const vfs = @import("vfs");
const is_wasm = @import("builtin").target.cpu.arch.isWasm();
fn fread(ptr: [*]u8, size: usize, nitems: usize, stream: ?*anyopaque) usize {
    if (is_wasm) return vfs.fread(ptr, size, nitems, stream);
    const c = struct {
        extern "c" fn fread(ptr: [*]u8, size: usize, nitems: usize, stream: ?*anyopaque) usize;
    };
    return c.fread(ptr, size, nitems, stream);
}
fn fseek(stream: ?*anyopaque, off: i64, whence: i32) i32 {
    if (is_wasm) return vfs.fseek(stream, off, whence);
    const c = struct {
        extern "c" fn fseek(stream: ?*anyopaque, off: i64, whence: i32) i32;
    };
    return c.fseek(stream, off, whence);
}
fn ftell(stream: ?*anyopaque) i64 {
    if (is_wasm) return vfs.ftell(stream);
    const c = struct {
        extern "c" fn ftell(stream: ?*anyopaque) i64;
    };
    return c.ftell(stream);
}
fn fclose(stream: ?*anyopaque) i32 {
    if (is_wasm) return vfs.fclose(stream);
    const c = struct {
        extern "c" fn fclose(stream: ?*anyopaque) i32;
    };
    return c.fclose(stream);
}

fn freadDoubles(buf: []f64, stream: ?*anyopaque) usize {
    return fread(std.mem.sliceAsBytes(buf).ptr, 8, buf.len, stream);
}

fn sliceOf(buf: []const u8) []const u8 {
    return std.mem.sliceTo(buf, 0);
}

/// swejpl.c fsizer
fn fsizer(serr: ?[]u8, swed: *sweph.Swed) i32 {
    var ncon: i32 = 0;
    var emrat: f64 = 0;
    var numde: i32 = 0;
    var au: f64 = 0;
    var ss: [3]f64 = .{ 0, 0, 0 };
    var lpt: [3]i32 = .{ 0, 0, 0 };
    var ttl: [6 * 14 * 3]u8 = undefined;
    if (sweph.swi_fopen(sweph.SEI_FILE_PLANET, sliceOf(&swed.jpl.js.jplfname), sliceOf(&swed.jpl.js.jplfpath), serr, swed)) |fp| {
        swed.jpl.js.jplfptr = fp;
    } else {
        return NOT_AVAILABLE;
    }
    // ttl = ephemeris title
    if (fread(&ttl, 1, 252, swed.jpl.js.jplfptr) != 252) return NOT_AVAILABLE;
    // cnam = names of constants
    if (fread(&swed.jpl.js.ch_cnam, 1, 6 * 400, swed.jpl.js.jplfptr) != 6 * 400) return NOT_AVAILABLE;
    // ss[0] = start epoch, ss[1] = end epoch, ss[2] = segment size in days
    if (freadDoubles(&ss, swed.jpl.js.jplfptr) != 3) return NOT_AVAILABLE;
    // reorder ?
    if (ss[2] < 1 or ss[2] > 200)
        swed.jpl.js.do_reorder = true
    else
        swed.jpl.js.do_reorder = false;
    for (0..3) |i|
        swed.jpl.js.eh_ss[i] = ss[i];
    if (swed.jpl.js.do_reorder)
        reorder(std.mem.asBytes(&swed.jpl.js.eh_ss), 3);
    // plausibility test of these constants
    if (swed.jpl.js.eh_ss[0] < -5583942 or swed.jpl.js.eh_ss[1] > 9025909 or swed.jpl.js.eh_ss[2] < 1 or swed.jpl.js.eh_ss[2] > 200) {
        if (serr) |sr| {
            const msg = "alleged ephemeris file has invalid format.";
            const n = @min(msg.len, sr.len - 1);
            @memcpy(sr[0..n], msg[0..n]);
            sr[n] = 0;
            const fname = sliceOf(&swed.jpl.js.jplfname);
            if (n + fname.len + 3 < AS_MAXCH) {
                const out = std.fmt.bufPrint(sr[0 .. sr.len - 1], "alleged ephemeris file ({s}) has invalid format.", .{fname}) catch sr[0..0];
                sr[out.len] = 0;
            }
        }
        return NOT_AVAILABLE;
    }
    // ncon = number of constants
    if (fread(std.mem.asBytes(&ncon).ptr, 4, 1, swed.jpl.js.jplfptr) != 1) return NOT_AVAILABLE;
    if (swed.jpl.js.do_reorder)
        reorder(std.mem.asBytes(&ncon), 1);
    // au = astronomical unit
    if (fread(std.mem.asBytes(&au).ptr, 8, 1, swed.jpl.js.jplfptr) != 1) return NOT_AVAILABLE;
    if (swed.jpl.js.do_reorder)
        reorder(std.mem.asBytes(&au), 1);
    // emrat = earth moon mass ratio
    if (fread(std.mem.asBytes(&emrat).ptr, 8, 1, swed.jpl.js.jplfptr) != 1) return NOT_AVAILABLE;
    if (swed.jpl.js.do_reorder)
        reorder(std.mem.asBytes(&emrat), 1);
    // ipt[i+0]: coefficients of planet i start at buf[ipt[i+0]-1]
    // ipt[i+1]: number of coefficients (interpolation order - 1)
    // ipt[i+2]: number of intervals in segment
    if (fread(std.mem.sliceAsBytes(swed.jpl.js.eh_ipt[0..]).ptr, 4, 36, swed.jpl.js.jplfptr) != 36) return NOT_AVAILABLE;
    if (swed.jpl.js.do_reorder)
        reorder(std.mem.sliceAsBytes(swed.jpl.js.eh_ipt[0..]).ptr[0 .. 4 * 36], 36);
    // numde
    if (fread(std.mem.asBytes(&numde).ptr, 4, 1, swed.jpl.js.jplfptr) != 1) return NOT_AVAILABLE;
    if (swed.jpl.js.do_reorder)
        reorder(std.mem.asBytes(&numde), 1);
    // read librations
    if (fread(std.mem.sliceAsBytes(lpt[0..]).ptr, 4, 3, swed.jpl.js.jplfptr) != 3) return NOT_AVAILABLE;
    if (swed.jpl.js.do_reorder)
        reorder(std.mem.sliceAsBytes(lpt[0..]).ptr[0 .. 4 * 3], 3);
    // fill librations into eh_ipt[36]..[38]
    for (0..3) |i|
        swed.jpl.js.eh_ipt[i + 36] = lpt[i];
    _ = fseek(swed.jpl.js.jplfptr, 0, 0); // rewind
    // find the number of ephemeris coefficients from the pointers
    var kmx: i32 = 0;
    var khi: i32 = 0;
    for (0..13) |i| {
        if (swed.jpl.js.eh_ipt[i * 3] > kmx) {
            kmx = swed.jpl.js.eh_ipt[i * 3];
            khi = @intCast(i + 1);
        }
    }
    // All-zero pointer table (C OOB read at ipt[-3]): no usable bodies.
    if (khi == 0)
        return NOT_AVAILABLE;
    var nd: i32 = 0;
    if (khi == 12)
        nd = 2
    else
        nd = 3;
    const khiu: usize = @intCast(khi);
    var ksize: i32 = @intCast(@as(i64, swed.jpl.js.eh_ipt[khiu * 3 - 3]) + @as(i64, nd) * @as(i64, swed.jpl.js.eh_ipt[khiu * 3 - 2]) * @as(i64, swed.jpl.js.eh_ipt[khiu * 3 - 1]) - 1);
    ksize = @intCast(@as(i64, ksize) * 2);
    // de102 files give wrong ksize, because they contain 424 empty bytes
    // per record. Fixed by hand!
    if (ksize == 1546)
        ksize = 1652;
    if (ksize < 1000 or ksize > 5000) {
        if (serr) |sr| {
            const out = std.fmt.bufPrint(sr[0 .. sr.len - 1], "JPL ephemeris file does not provide valid ksize ({d})", .{ksize}) catch sr[0..0];
            sr[out.len] = 0;
        }
        return NOT_AVAILABLE;
    }
    return ksize;
}

/// swejpl.c swi_pleph: position of 'ntarg' relative to 'ncent' (au, au/day)
pub fn swi_pleph(et: f64, ntarg: i32, ncent: i32, rrd: *[6]f64, swed: *sweph.Swed, serr: ?[]u8) i32 {
    var list: [12]i32 = .{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    const pv = swed.jpl.js.pv[0..];
    const pvsun = swed.jpl.js.pvsun[0..];
    for (0..6) |i|
        rrd[i] = 0.0;
    if (ntarg == ncent)
        return 0;
    // check for nutation call
    if (ntarg == J_NUT) {
        if (swed.jpl.js.eh_ipt[34] > 0) {
            list[10] = 2;
            return state(et, list[0..], false, pv, pvsun, rrd, swed, serr);
        } else {
            if (serr) |sr| {
                const msg = "No nutations on the JPL ephemeris file;";
                const n = @min(msg.len, sr.len - 1);
                @memcpy(sr[0..n], msg[0..n]);
                sr[n] = 0;
            }
            return NOT_AVAILABLE;
        }
    }
    if (ntarg == J_LIB) {
        if (swed.jpl.js.eh_ipt[37] > 0) {
            list[11] = 2;
            const retc = state(et, list[0..], false, pv, pvsun, rrd, swed, serr);
            if (retc != OK)
                return retc;
            for (0..6) |i|
                rrd[i] = pv[i + 60];
            return 0;
        } else {
            if (serr) |sr| {
                const msg = "No librations on the ephemeris file;";
                const n = @min(msg.len, sr.len - 1);
                @memcpy(sr[0..n], msg[0..n]);
                sr[n] = 0;
            }
            return NOT_AVAILABLE;
        }
    }
    // set up proper entries in 'list' array for state call
    if (ntarg < J_SUN)
        list[@intCast(ntarg)] = 2;
    if (ntarg == J_MOON) // Moon needs Earth
        list[@intCast(J_EARTH)] = 2;
    if (ntarg == J_EARTH) // Earth needs Moon
        list[@intCast(J_MOON)] = 2;
    if (ntarg == J_EMB) // EMB needs Earth
        list[@intCast(J_EARTH)] = 2;
    if (ncent < J_SUN)
        list[@intCast(ncent)] = 2;
    if (ncent == J_MOON) // Moon needs Earth
        list[@intCast(J_EARTH)] = 2;
    if (ncent == J_EARTH) // Earth needs Moon
        list[@intCast(J_MOON)] = 2;
    if (ncent == J_EMB) // EMB needs Earth
        list[@intCast(J_EARTH)] = 2;
    const retc = state(et, list[0..], true, pv, pvsun, rrd, swed, serr);
    if (retc != OK)
        return retc;
    if (ntarg == J_SUN or ncent == J_SUN) {
        for (0..6) |i|
            pv[i + 6 * @as(usize, @intCast(J_SUN))] = pvsun[i];
    }
    if (ntarg == J_SBARY or ncent == J_SBARY) {
        for (0..6) |i| {
            pv[i + 6 * @as(usize, @intCast(J_SBARY))] = 0.0;
        }
    }
    if (ntarg == J_EMB or ncent == J_EMB) {
        for (0..6) |i|
            pv[i + 6 * @as(usize, @intCast(J_EMB))] = pv[i + 6 * @as(usize, @intCast(J_EARTH))];
    }
    if ((ntarg == J_EARTH and ncent == J_MOON) or (ntarg == J_MOON and ncent == J_EARTH)) {
        for (0..6) |i|
            pv[i + 6 * @as(usize, @intCast(J_EARTH))] = 0.0;
    } else {
        if (list[@intCast(J_EARTH)] == 2) {
            for (0..6) |i|
                pv[i + 6 * @as(usize, @intCast(J_EARTH))] -= pv[i + 6 * @as(usize, @intCast(J_MOON))] / (swed.jpl.js.eh_emrat + 1.0);
        }
        if (list[@intCast(J_MOON)] == 2) {
            for (0..6) |i| {
                pv[i + 6 * @as(usize, @intCast(J_MOON))] += pv[i + 6 * @as(usize, @intCast(J_EARTH))];
            }
        }
    }
    for (0..6) |i|
        rrd[i] = pv[i + @as(usize, @intCast(ntarg)) * 6] - pv[i + @as(usize, @intCast(ncent)) * 6];
    return OK;
}

/// swejpl.c interp: differentiate and interpolate Chebyshev coefficients
fn interp(buf: []const f64, t: f64, intv: f64, ncfin: i32, ncmin: i32, nain: i32, ifl: i32, pv: []f64, ctx: *JplCtx) void {
    const pc = ctx.js.pc[0..];
    const vc = ctx.js.vc[0..];
    const ac = ctx.js.ac[0..];
    const jc = ctx.js.jc[0..];
    const ncf: usize = @intCast(ncfin);
    const ncm: usize = @intCast(ncmin);
    const na: f64 = @floatFromInt(nain);
    var temp: f64 = undefined;
    var ni: i32 = undefined;
    var tc: f64 = undefined;
    var dt1: f64 = undefined;
    // get correct sub-interval number for this set of coefficients and then
    // get normalized chebyshev time within that subinterval.
    if (t >= 0)
        dt1 = @floor(t)
    else
        dt1 = -@floor(-t);
    temp = na * t;
    // Corrupt-na / stray-t guard (C UB on OOB sub-interval): clamp into the
    // valid sub-interval range. Valid files never trigger this (t is
    // segment-normalized, na validated at open).
    const ni_max: f64 = @floatFromInt(@max(nain, 1) - 1);
    const ni_f = temp - dt1;
    ni = if (!std.math.isFinite(ni_f)) 0 else @intFromFloat(@min(@max(ni_f, 0.0), ni_max));
    // tc is the normalized chebyshev time (-1 <= tc <= 1)
    tc = (@mod(temp, 1.0) + dt1) * 2.0 - 1.0;
    // check to see whether chebyshev time has changed,
    // and compute new polynomial values if it has.
    if (tc != pc[1]) {
        ctx.np = 2;
        ctx.nv = 3;
        ctx.nac = 4;
        ctx.njk = 5;
        pc[1] = tc;
        ctx.twot = tc + tc;
    }
    // be sure that at least 'ncf' polynomials have been evaluated
    // and are stored in the array 'pc'.
    if (ctx.np < ncf) {
        var i: usize = @intCast(ctx.np);
        while (i < ncf) : (i += 1)
            pc[i] = ctx.twot * pc[i - 1] - pc[i - 2];
        ctx.np = @intCast(ncf);
    }
    // interpolate to get position for each component
    const niu: usize = @intCast(ni);
    for (0..ncm) |i| {
        pv[i] = 0.0;
        var j: usize = ncf;
        while (j > 0) {
            j -= 1;
            pv[i] += pc[j] * buf[j + (i + niu * ncm) * ncf];
        }
    }
    if (ifl <= 1)
        return;
    // if velocity interpolation is wanted, be sure enough
    // derivative polynomials have been generated and stored.
    const bma = (na + na) / intv;
    vc[2] = ctx.twot + ctx.twot;
    if (ctx.nv < ncf) {
        var i: usize = @intCast(ctx.nv);
        while (i < ncf) : (i += 1)
            vc[i] = ctx.twot * vc[i - 1] + pc[i - 1] + pc[i - 1] - vc[i - 2];
        ctx.nv = @intCast(ncf);
    }
    // interpolate to get velocity for each component
    for (0..ncm) |i| {
        pv[i + ncm] = 0.0;
        var j: usize = ncf;
        while (j > 1) {
            j -= 1;
            pv[i + ncm] += vc[j] * buf[j + (i + niu * ncm) * ncf];
        }
        pv[i + ncm] *= bma;
    }
    if (ifl == 2)
        return;
    // check acceleration polynomial values, and re-do if necessary
    const bma2 = bma * bma;
    ac[3] = pc[1] * 24.0;
    if (ctx.nac < ncf) {
        ctx.nac = @intCast(ncf);
        var i: usize = @intCast(ctx.nac);
        while (i < ncf) : (i += 1)
            ac[i] = ctx.twot * ac[i - 1] + vc[i - 1] * 4.0 - ac[i - 2];
    }
    // get acceleration for each component
    for (0..ncm) |i| {
        pv[i + ncm * 2] = 0.0;
        var j: usize = ncf;
        while (j > 2) {
            j -= 1;
            pv[i + ncm * 2] += ac[j] * buf[j + (i + niu * ncm) * ncf];
        }
        pv[i + ncm * 2] *= bma2;
    }
    if (ifl == 3)
        return;
    // check jerk polynomial values, and re-do if necessary
    const bma3 = bma * bma2;
    jc[4] = pc[1] * 192.0;
    if (ctx.njk < ncf) {
        ctx.njk = @intCast(ncf);
        var i: usize = @intCast(ctx.njk);
        while (i < ncf) : (i += 1)
            jc[i] = ctx.twot * jc[i - 1] + ac[i - 1] * 6.0 - jc[i - 2];
    }
    // get jerk for each component
    for (0..ncm) |i| {
        pv[i + ncm * 3] = 0.0;
        var j: usize = ncf;
        while (j > 3) {
            j -= 1;
            pv[i + ncm * 3] += jc[j] * buf[j + (i + niu * ncm) * ncf];
        }
        pv[i + ncm * 3] *= bma3;
    }
}

/// swejpl.c state: read and interpolate the JPL ephemeris file.
/// list == null only reads/validates the header (read_const_jpl).
fn state(et: f64, list: ?[]i32, do_bary: bool, pv: ?[]f64, pvsun: ?[]f64, nut: ?[]f64, swed: *sweph.Swed, serr: ?[]u8) i32 {
    var nseg: i64 = 0;
    var flen: i64 = 0;
    var nb: i64 = 0;
    var aufac: f64 = undefined;
    var s: f64 = undefined;
    var t: f64 = undefined;
    var intv: f64 = undefined;
    var ts: [4]f64 = .{ 0, 0, 0, 0 };
    var nrecl: i32 = 0;
    var ksize: i32 = 0;
    var nr: i32 = 0;
    var et_mn: f64 = undefined;
    var et_fr: f64 = undefined;
    const ipt = swed.jpl.js.eh_ipt[0..];
    var ch_ttl: [252]u8 = undefined;
    var lpt: [3]i32 = .{ 0, 0, 0 };
    const buf = swed.jpl.js.buf[0..];
    if (swed.jpl.js.jplfptr == null) {
        // the number of single precision words in a record
        ksize = fsizer(serr, swed);
        nrecl = 4;
        if (ksize == NOT_AVAILABLE)
            return NOT_AVAILABLE;
        swed.jpl.irecsz = nrecl * ksize; // record size in bytes
        swed.jpl.ncoeffs = @divTrunc(ksize, 2); // # of coefficients, doubles
        // ttl = ephemeris title
        if (fread(&ch_ttl, 1, 252, swed.jpl.js.jplfptr) != 252) return NOT_AVAILABLE;
        // cnam = names of constants
        if (fread(&swed.jpl.js.ch_cnam, 1, 2400, swed.jpl.js.jplfptr) != 2400) return NOT_AVAILABLE;
        // ss[0] = start epoch, ss[1] = end epoch, ss[2] = segment size
        if (freadDoubles(swed.jpl.js.eh_ss[0..], swed.jpl.js.jplfptr) != 3) return NOT_AVAILABLE;
        if (swed.jpl.js.do_reorder)
            reorder(std.mem.asBytes(&swed.jpl.js.eh_ss), 3);
        // ncon = number of constants
        if (fread(std.mem.asBytes(&swed.jpl.js.eh_ncon).ptr, 4, 1, swed.jpl.js.jplfptr) != 1) return NOT_AVAILABLE;
        if (swed.jpl.js.do_reorder)
            reorder(std.mem.asBytes(&swed.jpl.js.eh_ncon), 1);
        // au = astronomical unit
        if (fread(std.mem.asBytes(&swed.jpl.js.eh_au).ptr, 8, 1, swed.jpl.js.jplfptr) != 1) return NOT_AVAILABLE;
        if (swed.jpl.js.do_reorder)
            reorder(std.mem.asBytes(&swed.jpl.js.eh_au), 1);
        // emrat = earth moon mass ratio
        if (fread(std.mem.asBytes(&swed.jpl.js.eh_emrat).ptr, 8, 1, swed.jpl.js.jplfptr) != 1) return NOT_AVAILABLE;
        if (swed.jpl.js.do_reorder)
            reorder(std.mem.asBytes(&swed.jpl.js.eh_emrat), 1);
        // ipt
        if (fread(std.mem.sliceAsBytes(ipt[0..]).ptr, 4, 36, swed.jpl.js.jplfptr) != 36) return NOT_AVAILABLE;
        if (swed.jpl.js.do_reorder)
            reorder(std.mem.sliceAsBytes(ipt[0..]).ptr[0 .. 4 * 36], 36);
        // numde
        if (fread(std.mem.asBytes(&swed.jpl.js.eh_denum).ptr, 4, 1, swed.jpl.js.jplfptr) != 1) return NOT_AVAILABLE;
        if (swed.jpl.js.do_reorder)
            reorder(std.mem.asBytes(&swed.jpl.js.eh_denum), 1);
        if (fread(std.mem.sliceAsBytes(lpt[0..]).ptr, 4, 3, swed.jpl.js.jplfptr) != 3) return NOT_AVAILABLE;
        if (swed.jpl.js.do_reorder)
            reorder(std.mem.sliceAsBytes(lpt[0..]).ptr[0 .. 4 * 3], 3);
        // cval[]: other constants in next record
        _ = fseek(swed.jpl.js.jplfptr, @as(i64, swed.jpl.irecsz), 0);
        if (freadDoubles(swed.jpl.js.eh_cval[0..], swed.jpl.js.jplfptr) != 400) return NOT_AVAILABLE;
        if (swed.jpl.js.do_reorder)
            reorder(std.mem.sliceAsBytes(swed.jpl.js.eh_cval[0..]).ptr[0 .. 8 * 400], 400);
        // new 26-aug-2008: verify correct block size
        for (0..3) |i|
            ipt[i + 36] = lpt[i];
        swed.jpl.nrl = 0;
        // is file length correct?
        _ = fseek(swed.jpl.js.jplfptr, 0, 2); // SEEK_END
        flen = ftell(swed.jpl.js.jplfptr);
        // # of segments in file; corrupt ss[2]==0 makes this non-finite
        // (C UB: (int)inf) — fail the open like C's observable mutilated
        // error instead of panicking.
        const nseg_f = (swed.jpl.js.eh_ss[1] - swed.jpl.js.eh_ss[0]) / swed.jpl.js.eh_ss[2];
        if (!std.math.isFinite(nseg_f) or nseg_f > 2147483647 or nseg_f < -2147483648)
            return NOT_AVAILABLE;
        nseg = @intFromFloat(nseg_f);
        // sum of all cheby coeffs of all planets and segments
        nb = 0;
        for (0..13) |i| {
            var k: i64 = 3;
            if (i == 11)
                k = 2;
            nb += @as(i64, ipt[i * 3 + 1]) * @as(i64, ipt[i * 3 + 2]) * k * nseg;
        }
        // add start and end epochs of segments
        nb += 2 * nseg;
        // doubles to bytes
        nb *= 8;
        // add size of header and constants section
        nb += 2 * @as(i64, ksize) * @as(i64, nrecl);
        if (flen != nb
            // some of our files are one record too long
        and flen - nb != @as(i64, ksize) * @as(i64, nrecl)) {
            if (serr) |sr| {
                const fname = sliceOf(&swed.jpl.js.jplfname);
                var msg: [AS_MAXCH]u8 = undefined;
                var r: []u8 = undefined;
                if (msg.len >= fname.len + 80) {
                    r = std.fmt.bufPrint(&msg, "JPL ephemeris file {s} is mutilated; length = {d} instead of {d}.", .{ fname, @as(u32, @intCast(flen)), @as(u32, @intCast(nb)) }) catch msg[0..0];
                } else {
                    r = std.fmt.bufPrint(&msg, "JPL ephemeris file is mutilated; length = {d} instead of {d}.", .{ @as(u32, @intCast(flen)), @as(u32, @intCast(nb)) }) catch msg[0..0];
                }
                const c = @min(r.len, sr.len - 1);
                @memcpy(sr[0..c], msg[0..c]);
                sr[c] = 0;
            }
            return NOT_AVAILABLE;
        }
        // check if start and end dates in segments are the same as in
        // file header
        _ = fseek(swed.jpl.js.jplfptr, @as(i64, 2) * @as(i64, swed.jpl.irecsz), 0);
        if (freadDoubles(ts[0..2], swed.jpl.js.jplfptr) != 2) return NOT_AVAILABLE;
        if (swed.jpl.js.do_reorder)
            reorder(std.mem.asBytes(&ts), 2);
        _ = fseek(swed.jpl.js.jplfptr, @as(i64, @intCast(nseg + 2 - 1)) * @as(i64, swed.jpl.irecsz), 0);
        if (freadDoubles(ts[2..4], swed.jpl.js.jplfptr) != 2) return NOT_AVAILABLE;
        if (swed.jpl.js.do_reorder)
            reorder(std.mem.asBytes(ts[2..]), 2);
        if (ts[0] != swed.jpl.js.eh_ss[0] or ts[3] != swed.jpl.js.eh_ss[1]) {
            if (serr) |sr| {
                const r = std.fmt.bufPrint(sr[0 .. sr.len - 1], "JPL ephemeris file is corrupt; start/end date check failed. {d:.1} != {d:.1} || {d:.1} != {d:.1}", .{ ts[0], swed.jpl.js.eh_ss[0], ts[3], swed.jpl.js.eh_ss[1] }) catch sr[0..0];
                sr[r.len] = 0;
            }
            return NOT_AVAILABLE;
        }
        // Corrupt-table guard (C UB on OOB interp reads past the record).
        // Runs after C's own checks so nb/length semantics are untouched:
        // every really-read region must be absent (normalized to zeros) or
        // fit the record with ctx-sized counts. Valid JPL files always
        // satisfy this; without it, corrupt pointers panic (Debug) or read
        // out of bounds. Component factor k mirrors the nb accounting
        // (k=2 for the nutation table at i==11, 3 for 3-comp bodies);
        // ipt[36..38] (librations, filled from lpt above) use k=3.
        // Body 12's file triple is overwritten by lpt and never read.
        for (0..12) |i| {
            const st = ipt[i * 3];
            const nc = ipt[i * 3 + 1];
            const ni_ = ipt[i * 3 + 2];
            if (st <= 0 or nc <= 0 or ni_ <= 0) {
                ipt[i * 3] = 0;
                ipt[i * 3 + 1] = 0;
                ipt[i * 3 + 2] = 0;
                continue;
            }
            if (nc > 18)
                return NOT_AVAILABLE;
            var k: i64 = 3;
            if (i == 11)
                k = 2;
            const end: i64 = @as(i64, st - 1) + k * @as(i64, nc) * @as(i64, ni_);
            if (end > @as(i64, swed.jpl.ncoeffs))
                return NOT_AVAILABLE;
        }
        {
            const st = ipt[36];
            const nc = ipt[37];
            const ni_ = ipt[38];
            if (st <= 0 or nc <= 0 or ni_ <= 0) {
                ipt[36] = 0;
                ipt[37] = 0;
                ipt[38] = 0;
            } else {
                if (nc > 18)
                    return NOT_AVAILABLE;
                const end: i64 = @as(i64, st - 1) + 3 * @as(i64, nc) * @as(i64, ni_);
                if (end > @as(i64, swed.jpl.ncoeffs))
                    return NOT_AVAILABLE;
            }
        }
    }
    if (list == null)
        return 0;
    s = et - 0.5;
    et_mn = @floor(s);
    et_fr = s - et_mn; // fraction of days since previous midnight
    et_mn += 0.5; // midnight before epoch
    // error return for epoch out of range
    if (et < swed.jpl.js.eh_ss[0] or et > swed.jpl.js.eh_ss[1]) {
        if (serr) |sr| {
            const r = std.fmt.bufPrint(sr[0 .. sr.len - 1], "jd {d:.6} outside JPL eph. range {d:.2} .. {d:.2};", .{ et, swed.jpl.js.eh_ss[0], swed.jpl.js.eh_ss[1] }) catch sr[0..0];
            sr[r.len] = 0;
        }
        return BEYOND_EPH_LIMITS;
    }
    // calculate record # and relative time in interval. Safe by
    // construction: et is range-checked above and ss[2] passed the open-time
    // nseg finiteness check, so |(et-ss[0])/ss[2]| <= |nseg|+1 (i32 range).
    nr = @as(i32, @intFromFloat((et_mn - swed.jpl.js.eh_ss[0]) / swed.jpl.js.eh_ss[2])) + 2;
    if (et_mn == swed.jpl.js.eh_ss[1])
        nr -= 1; // end point of ephemeris, use last record
    t = (et_mn - (@as(f64, @floatFromInt(nr - 2)) * swed.jpl.js.eh_ss[2] + swed.jpl.js.eh_ss[0]) + et_fr) / swed.jpl.js.eh_ss[2];
    // read correct record if not in core
    if (nr != swed.jpl.nrl) {
        swed.jpl.nrl = nr;
        if (fseek(swed.jpl.js.jplfptr, @as(i64, nr) * @as(i64, swed.jpl.irecsz), 0) != 0) {
            if (serr) |sr| {
                const r = std.fmt.bufPrint(sr[0 .. sr.len - 1], "Read error in JPL eph. at {d}\n", .{et}) catch sr[0..0];
                sr[r.len] = 0;
            }
            return NOT_AVAILABLE;
        }
        var k: usize = 1;
        while (k <= swed.jpl.ncoeffs) : (k += 1) {
            if (fread(std.mem.asBytes(&buf[k - 1]).ptr, 8, 1, swed.jpl.js.jplfptr) != 1) {
                if (serr) |sr| {
                    const r = std.fmt.bufPrint(sr[0 .. sr.len - 1], "Read error in JPL eph. at {d}\n", .{et}) catch sr[0..0];
                    sr[r.len] = 0;
                }
                return NOT_AVAILABLE;
            }
            if (swed.jpl.js.do_reorder)
                reorder(std.mem.asBytes(&buf[k - 1]), 1);
        }
    }
    if (swed.jpl.js.do_km) {
        intv = swed.jpl.js.eh_ss[2] * 86400.0;
        aufac = 1.0;
    } else {
        intv = swed.jpl.js.eh_ss[2];
        aufac = 1.0 / swed.jpl.js.eh_au;
    }
    const pv_arr = pv.?;
    const pvsun_arr = pvsun.?;
    // interpolate ssbary sun; absent sun entry (C OOB read) fails the
    // computation so callers fall back gracefully instead of panicking.
    if (ipt[30] <= 0)
        return NOT_AVAILABLE;
    interp(buf[@intCast(ipt[30] - 1)..], t, intv, ipt[31], 3, ipt[32], 2, pvsun_arr, &swed.jpl);
    for (0..6) |i| {
        pvsun_arr[i] *= aufac;
    }
    // check and interpolate whichever bodies are requested; absent table
    // entries (C OOB read) fail the computation for graceful fallback.
    for (0..10) |i| {
        if (list.?[i] > 0) {
            if (ipt[i * 3] <= 0)
                return NOT_AVAILABLE;
            interp(buf[@intCast(ipt[i * 3] - 1)..], t, intv, ipt[i * 3 + 1], 3, ipt[i * 3 + 2], list.?[i], pv_arr[i * 6 ..], &swed.jpl);
            for (0..6) |j| {
                if (i < 9 and !do_bary) {
                    pv_arr[j + i * 6] = pv_arr[j + i * 6] * aufac - pvsun_arr[j];
                } else {
                    pv_arr[j + i * 6] *= aufac;
                }
            }
        }
    }
    // do nutations if requested (and if on file)
    if (list.?[10] > 0 and ipt[34] > 0) {
        interp(buf[@intCast(ipt[33] - 1)..], t, intv, ipt[34], 2, ipt[35], list.?[10], nut.?, &swed.jpl);
    }
    // get librations if requested (and if on file)
    if (list.?[11] > 0 and ipt[37] > 0) {
        interp(buf[@intCast(ipt[36] - 1)..], t, intv, ipt[37], 3, ipt[38], list.?[1], pv_arr[60..], &swed.jpl);
    }
    return OK;
}

/// swejpl.c read_const_jpl
fn read_const_jpl(ss: *[3]f64, swed: *sweph.Swed, serr: ?[]u8) i32 {
    const retc = state(0.0, null, false, null, null, null, swed, serr);
    if (retc != OK)
        return retc;
    for (0..3) |i|
        ss[i] = swed.jpl.js.eh_ss[i];
    return OK;
}

/// swejpl.c reorder: byte-swap size-byte words in place
fn reorder(x: []u8, number: usize) void {
    var sp1: usize = 0;
    var s: [8]u8 = undefined;
    const size = x.len / number;
    for (0..number) |_| {
        for (0..size) |j|
            s[j] = x[sp1 + size - j - 1];
        for (0..size) |j|
            x[sp1 + j] = s[j];
        sp1 += size;
    }
}

/// swejpl.c swi_close_jpl_file
pub fn swi_close_jpl_file(swed: *sweph.Swed) void {
    if (swed.jpl.js_is_init) {
        if (swed.jpl.js.jplfptr) |fp| {
            _ = fclose(fp);
        }
        // swi_fopen stored the same handle in fidat[SEI_FILE_PLANET]; the C
        // double-closes it in the file loops. Nulling it here keeps the
        // observed behavior (the loop memsets fidat anyway) without UB.
        swed.fidat[sweph.SEI_FILE_PLANET].fp = null;
        swed.jpl.js = .{};
        swed.jpl.js_is_init = false;
    }
}

/// swejpl.c swi_open_jpl_file
pub fn swi_open_jpl_file(ss: *[3]f64, fname: []const u8, fpath: []const u8, swed: *sweph.Swed, serr: ?[]u8) i32 {
    // if open, return
    if (swed.jpl.js_is_init and swed.jpl.js.jplfptr != null)
        return OK;
    swed.jpl.js = .{};
    swed.jpl.js_is_init = true;
    const n1 = @min(fname.len, swed.jpl.js.jplfname.len - 1);
    @memcpy(swed.jpl.js.jplfname[0..n1], fname[0..n1]);
    swed.jpl.js.jplfname[n1] = 0;
    const n2 = @min(fpath.len, swed.jpl.js.jplfpath.len - 1);
    @memcpy(swed.jpl.js.jplfpath[0..n2], fpath[0..n2]);
    swed.jpl.js.jplfpath[n2] = 0;
    const retc = read_const_jpl(ss, swed, serr);
    if (retc != OK) {
        swi_close_jpl_file(swed);
    } else {
        // intializations for function interpol()
        swed.jpl.js.pc[0] = 1;
        swed.jpl.js.pc[1] = 2;
        swed.jpl.js.vc[1] = 1;
        swed.jpl.js.ac[2] = 4;
        swed.jpl.js.jc[3] = 24;
    }
    return retc;
}

/// swejpl.c swi_get_jpl_denum
pub fn swi_get_jpl_denum(swed: *sweph.Swed) i32 {
    return swed.jpl.js.eh_denum;
}
