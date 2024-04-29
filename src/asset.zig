const std = @import("std");
const builtin = @import("builtin");

const c = @import("c.zig");
const global = @import("global.zig");

const AssetIdHashMap = std.AutoHashMap(AssetId, Asset);
const AssetNameHashMap = std.StringHashMap(AssetId);

var asset_id: AssetId = 0;
var asset_id_table: AssetIdHashMap = undefined;
var asset_name_table: AssetNameHashMap = undefined;

pub const asset_file_list = [_]AssetLoadInfo{
    .{ .name = "daniel", .kind = .model, .path = "assets/daniel.glb" },
    .{ .name = "idle_anim", .kind = .model_animation, .path = "assets/daniel.glb" },
    .{ .name = "dev_ground", .kind = .model, .path = "assets/dev_ground.glb" },
};

pub fn openAssetDir(allocator: std.mem.Allocator) !std.fs.Dir {
    if (builtin.mode == .Debug) {
        return try std.fs.cwd().openDir("assets", .{});
    } else {
        const exe_path = try std.fs.selfExeDirPathAlloc(allocator);
        defer allocator.free(exe_path);

        const asset_dir_path = try std.fs.path.join(allocator, &.{ exe_path, "assets" });
        defer allocator.free(asset_dir_path);

        return try std.fs.openDirAbsolute(asset_dir_path, .{});
    }
}

/// doesn't free over-written assets
pub fn loadAssets() !void {
    for (asset_file_list) |asset_info| {
        const asset = switch (asset_info.kind) {
            .model => Asset{
                .model = Model.init(asset_info.path),
            },
            .model_animation => Asset{
                .model_animation = ModelAnimation.init(asset_info.path),
            },
        };
        try asset_name_table.put(asset_info.name, asset_id);
        try asset_id_table.put(asset_id, asset);
        asset_id += 1;
    }
}

/// TODO?
// pub fn unload() void {}

pub fn getId(name: []const u8) AssetId {
    return asset_name_table.get(name).?;
}

pub fn getById(id: AssetId) Asset {
    return asset_id_table.get(id).?;
}

pub fn getByName(name: []const u8) Asset {
    return getById(getId(name));
}

pub fn init(allocator: std.mem.Allocator) void {
    asset_name_table = AssetNameHashMap.init(allocator);
    asset_id_table = AssetIdHashMap.init(allocator);
}

pub fn deinit() void {
    asset_name_table.deinit();
    asset_id_table.deinit();
}

// ASSET
pub const AssetId = u32;

pub const AssetKind = enum {
    model,
    model_animation,
};

pub const AssetLoadInfo = struct {
    kind: AssetKind,
    name: []const u8,
    path: []const u8,
};

pub const Asset = union(AssetKind) {
    model: Model,
    model_animation: ModelAnimation,
};

// MODEL
pub const Model = struct {
    rl_model: c.Model = undefined,

    pub fn init(path: []const u8) Model {
        return Model{
            .rl_model = c.LoadModel(@ptrCast(path)),
        };
    }

    pub fn deinit(self: *Model) void {
        c.UnloadModel(self.rl_model);
        self.* = undefined;
    }
};

pub const ModelAnimation = struct {
    animations: [*c]c.ModelAnimation = undefined,
    animation_count: u32 = 0,

    pub fn init(path: []const u8) ModelAnimation {
        var anim_count: c_int = 0;
        const animations = c.LoadModelAnimations(@ptrCast(path), &anim_count);
        return ModelAnimation{
            .animations = animations,
            .animation_count = @intCast(anim_count),
        };
    }

    pub fn deinit(self: *ModelAnimation) void {
        c.UnloadModelAnimations(self.animations.ptr, @intCast(self.animation_count));
        self.* = undefined;
    }
};

pub const ModelAnimationState = struct {
    ani_ndx: u32 = 0,
    ani_frame: i32 = 0,

    pub fn setById(self: *ModelAnimation, ndx: u32) void {
        self.ani_ndx = ndx;
    }

    // TODO?
    // pub fn setByName(self: *ModelAnimation, name: []const u8) void {}

    pub fn animateModel(self: *ModelAnimationState, model: *Model, model_animation: *const ModelAnimation) void {
        const animation = model_animation.animations[self.ani_ndx];
        self.ani_frame = @mod((self.ani_frame + 1), animation.frameCount);
        c.UpdateModelAnimation(model.rl_model, animation, self.ani_frame);
    }
};

// const AssetManager = struct {
//     const Self = @This();

//     asset_id: AssetId = 0,
//     id_table: AssetIdHashMap = undefined,
//     name_table: AssetNameHashMap = undefined,

//     pub fn getId(self: *const Self, name: []const u8) AssetId {
//         return self.name_table.get(name).?;
//     }

//     pub fn getById(self: *const Self, id: AssetId) Asset {
//         return self.id_table.get(id).?;
//     }

//     pub fn getByName(self: *const Self, name: []const u8) Asset {
//         return self.getById(getId(name));
//     }

//     pub fn init(allocator: std.mem.Allocator) void {
//         asset_name_table = AssetNameHashMap.init(allocator);
//         asset_id_table = AssetIdHashMap.init(allocator);
//     }

//     pub fn deinit() void {
//         asset_name_table.deinit();
//         asset_id_table.deinit();
//     }
// };
