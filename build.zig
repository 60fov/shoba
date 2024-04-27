const std = @import("std");
const builtin = @import("builtin");
const raylib_build = @import("lib/raylib/src/build.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_client = b.addExecutable(.{
        .name = "shoba-client",
        .root_source_file = .{ .path = "src/client.zig" },
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
    exe_client.addIncludePath(.{ .path = "lib/raylib/src/" });
    exe_client.addCSourceFile(.{
        .file = .{ .path = "src/raygui_impl.c" },
    });
    exe_client.addIncludePath(.{ .path = "lib/raygui/src/" });
    exe_client.linkLibrary(raylib);

    b.installArtifact(exe_client);

    const run_client = b.addRunArtifact(exe_client);
    run_client.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_client.addArgs(args);
    }

    const run_step = b.step("client", "build and run the client");
    run_step.dependOn(&run_client.step);

    const exe_server = b.addExecutable(.{
        .name = "shoba-server",
        .root_source_file = .{ .path = "src/server.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe_server.addIncludePath(.{ .path = "lib/raylib/src/" });
    // TODO remove raylib as server dependency
    exe_server.linkLibrary(raylib);

    const server_build_step = b.step("server", "build the server");
    const server_install = b.addInstallArtifact(exe_server, .{});
    server_build_step.dependOn(&server_install.step);

    const server_run = b.addRunArtifact(exe_server);
    const server_run_step = b.step("serve", "build and run the server");
    server_run.step.dependOn(server_build_step);
    server_run_step.dependOn(&server_run.step);
}
