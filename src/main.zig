const std = @import("std");
const c = @import("c.zig");
const global = @import("global.zig");

pub fn main() void {
    const width = 800;
    const height = 600;

    const allocator = std.heap.page_allocator;
    global.init(allocator) catch unreachable;
    defer global.deinit(allocator);

    c.InitWindow(800, 600, "zig-raylib");
    defer c.CloseWindow();

    c.SetTargetFPS(165);

    const cam: c.Camera3D = .{
        .fovy = 60.0,
        .up = .{ .y = 1 },
        .target = .{ .y = 1 },
        .position = .{ .y = 7, .z = -7 },
        .projection = c.CAMERA_PERSPECTIVE,
    };

    const fb: c.RenderTexture = c.LoadRenderTexture(width, height);
    defer c.UnloadRenderTexture(fb);

    const src = c.Rectangle{ .width = width, .height = -height };
    const dst = c.Rectangle{ .width = width, .height = height };
    const cube_pos: c.Vector3 = .{ .x = 1, .y = 1, .z = 0 };

    const dev_model = c.LoadModel("assets/dev_model_1.obj");

    while (!c.WindowShouldClose()) {
        c.BeginTextureMode(fb);
        {
            c.ClearBackground(c.LIGHTGRAY);

            c.BeginMode3D(cam);
            {
                c.DrawGrid(10, 1.0);

                // unit axis
                c.DrawLine3D(.{}, .{ .x = 1 }, c.RED);
                c.DrawLine3D(.{}, .{ .y = 1 }, c.GREEN);
                c.DrawLine3D(.{}, .{ .z = 1 }, c.BLUE);

                c.DrawCubeV(cube_pos, .{ .x = 1, .y = 1, .z = 1 }, c.RED);
                c.DrawCubeWiresV(cube_pos, .{ .x = 1, .y = 1, .z = 1 }, c.MAROON);

                c.DrawModel(dev_model, .{}, 1, c.WHITE);
                c.DrawModelWires(dev_model, .{}, 1, c.LIGHTGRAY);
            }
            c.EndMode3D();
        }
        c.EndTextureMode();

        c.BeginDrawing();
        {
            c.ClearBackground(c.BLACK);
            c.DrawTexturePro(fb.texture, src, dst, .{}, 0, c.WHITE);

            c.DrawFPS(10, 10);
        }
        c.EndDrawing();
    }
}
