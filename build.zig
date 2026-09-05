const std = @import("std");

fn mkmod(b: *std.Build, bo: *std.Build.Step.Options, name: []const u8, path: []const u8, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const m = b.addModule(name, .{
        .root_source_file = b.path(path),
        .target = target,
        .optimize = optimize,
    });
    m.addOptions("build_options", bo);
    return m;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const isWasm = target.result.cpu.arch.isWasm();
    const isShimOK = !isWasm and target.result.os.tag != .windows;
    const pure_opt = b.option(bool, "pure", "pure Zig: std.math instead of libm shim");
    const pure = if (isShimOK) (pure_opt orelse false) else true;
    const build_options = b.addOptions();
    build_options.addOption(bool, "pure", pure);
    build_options.addOption(bool, "is_wasm", isWasm);

    // ── Named modules per the dependency DAG (spec §1) ──────────────────────
    // leaves
    const swedate = mkmod(b, build_options, "swedate", "src/swedate.zig", target, optimize);
    const deltat = mkmod(b, build_options, "deltat", "src/deltat.zig", target, optimize);
    // foundation
    const swephlib = mkmod(b, build_options, "swephlib", "src/swephlib.zig", target, optimize);
    // ephemeris
    const swemmoon = mkmod(b, build_options, "swemmoon", "src/swemmoon.zig", target, optimize);
    const swemplan = mkmod(b, build_options, "swemplan", "src/swemplan.zig", target, optimize);
    const swejpl = mkmod(b, build_options, "swejpl", "src/swejpl.zig", target, optimize);
    // engine
    const sweph = mkmod(b, build_options, "sweph", "src/sweph.zig", target, optimize);
    // consumers
    const swecl = mkmod(b, build_options, "swecl", "src/swecl.zig", target, optimize);
    const swehouse = mkmod(b, build_options, "swehouse", "src/swehouse.zig", target, optimize);
    const swehel = mkmod(b, build_options, "swehel", "src/swehel.zig", target, optimize);

    // Wire inter-module deps (empirically-mapped full graph)
    // leaves: swedate (no deps)
    deltat.addImport("swephlib", swephlib);
    // foundation: swephlib → deltat, swedate
    swephlib.addImport("deltat", deltat);
    swephlib.addImport("swedate", swedate);
    // ephemeris
    swemmoon.addImport("swephlib", swephlib);
    swemplan.addImport("swephlib", swephlib);
    swemplan.addImport("sweph", sweph);
    swejpl.addImport("swephlib", swephlib);
    swejpl.addImport("sweph", sweph);
    // engine: sweph → everything below
    sweph.addImport("swephlib", swephlib);
    sweph.addImport("deltat", deltat);
    sweph.addImport("swemmoon", swemmoon);
    sweph.addImport("swemplan", swemplan);
    sweph.addImport("swejpl", swejpl);
    sweph.addImport("swehouse", swehouse);
    // consumers
    swecl.addImport("sweph", sweph);
    swecl.addImport("swephlib", swephlib);
    swecl.addImport("deltat", deltat);
    swecl.addImport("swemmoon", swemmoon);
    swecl.addImport("swehouse", swehouse);
    swehouse.addImport("swephlib", swephlib);
    swehel.addImport("sweph", sweph);
    swehel.addImport("swecl", swecl);
    swehel.addImport("swephlib", swephlib);
    swehel.addImport("deltat", deltat);
    swehel.addImport("swedate", swedate);

    // ── libswe (C ABI) ──────────────────────────────────────────────────────
    const swe_abi = mkmod(b, build_options, "swe_abi", "src/swe_abi.zig", target, optimize);
    swe_abi.addImport("sweph", sweph);
    swe_abi.addImport("swephlib", swephlib);
    swe_abi.addImport("deltat", deltat);
    swe_abi.addImport("swedate", swedate);
    swe_abi.addImport("swecl", swecl);
    swe_abi.addImport("swehouse", swehouse);
    swe_abi.addImport("swehel", swehel);
    swe_abi.addImport("swemplan", swemplan);
    swe_abi.addImport("swejpl", swejpl);
    swe_abi.addImport("swephlib", swephlib);
    swe_abi.addImport("deltat", deltat);
    swe_abi.addImport("swecl", swecl);
    swe_abi.addImport("swehouse", swehouse);
    swe_abi.addImport("swemplan", swemplan);
    swe_abi.addImport("swejpl", swejpl);
    if (isShimOK and !pure) {
        swe_abi.addCSourceFile(.{ .file = b.path("src/libmshim.c"), .flags = &.{} });
    }
    if (!isWasm) swe_abi.link_libc = true;

    const libswe_static = b.addLibrary(.{
        .name = "swe",
        .root_module = swe_abi,
        .linkage = .static,
    });
    b.installArtifact(libswe_static);
    var libswe_shared: ?*std.Build.Step.Compile = null;
    if (!isWasm) {
        libswe_shared = b.addLibrary(.{
            .name = "swe",
            .root_module = swe_abi,
            .linkage = .dynamic,
        });
        b.installArtifact(libswe_shared.?);
    }

    const libswe_step = b.step("libswe", "libswe static+shared only");
    libswe_step.dependOn(&libswe_static.step);
    if (libswe_shared) |sh| libswe_step.dependOn(&sh.step);

    // Headers
    b.installFile("include/swephexp.h", "include/swephexp.h");
    b.installFile("include/sweodef.h", "include/sweodef.h");
    b.installFile("include/sweph.h", "include/sweph.h");
    b.installFile("include/swephlib.h", "include/swephlib.h");

    // Facade module (importable by zig dep consumers)
    _ = b.addModule("swisseph", .{
        .root_source_file = b.path("src/swisseph.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ── Tools (host-only) ───────────────────────────────────────────────────
    if (!isWasm) {
        const tools = [_]struct { name: []const u8, path: []const u8 }{
            .{ .name = "swetest", .path = "src/bin/swetest.zig" },
            .{ .name = "swevents", .path = "src/bin/swevents.zig" },
            .{ .name = "swemini", .path = "src/bin/swemini.zig" },
            .{ .name = "obama", .path = "src/bin/obama.zig" },
            .{ .name = "swephgen4", .path = "src/ep4/swephgen4.zig" },
        };
        for (tools) |t| {
            const m = mkmod(b, build_options, t.name, t.path, target, optimize);
            m.addImport("swe_abi", swe_abi);
            m.link_libc = true;
            const exe = b.addExecutable(.{ .name = t.name, .root_module = m });
            b.installArtifact(exe);
        }

        // Unit tests: single smoke-test root importing the facade.
        // Shim attached ONLY here — attaching to multiple modules in the same
        // link causes duplicate symbol errors. The facade transitively imports
        // all subsystems.
        const facade = mkmod(b, build_options, "swisseph", "src/swisseph.zig", target, optimize);
        facade.addImport("sweph", sweph);
        facade.addImport("swephlib", swephlib);
        facade.addImport("deltat", deltat);
        facade.addImport("swedate", swedate);
        facade.addImport("swecl", swecl);
        facade.addImport("swehouse", swehouse);
        facade.addImport("swehel", swehel);
        facade.addImport("swemmoon", swemmoon);
        facade.addImport("swemplan", swemplan);
        facade.addImport("swejpl", swejpl);
        const smoke_mod = b.createModule(.{ .root_source_file = b.path("test/smoke.zig"), .target = target, .optimize = optimize });
        smoke_mod.addImport("swe_abi", swe_abi);
        const smoke_tests = b.addTest(.{ .root_module = smoke_mod });
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&b.addRunArtifact(smoke_tests).step);

        // Thread-safety test: N threads × M calls on independent Swed contexts
        const ts_mod = b.createModule(.{ .root_source_file = b.path("verify/concurrent/thread_safety_test.zig"), .target = target, .optimize = optimize });
        ts_mod.addImport("sweph", sweph);
        ts_mod.addImport("swephlib", swephlib);
        ts_mod.addImport("deltat", deltat);
        ts_mod.addImport("swedate", swedate);
        ts_mod.addCSourceFile(.{ .file = b.path("src/libmshim.c"), .flags = &.{} });
        ts_mod.link_libc = true;
        const ts_tests = b.addTest(.{ .root_module = ts_mod });
        test_step.dependOn(&b.addRunArtifact(ts_tests).step);

        // Threaded smoke test: per-thread Swed isolation + ABI threadlocal
        // SweState isolation (shim comes in via swe_abi).
        const thr_mod = b.createModule(.{ .root_source_file = b.path("src/test_thread_safety.zig"), .target = target, .optimize = optimize });
        thr_mod.addOptions("build_options", build_options);
        thr_mod.addImport("sweph", sweph);
        thr_mod.addImport("swephlib", swephlib);
        thr_mod.addImport("deltat", deltat);
        thr_mod.addImport("swedate", swedate);
        thr_mod.addImport("swehouse", swehouse);
        thr_mod.addImport("swecl", swecl);
        thr_mod.addImport("swehel", swehel);
        thr_mod.addImport("swemmoon", swemmoon);
        thr_mod.addImport("swemplan", swemplan);
        thr_mod.addImport("swejpl", swejpl);
        thr_mod.addImport("swe_abi", swe_abi);
        thr_mod.link_libc = true;
        const thr_tests = b.addTest(.{ .root_module = thr_mod });
        test_step.dependOn(&b.addRunArtifact(thr_tests).step);

        // Heavy multithreaded race test: 16 threads with independent context
        // bundles, mixed ephemerides (JPL/SWIEPH/Moshier), fixstar, houses,
        // sidereal toggling — bit-exact vs single-threaded reference. Plus an
        // 8-thread ABI threadlocal stress.
        const stress_mod = b.createModule(.{ .root_source_file = b.path("src/test_stress_race.zig"), .target = target, .optimize = optimize });
        stress_mod.addOptions("build_options", build_options);
        stress_mod.addImport("sweph", sweph);
        stress_mod.addImport("swephlib", swephlib);
        stress_mod.addImport("deltat", deltat);
        stress_mod.addImport("swedate", swedate);
        stress_mod.addImport("swehouse", swehouse);
        stress_mod.addImport("swemmoon", swemmoon);
        stress_mod.addImport("swecl", swecl);
        stress_mod.addImport("swehel", swehel);
        stress_mod.addImport("swemplan", swemplan);
        stress_mod.addImport("swejpl", swejpl);
        stress_mod.addImport("swe_abi", swe_abi);
        stress_mod.link_libc = true;
        const stress_tests = b.addTest(.{ .root_module = stress_mod });
        test_step.dependOn(&b.addRunArtifact(stress_tests).step);

        // Race stress runner: `zig build run-stress` executes the heavy
        // multithreaded race check as an executable (ReleaseSafe).
        // NOTE: -Dtsan (ThreadSanitizer) is intentionally not offered:
        // LLVM does not support TSan on aarch64-macos (runtime segfaults at
        // init) and the x86_64-macos cross build fails compiling libtsan.
        const run_stress_step = b.step("run-stress", "run the heavy multithreaded race stress test");
        const stress_runner = b.addExecutable(.{
            .name = "stress-race",
            .root_module = stress_mod,
        });
        run_stress_step.dependOn(&b.addRunArtifact(stress_runner).step);

        // Examples (compiled as part of test to keep them working)
        const ex_mod = b.createModule(.{ .root_source_file = b.path("examples/zig-native/main.zig"), .target = target, .optimize = optimize });
        ex_mod.addOptions("build_options", build_options);
        ex_mod.addImport("swisseph", facade);
        ex_mod.addCSourceFile(.{ .file = b.path("src/libmshim.c"), .flags = &.{} });
        ex_mod.link_libc = true;
        const example = b.addExecutable(.{ .name = "example-native", .root_module = ex_mod });
        const examples_step = b.step("examples", "Build the examples");
        examples_step.dependOn(&b.addInstallArtifact(example, .{}).step);
        test_step.dependOn(&example.step);

        // README quick-start snippet, compiled verbatim on every test run
        const readme_mod = b.createModule(.{ .root_source_file = b.path("examples/zig-native/readme_check.zig"), .target = target, .optimize = optimize });
        readme_mod.addOptions("build_options", build_options);
        readme_mod.addImport("swisseph", facade);
        readme_mod.addCSourceFile(.{ .file = b.path("src/libmshim.c"), .flags = &.{} });
        readme_mod.link_libc = true;
        const readme_check = b.addExecutable(.{ .name = "readme-check", .root_module = readme_mod });
        test_step.dependOn(&b.addRunArtifact(readme_check).step);

        // zig-difftest: recomputes the 21 verification corpora bit-for-bit
        // (drives the swisseph-zig-verify harness; corpus files live there).
        const dt_mod = b.createModule(.{ .root_source_file = b.path("src/difftest.zig"), .target = target, .optimize = optimize });
        dt_mod.addOptions("build_options", build_options);
        dt_mod.addImport("swedate", swedate);
        dt_mod.addImport("deltat", deltat);
        dt_mod.addImport("swephlib", swephlib);
        dt_mod.addImport("swemmoon", swemmoon);
        dt_mod.addImport("swemplan", swemplan);
        dt_mod.addImport("swejpl", swejpl);
        dt_mod.addImport("sweph", sweph);
        dt_mod.addImport("swecl", swecl);
        dt_mod.addImport("swehouse", swehouse);
        dt_mod.addImport("swehel", swehel);
        dt_mod.addCSourceFile(.{ .file = b.path("src/libmshim.c"), .flags = &.{} });
        dt_mod.link_libc = true;
        const difftest = b.addExecutable(.{ .name = "zig-difftest", .root_module = dt_mod });
        b.installArtifact(difftest);
    }
}
