// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2026 Mohammad Shafiee — Zig port of Swiss Ephemeris
//
// In-memory virtual filesystem for wasm32-freestanding (browser) builds.
//
// freestanding wasm has no libc, so the fopen/fread/fseek/ftell/fclose/fgets
// shims in sweph.zig / swejpl.zig / swemplan.zig delegate here. Hosts stage
// file bytes verbatim (fetch → ArrayBuffer, never text-decode) via
// swe_vfs_register (see swe_abi.zig); lookups key on the path basename
// because swi_fopen probes "<dir>/<fname>" trial paths per ephepath entry.
//
// Byte-exactness is load-bearing: text parsers demand CRLF (read_const
// rejects header lines without "\r\n") and binary .se1/.eph go through
// endian-correcting do_fread — so registered bytes are memcpy'd only, and
// fgets preserves "\r\n" in-buffer exactly like C.
//
// This module compiles on all targets; on non-wasm targets the VFS is
// present but idle (callers use libc directly).
const std = @import("std");
const builtin = @import("builtin");

const is_wasm = builtin.target.cpu.arch.isWasm();

pub const MAX_FILES = 16;
pub const MAX_HANDLES = 16;
pub const MAX_NAME = 256; // matches sweph.AS_MAXCH

const FileEntry = struct {
    name: [MAX_NAME]u8 = [_]u8{0} ** MAX_NAME, // NUL-terminated basename
    data: []u8 = &[_]u8{},
    used: bool = false,
};

const Handle = struct {
    file: usize = 0,
    cursor: usize = 0,
    used: bool = false,
};

var files: [MAX_FILES]FileEntry = [_]FileEntry{.{}} ** MAX_FILES;
var handles: [MAX_HANDLES]Handle = [_]Handle{.{}} ** MAX_HANDLES;

/// Allocator owning registered file bytes: proven wasm_allocator on wasm
/// (memory.grow), page_allocator elsewhere.
fn ownedAllocator() std.mem.Allocator {
    if (is_wasm) {
        return std.heap.wasm_allocator;
    } else {
        return std.heap.page_allocator;
    }
}

// ---------------------------------------------------------------------------
// heap probe for sweph's c_allocator / fs_alloc
// ---------------------------------------------------------------------------
// page_allocator compiles on wasm32-freestanding but is runtime-unverified
// in a browser. Probe once: try alloc+free, fall back to wasm_allocator
// (proven by the swe_wasm_alloc staging path) on failure.
var heap_choice: ?std.mem.Allocator = null;

pub fn heapAllocator() std.mem.Allocator {
    if (!is_wasm) return std.heap.page_allocator;
    if (heap_choice) |a| return a;
    var ok = false;
    if (std.heap.page_allocator.alloc(u8, 16)) |m| {
        std.heap.page_allocator.free(m);
        ok = true;
    } else |_| {}
    heap_choice = if (ok) std.heap.page_allocator else std.heap.wasm_allocator;
    return heap_choice.?;
}

/// Test hook: which backing allocator did the probe select?
/// 0 = unprobed, 1 = page_allocator, 2 = wasm_allocator fallback.
pub fn heapChoiceForTest() i32 {
    if (!is_wasm) return 0;
    _ = heapAllocator();
    return if (heap_choice.?.vtable == std.heap.page_allocator.vtable) 1 else 2;
}

// ---------------------------------------------------------------------------
// registration (called via swe_abi swe_vfs_register / swe_vfs_clear)
// ---------------------------------------------------------------------------
fn basenameOf(path: []const u8) []const u8 {
    var base = path;
    if (std.mem.lastIndexOfScalar(u8, base, '/')) |i| base = base[i + 1 ..];
    return base;
}

fn nameEquals(entry: *const FileEntry, base: []const u8) bool {
    const stored = std.mem.sliceTo(&entry.name, 0);
    return std.mem.eql(u8, stored, base);
}

/// Copy `data` verbatim into VFS-owned storage under `name` (basename).
/// Re-registering a name replaces its bytes. Returns 0 ok, -1 alloc fail,
/// -2 table full, -3 empty name.
pub fn register(name: []const u8, data: []const u8) i32 {
    const base = basenameOf(name);
    if (base.len == 0 or base.len >= MAX_NAME) return -3;
    // replace existing entry
    for (&files) |*f| {
        if (f.used and nameEquals(f, base)) {
            const nd = ownedAllocator().alloc(u8, data.len) catch return -1;
            @memcpy(nd, data);
            ownedAllocator().free(f.data);
            f.data = nd;
            return 0;
        }
    }
    for (&files) |*f| {
        if (!f.used) {
            const nd = ownedAllocator().alloc(u8, data.len) catch return -1;
            @memcpy(nd, data);
            @memcpy(f.name[0..base.len], base);
            f.name[base.len] = 0;
            f.data = nd;
            f.used = true;
            return 0;
        }
    }
    return -2;
}

