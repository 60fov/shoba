const std = @import("std");
const builtin = @import("builtin");
const raylib_build = @import("lib/raylib/src/build.zig");

const targets: []const std.Target.Query = &.{
    // .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
    // .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    // .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
};

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
    if (target.result.os.tag == .linux) {
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

    const cross_build_step = b.step("all", "cross compile client & server");
    cross_build_step.dependOn(server_build_step);
    cross_build_step.dependOn(b.getInstallStep());

    for (targets) |t| {
        const target_result = b.resolveTargetQuery(t);
        const client = b.addExecutable(.{
            .name = exe_client.name,
            .root_source_file = .{ .path = "src/client.zig" },
            .target = target_result,
            .optimize = optimize,
        });

        const target_raylib = try raylib_build.addRaylib(b, target_result, optimize, .{});
        if (target_result.result.os.tag == .linux) {
            target_raylib.root_module.addCMacro("_GLFW_X11", "");
        }

        client.addIncludePath(.{ .path = "lib/raylib/src/" });
        client.addCSourceFile(.{
            .file = .{ .path = "src/raygui_impl.c" },
        });
        client.addIncludePath(.{ .path = "lib/raygui/src/" });
        client.linkLibrary(target_raylib);

        const client_output = b.addInstallArtifact(client, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        const server = b.addExecutable(.{
            .name = "shoba-server",
            .root_source_file = .{ .path = "src/server.zig" },
            .target = target_result,
            .optimize = optimize,
        });
        server.addIncludePath(.{ .path = "lib/raylib/src/" });
        // TODO remove raylib as server dependency
        server.linkLibrary(target_raylib);

        const server_output = b.addInstallArtifact(server, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        cross_build_step.dependOn(&install_asset_dir.step);
        cross_build_step.dependOn(&client_output.step);
        cross_build_step.dependOn(&server_output.step);
    }
}
