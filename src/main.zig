const std = @import("std");

const GifHeader = extern struct {
    signature: [6]u8,
    screen_width: u16,
    screen_height: u16,
    packed_field: u8,
    background_color_index: u8,
    pixel_aspect_ratio: u8,

    fn is_global_color_tag_set(self: GifHeader) bool {
        return (self.packed_field & 1) != 0;
    }

    fn color_per_pixel(self: GifHeader) u8  {
        return  @as(u8, (self.packed_field >> 4) & 0b0111) + 1; // shift to the right and mask last 3bits
    }

    fn get_size_of_color_table(self: GifHeader) usize {
        const n = self.packed_field & 0b00000111;
        return std.math.pow(usize, 2, n + 1) - 1; // 2 ^ (n + 1)
    }

};

pub fn main() !void {
    const gif_data = @embedFile("assets/spider-man.gif");
    const header = std.mem.bytesAsValue(GifHeader, gif_data);
    std.debug.print("intCastata: {any} type: {s}\n", .{ header, header.signature });
    std.debug.print("packed: {b} global: {any} color_per_pixel {d}\n size of color table {d} ", .{ header.packed_field, header.is_global_color_tag_set(), header.color_per_pixel(), header.get_size_of_color_table() });
}
