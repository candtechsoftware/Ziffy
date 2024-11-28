const std = @import("std");

const Color = packed struct(u24) {
    r: u8,
    g: u8,
    b: u8,
};

const LogicalDescriptor = packed struct {
    screen_width: u16,
    screen_height: u16,
    packed_field: u8,
    background_color_index: u8,
    pixel_aspect_ratio: u8,

    fn is_global_color_tag_set(self: LogicalDescriptor) bool {
        return (self.packed_field & 1) != 0;
    }

    fn color_per_pixel(self: LogicalDescriptor) u8 {
        return @as(u8, (self.packed_field >> 4) & 0b0111) + 1; // shift to the right and mask last 3bits
    }

    fn get_size_of_color_table(self: LogicalDescriptor) usize {
        const n = self.packed_field & 0b00000111;
        const color_count = std.math.pow(usize, 2, n + 1); // 2 ^ (n + 1)
        const size = @bitSizeOf(Color) / 8;
        return size * color_count;
    }
};

const GifParser = struct {
    signature: [6]u8,
    logical_descriptor: LogicalDescriptor,
    cursor: usize,
    data: []const u8,

    pub fn init(data: []const u8) !GifParser {
        const signature = data[0..6];
        const size = @sizeOf(LogicalDescriptor);
        const logical_descriptor = std.mem.bytesToValue(LogicalDescriptor, data[6..size]);

        return .{
            .signature = signature.*,
            .logical_descriptor = logical_descriptor,
            .cursor = signature.len + size,
            .data = data[(signature.len + size - 1)..],
        };
    }
};

pub fn main() !void {
    const data = @embedFile("assets/spider-man.gif");
    const parser = try GifParser.init(data);
    std.debug.print("logical_descriptor {any}\n", .{parser.logical_descriptor.get_size_of_color_table()});
}
