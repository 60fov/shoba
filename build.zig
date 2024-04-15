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
}
