const std = @import("std");
const builtin = @import("builtin");
const raylib_build = @import("lib/raylib/src/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "shoba",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const install_step = b.getInstallStep();
    const install_asset_dir = b.addInstallDirectory(.{
        .source_dir = .{ .path = "assets" },
        .install_subdir = "assets",
        .install_dir = .{ .bin = {} },
    });
    install_step.dependOn(&install_asset_dir.step);

    const raylib = try raylib_build.addRaylib(b, target, optimize, .{});
    // raylib.defineCMacro("SUPPORT_CUSTOM_FRAME_CONTROL", null);
    if (builtin.target.os.tag == .linux) {
        raylib.root_module.addCMacro("_GLFW_X11", "");
    }
    exe.addIncludePath(.{ .path = "lib/raylib/src/" });
    exe.addCSourceFile(.{
        .file = .{ .path = "src/raygui_impl.c" },
    });
    exe.addIncludePath(.{ .path = "lib/raygui/src/" });
    exe.linkLibrary(raylib);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const server_exe = b.addExecutable(.{
        .name = "server",
        .root_source_file = .{ .path = "src/server.zig" },
        .target = target,
        .optimize = optimize,
    });
    server_exe.addIncludePath(.{ .path = "lib/raylib/src/" });
    server_exe.linkLibrary(raylib);

    const server_build_step = b.step("server", "build the server");
    const server_install = b.addInstallArtifact(server_exe, .{});
    server_build_step.dependOn(&server_install.step);

    const server_run = b.addRunArtifact(server_exe);
    const server_run_step = b.step("serve", "build and run the server");
    server_run.step.dependOn(server_build_step);
    server_run_step.dependOn(&server_run.step);
}
