const std = @import("std");

const c = @import("c.zig");
const global = @import("global.zig");
const input = @import("input.zig");

const width = global.width;
const height = global.height;
const tick_rate = global.tick_rate;

const Item = union(Item.Kind) {
    pub const Kind = enum {
        button,
        number,
    };
    button: []const u8,
    number: i32,
};
const Menu = struct {
    items: [12]?Item = [_]?Item{null} ** 12,
};

var stack: [4]?Menu = [_]?Menu{null} ** 4;
var bg_color: c.Color = undefined;

pub fn init() void {
    bg_color = c.DARKGRAY;
    // push(menu1());
}

pub fn push(new_menu: Menu) void {
    for (stack, 0..) |menu, i| {
        if (menu) |_| continue;
        stack[i] = new_menu;
    }
}

pub fn pop() void {
    for (stack, 0..) |menu, i| {
        if (menu) |_| stack[i] = null;
    }
}

pub fn menu1() Menu {
    var menu = Menu{};
    menu.items[2] = Item{ .button = "play" };
    menu.items[1] = Item{ .button = "online" };
    menu.items[0] = Item{ .button = "settings" };
    return menu;
}

pub fn draw() void {
    // handle ui input
    {
        if (c.IsKeyPressed(c.KEY_ESCAPE)) {
            if (stack[0] == null) {
                push(menu1());
            } else {
                pop();
            }
        }
    }

    for (stack) |menu| {
        if (menu) |m| {
            c.DrawRectangle(0, 0, width, height, bg_color);
            for (m.items, 0..) |item_opt, i| {
                const size = 40;
                const x = 10;
                const y = height - (10 + @as(i32, @intCast(i + 1)) * size);
                if (item_opt) |item| {
                    switch (item) {
                        .button => {
                            // if (ui.button()) {
                            //     // play event
                            // }
                            c.DrawText(@ptrCast(item.button.ptr), x, y, size, c.LIGHTGRAY);
                        },
                        .number => {
                            c.DrawText("number item...", x, y, size, c.LIGHTGRAY);
                        },
                    }
                }
            }
        }
    }
}

var show_dev: bool = true;
// pub fn drawDev(shoba: *Game) void {
//     if (c.IsKeyPressed(c.KEY_ESCAPE)) show_dev = !show_dev;

//     if (show_dev) {
//         var index: f32 = 0;
//         const padding = 4;
//         const row_height = 23;
//         const y_offset = row_height + padding;
//         const wbox = c.Rectangle{
//             .x = 10,
//             .y = 10,
//             .width = 200,
//             .height = 400,
//         };
//         const inner = c.Rectangle{
//             .x = wbox.x + padding,
//             .y = wbox.y + padding + row_height,
//             .width = wbox.width - padding * 2,
//             .height = 20,
//         };
//         show_dev = c.GuiWindowBox(wbox, "dev") != 1;

//         const str = std.fmt.bufPrintZ(global.scratch_buffer, "m: {d}\t{d}", .{ input.mouse.pos.x, input.mouse.pos.y }) catch "";
//         if (c.GuiLabel(c.Rectangle{
//             .x = inner.x,
//             .y = inner.y + index * y_offset,
//             .width = inner.width,
//             .height = row_height,
//         }, @ptrCast(str.ptr)) == 1) {}
//         index += 1;

//         const label_width = 30;
//         const cam = &shoba.state.next.cam;

//         _ = c.GuiSlider(c.Rectangle{
//             .x = inner.x + label_width,
//             .y = inner.y + index * y_offset,
//             .width = inner.width - label_width,
//             .height = row_height,
//         }, "fovy", "", @ptrCast(&cam.fovy), 40, 120);
//         index += 1;

//         var cam_angle: f32 = std.math.atan2(cam.position.z, cam.position.y);
//         var cam_dist: f32 = c.Vector2Length(c.Vector2{ .x = cam.position.z, .y = cam.position.y });
//         // const cam_h = cam_dist * std.math.sin(cam_angle);
//         // var cam_yoff: f32 = cam.position.y - cam_h;

//         if (c.GuiSlider(c.Rectangle{
//             .x = inner.x + label_width,
//             .y = inner.y + index * y_offset,
//             .width = inner.width - label_width,
//             .height = row_height,
//         }, "angle", "", @ptrCast(&cam_angle), 0, std.math.pi / 2.0 - 0.01) == 1) {
//             cam.position.z = cam_dist * std.math.cos(cam_angle);
//             cam.position.y = cam_dist * std.math.sin(cam_angle);
//         }
//         index += 1;

//         if (c.GuiSlider(c.Rectangle{
//             .x = inner.x + label_width,
//             .y = inner.y + index * y_offset,
//             .width = inner.width - label_width,
//             .height = row_height,
//         }, "dist", "", @ptrCast(&cam_dist), 1, 100) == 1) {
//             cam.position.z = cam_dist * std.math.cos(cam_angle);
//             cam.position.y = cam_dist * std.math.sin(cam_angle);
//         }
//         index += 1;

//         // if (c.GuiSlider(c.Rectangle{
//         //     .x = inner.x + label_width,
//         //     .y = inner.y + index * y_offset,
//         //     .width = inner.width - label_width,
//         //     .height = row_height,
//         // }, "y-off", "", @ptrCast(&cam_yoff), 1, 10) == 1) {
//         //     cam.position.y = cam_dist * std.math.sin(cam_angle) - cam_yoff;
//         //     cam.target.y = cam_yoff;
//         // }
//         // index += 1;
//     }
// }
