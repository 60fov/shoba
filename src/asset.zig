const std = @import("std");

const c = @import("c.zig");
const global = @import("global.zig");

const AssetIdHashMap = std.AutoHashMap(AssetId, Asset);
const AssetNameHashMap = std.StringHashMap(AssetId);

var asset_id: AssetId = 0;
var asset_id_table: AssetIdHashMap = undefined;
var asset_name_table: AssetNameHashMap = undefined;

/// doesn't free over-written assets
pub fn load(kind: AssetKind, name: []const u8, options: AssetLoadOptions) !void {
    const asset = switch (kind) {
        .model => Asset{
            .model = options.model,
        },
        .model_animation => Asset{
            .model_animation = options.model_animation,
        },
    };
    try asset_name_table.put(name, asset_id);
    try asset_id_table.put(asset_id, asset);
    asset_id += 1;
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

pub fn init() void {
    asset_name_table = AssetNameHashMap.init(global.mem.fba_allocator);
    asset_id_table = AssetIdHashMap.init(global.mem.fba_allocator);
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

pub const AssetLoadOptions = union(AssetKind) {
    model: Model,
    model_animation: ModelAnimation,
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
        c.UnloadModelAnimations(self.animations.ptr, self.animations.len);
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
