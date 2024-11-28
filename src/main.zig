const std = @import("std");

const Color = packed struct(u24) { color_in_hex: u24 };

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

    fn is_global_color_tag_set(self: LogicalDescriptor) bool {
        return (self.packed_field & 1) != 0;
    }

    fn color_per_pixel(self: LogicalDescriptor) u8 {
        return @as(u8, (self.packed_field >> 4) & 0b0111) + 1; // shift to the right and mask last 3bits
    }

    fn get_size_of_color_table(self: LogicalDescriptor) usize {
        const n = self.packed_field & 0b00000111;
        const color_count = std.math.pow(usize, 2, n + 1); // 2 ^ (n + 1)
        const size = @bitSizeOf(u24) / 8;
        return size * color_count;
    }
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

const GifParser = struct {
    header: Header = .{},
    logical_descriptor: LogicalDescriptor = .{},
    allocator: std.mem.Allocator = undefined,
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

    pub fn parse(self: *GifParser) void {
        var cursor: usize = @sizeOf(Header);
        self.header = std.mem.bytesToValue(Header, self.data[0..cursor]);
        self.logical_descriptor = std.mem.bytesToValue(LogicalDescriptor, self.data[cursor..@sizeOf(LogicalDescriptor)]);
        cursor += @sizeOf(LogicalDescriptor);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const data = @embedFile("assets/spider-man.gif");
    const alloc = gpa.allocator();
    var parser = GifParser.init(alloc, data);
    parser.parse();
}
