const std = @import("std");

const ParserError = error{
    TagError,
    VersionError,
};

const LogicalDescriptorFlags = packed struct {
    global_color_table_size: u3 = 0,
    sorted: bool = false,
    color_resolution: u3 = 0,
    use_global_color_table: bool = false,
};

const LogicalDescriptor = extern struct {
    screen_width: u16 align(1) = 0,
    screen_height: u16 align(1) = 0,
    flags: LogicalDescriptorFlags align(1) = .{},
    background_color_index: u8 align(1) = 0,
    pixel_aspect_ratio: u8 align(1) = 0,
};

const Header = extern struct {
    tag: [3]u8 align(1) = undefined,
    version: [3]u8 align(1) = undefined,
};

const TAG = "GIF";
const VERSIONS = [_][]const u8{
    "87a",
    "89a",
};

const ColorTableShiftSize = if (@sizeOf(usize) == 4) u5 else u6;

fn Color(comptime T: type) type {
    return extern struct {
        r: T align(1),
        g: T align(1),
        b: T align(1),
    };
}

pub const Rgb24 = Color(u8);

fn FixedArray(comptime T: type, comptime storage_size: usize) type {
    return struct {
        data: []T = &.{},
        storage: [storage_size]T = undefined,

        const Self = @This();

        pub fn resize(self: *Self, size: usize) void {
            self.data = self.storage[0..size];
        }
    };
}

const GifParser = struct {
    header: Header = .{},
    logical_descriptor: LogicalDescriptor = .{},
    allocator: std.mem.Allocator = undefined,
    global_color_table: FixedArray(Rgb24, 256) = .{},
    data: []const u8,

    pub fn init(allocator: std.mem.Allocator, data: []const u8) GifParser {
        return .{
            .data = data,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *GifParser) void {
        // TODO(alex): need to actually deallocate things
        _ = self;
    }

    pub fn parse(self: *GifParser) ParserError!void {
        var cursor: usize = @sizeOf(Header);
        self.header = std.mem.bytesToValue(Header, self.data[0..cursor]);
        if (!std.mem.eql(u8, self.header.tag[0..], TAG)) {
            return ParserError.TagError;
        }

        var valid_version = false;

        for (VERSIONS) |v| {
            if (std.mem.eql(u8, self.header.version[0..], v)) {
                valid_version = true;
            }
        }

        if (!valid_version) {
            return ParserError.VersionError;
        }

        self.logical_descriptor = std.mem.bytesToValue(LogicalDescriptor, self.data[cursor..@sizeOf(LogicalDescriptor)]);

        const global_color_table_size = @as(usize, 1) << (@as(ColorTableShiftSize, @intCast(self.logical_descriptor.flags.global_color_table_size)) + 1);
        self.global_color_table.resize(global_color_table_size);

        if (self.logical_descriptor.flags.use_global_color_table) {
            var idx: usize = 0;

            while (idx < global_color_table_size) : (idx += 1) {
                self.global_color_table.data[idx] = std.mem.bytesToValue(Rgb24, self.data[cursor .. cursor + 2]);
                cursor += 2;
            }
        }



        cursor += @sizeOf(LogicalDescriptor);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const data = @embedFile("assets/spider-man.gif");
    const alloc = gpa.allocator();
    var parser = GifParser.init(alloc, data);
    try parser.parse();
}
