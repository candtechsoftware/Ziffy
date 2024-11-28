const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const opts = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ws_server",
        .root_source_file = b.path("src/main.zig"),
        .optimize = opts,
        .target = target,
    });

    b.installArtifact(exe);
}