pub fn clear() void {
    for (&files) |*f| {
        if (f.used) {
            ownedAllocator().free(f.data);
            f.* = .{};
        }
    }
    for (&handles) |*h| h.* = .{};
}

pub fn fileCount() usize {
    var n: usize = 0;
    for (&files) |*f| {
        if (f.used) n += 1;
    }
    return n;
}

fn findFile(base: []const u8) ?usize {
    for (&files, 0..) |*f, i| {
        if (f.used and nameEquals(f, base)) return i;
    }
    return null;
}

// Handles are 1-based indices cast to ?*anyopaque (0 stays null).
fn handleOf(stream: ?*anyopaque) ?*Handle {
    const fp = stream orelse return null;
    const idx = @intFromPtr(fp);
    if (idx == 0 or idx > MAX_HANDLES) return null;
    const h = &handles[idx - 1];
    if (!h.used) return null;
    return h;
}

// ---------------------------------------------------------------------------
// C stdio surface (wasm branch of the per-module shims)
// ---------------------------------------------------------------------------
pub fn fopen(path: [*:0]const u8) ?*anyopaque {
    const base = basenameOf(std.mem.span(path));
    if (base.len == 0) return null;
    const fi = findFile(base) orelse return null;
    for (&handles, 0..) |*h, i| {
        if (!h.used) {
            h.* = .{ .file = fi, .cursor = 0, .used = true };
            return @ptrFromInt(i + 1);
        }
    }
    return null;
}

pub fn fread(ptr: [*]u8, size: usize, nitems: usize, stream: ?*anyopaque) usize {
    const h = handleOf(stream) orelse return 0;
    if (size == 0 or nitems == 0) return 0;
    const data = files[h.file].data;
    const avail = if (h.cursor >= data.len) 0 else data.len - h.cursor;
    // complete items only, like C: a trailing partial item is not consumed
    const items = @min(nitems, avail / size);
    const nbytes = items * size;
    @memcpy(ptr[0..nbytes], data[h.cursor .. h.cursor + nbytes]);
    h.cursor += nbytes;
    return items;
}

pub fn fseek(stream: ?*anyopaque, off: i64, whence: i32) i32 {
    const h = handleOf(stream) orelse return -1;
    const len: i64 = @intCast(files[h.file].data.len);
    const base: i64 = switch (whence) {
        0 => 0, // SEEK_SET
        1 => @as(i64, @intCast(h.cursor)), // SEEK_CUR
        2 => len, // SEEK_END
        else => return -1,
    };
    const newpos = base + off;
    if (newpos < 0 or newpos > len) return -1;
    h.cursor = @intCast(newpos);
    return 0;
}

pub fn ftell(stream: ?*anyopaque) i64 {
    const h = handleOf(stream) orelse return -1;
    return @intCast(h.cursor);
}

pub fn fclose(stream: ?*anyopaque) i32 {
    const h = handleOf(stream) orelse return 0;
    h.* = .{};
    return 0;
}

/// C fgets: copy up to size-1 bytes stopping AFTER the first '\n'
/// (so "\r\n" survives in-buffer), NUL-terminate, null at EOF.
pub fn fgets(buf: [*]u8, size: i32, stream: ?*anyopaque) ?[*:0]u8 {
    const h = handleOf(stream) orelse return null;
    if (size <= 0) return null;
    const data = files[h.file].data;
    if (h.cursor >= data.len) return null;
    const sizeu: usize = @intCast(size);
    const max = @min(sizeu - 1, data.len - h.cursor);
    if (max == 0) {
        buf[0] = 0;
        return @ptrCast(buf);
    }
    var n: usize = 0;
    while (n < max) : (n += 1) {
        buf[n] = data[h.cursor + n];
        if (data[h.cursor + n] == '\n') {
            n += 1;
            break;
        }
    }
    h.cursor += n;
    buf[n] = 0;
    return @ptrCast(buf);
}
