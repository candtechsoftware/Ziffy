const std = @import("std");
const builtin = @import("builtin");

const ParserError = error{
    TagError,
    VersionError,
    KindError,
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
const ExtBlockTerminator = 0x00;

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
const BlockKind = enum(u8) {
    image_descriptor = 0x2c,
    ext = 0x21,
    eof = 0x3b,
};

const ExtKind = enum(u8) {
    graphic_control = 0xf9,
    comment = 0xfe,
    plain_text = 0x01,
    app_ext = 0xff,
};

const ApplicationExtSignature = extern struct {
    ident: [8]u8,
    auth_code: [3]u8,
};

const ApplicationExt = struct {
    sig: ApplicationExtSignature,
    data: []u8,

    pub fn deinit(self: *ApplicationExt, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

const DisposalMethod = enum(u3) {
    none = 0,
    do_not_dispose = 1,
    restore_background_color = 2,
    restore_previous = 3,
    _,
};
const GraphicControlExtFlags = packed struct(u8) {
    has_transparent_color: bool = false,
    user_input: bool = false,
    disposal_method: DisposalMethod = .none,
    reversed: u3 = 0,
};

const GraphicControlExt = extern struct {
    flags: GraphicControlExtFlags align(1) = .{},
    delay: u16 align(1) = 0,
    transparent_index: u8 align(1) = 0,
};

const ImageDescriptorFlags = packed struct(u8) {
    local_color_table_size: u3 = 0,
    has_local_color_table: bool = false,
    is_interlaced: bool = false,
    reseverd: u2 = 0,
    sort: bool = false,
};

const Comment = struct {
    comment: []u8,

    pub fn denit(self: *Comment, allocator: std.mem.Allocator) void {
        allocator.free(self.comment);
    }
};

const ImageDescriptor = struct {
    left_pos: u16 align(1) = 0,
    top_pos: u16 align(1) = 0,
    width: u16 align(1) = 0,
    height: u16 align(1) = 0,
    flags: ImageDescriptorFlags align(1) = .{},
};
const SubBlock = struct {
    local_color_table: FixedArray(Rgb24, 256) = .{},
    image_descriptor: ImageDescriptor = .{},
    pixels: []u8 = &.{},
};
const Frame = struct { graphics_control: ?GraphicControlExt = null, sub_block: std.ArrayListUnmanaged(SubBlock) = .{} };

const GifParser = struct {
    header: Header = .{},
    logical_descriptor: LogicalDescriptor = .{},
    allocator: std.mem.Allocator = undefined,
    global_color_table: FixedArray(Rgb24, 256) = .{},
    data: []const u8,
    cursor: usize,
    current_frame: ?*Frame = null,
    has_anitmation_app_ext: bool = false,
    frames: std.ArrayListUnmanaged(Frame) = .{},
    comments: std.ArrayListUnmanaged(Comment) = .{},

    pub fn init(allocator: std.mem.Allocator, data: []const u8) GifParser {
        return .{
            .data = data,
            .allocator = allocator,
            .cursor = 0,
        };
    }

    pub fn deinit(self: *GifParser) void {
        // TODO(alex): need to actually deallocate things
        _ = self;
    }

    fn alloc_frame(self: *GifParser) !*Frame {
        const frame = try self.frames.addOne(self.allocator);
        frame.* = Frame{};
        return frame;
    }

    pub fn parse(self: *GifParser) anyerror!void {
        self.cursor = @sizeOf(Header);
        self.header = std.mem.bytesToValue(Header, self.data[0..self.cursor]);
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

        self.logical_descriptor = std.mem.bytesToValue(LogicalDescriptor, self.data[self.cursor..@sizeOf(LogicalDescriptor)]);
        self.cursor += @sizeOf(LogicalDescriptor);

        const global_color_table_size = @as(usize, 1) << (@as(ColorTableShiftSize, @intCast(self.logical_descriptor.flags.global_color_table_size)) + 1);
        self.global_color_table.resize(global_color_table_size);

        if (self.logical_descriptor.flags.use_global_color_table) {
            var idx: usize = 0;

            while (idx < global_color_table_size) : (idx += 1) {
                self.global_color_table.data[idx] = std.mem.bytesToValue(Rgb24, self.data[self.cursor .. self.cursor + 2]);
                std.debug.print("Color: {any} indx {d} \n", .{ self.global_color_table.data[idx], idx });
                self.cursor += 3;
            }
        }
        try self.read_data();
    }

    fn read_data(self: *GifParser) anyerror!void {
        var current_block = try byteToEnum(BlockKind, self.data[self.cursor]);
        self.cursor += 1;
        while (current_block != .eof) {
            var is_graphic_block = false;
            var ext_kind: ?ExtKind = null;
            switch (current_block) {
                .image_descriptor => {
                    is_graphic_block = true;
                },
                .ext => {
                    std.debug.print("Here {any}\n", .{ext_kind});
                    ext_kind = byteToEnum(ExtKind, self.data[self.cursor]) catch blk: {
                        var tmp = self.data[self.cursor];
                        self.cursor += 1;
                        while (tmp != ExtBlockTerminator) {
                            tmp = self.data[self.cursor];
                            self.cursor += 1;
                        }
                        break :blk null;
                    };
                    std.debug.print("after {any}\n", .{ext_kind});
                    self.cursor += 1;

                    if (ext_kind) |kind| {
                        switch (kind) {
                            .graphic_control, .plain_text => {
                                is_graphic_block = true;
                            },
                            else => {},
                        }
                    } else {
                        std.debug.print("IN HERE DATA {any}\n", .{self.data[self.cursor..(self.cursor + 20)]});
                        current_block = try byteToEnum(BlockKind, self.data[self.cursor]);
                        continue;
                    }
                },
                .eof => {
                    break;
                },
            }
            std.debug.print("after all {any}\n", .{ext_kind});
            if (is_graphic_block) {
                std.debug.print("Graphics Block! {any}\n", .{current_block});
                try self.read_graphics_block(current_block, ext_kind);
            } else {
                std.debug.print("Not Graphics Block {any}\n", .{current_block});
                try self.read_non_graphics_block(ext_kind.?);
            }
        }
    }

    fn read_non_graphics_block(self: *GifParser, ext_kind: ExtKind) !void {
        std.debug.print("Non g func {any} \n", .{ext_kind});
        switch (ext_kind) {
            .comment => {
                var new_comment = try self.comments.addOne(self.allocator);
                var comment_list = try std.ArrayListUnmanaged(u8).initCapacity(self.allocator, 256);
                defer comment_list.deinit(self.allocator);

                var block_size = self.data[self.cursor];
                self.cursor += 1;

                while (block_size > 0) {
                    var block: []const u8 = undefined;
                    block = self.data[self.cursor .. self.cursor + block_size];
                    self.cursor += block_size;
                    try comment_list.appendSlice(self.allocator, block[0..]);
                    block_size = self.data[self.cursor];
                    self.cursor += 1;
                }
                new_comment.comment = try self.allocator.dupe(u8, comment_list.items);
                std.debug.print("Comment {s}", .{new_comment.comment});
            },
            .app_ext => {
                const new_app_info = blk: {
                    var app_info: ApplicationExt = undefined;
                    var app_sig: ApplicationExtSignature = undefined;
                    self.cursor += 1;

                    const sig_size = @sizeOf(ApplicationExtSignature);
                    app_sig = std.mem.bytesToValue(ApplicationExtSignature, self.data[self.cursor..self.cursor + sig_size]);
                    self.cursor += sig_size;

                    app_info.sig = app_sig;

                    std.debug.print("App info: id: {s} :: auth: {s}\n", .{app_info.sig.ident, app_info.sig.auth_code});

                    break :blk app_info;
                };
                _ = new_app_info;
            },
            else => {
                std.debug.print("EXT kind:: {any}", .{ext_kind});
            },
        }
    }

    fn read_graphics_block(self: *GifParser, block_kind: BlockKind, ext_kind: ?ExtKind) !void {
        if (ext_kind) |kind| {
            if (kind == .graphic_control) {
                std.debug.print("HERE:: {any} ::  {any} \n", .{ self.data[self.cursor..(self.cursor + 100)], block_kind });
                self.current_frame = try self.alloc_frame();
                std.debug.print("out!Q ", .{});
                self.current_frame.?.graphics_control = blk: {
                    std.debug.print("in:: ", .{});
                    var control: GraphicControlExt = undefined;
                    // eat block_size
                    self.cursor += 1;

                    control.flags = std.mem.bytesToValue(GraphicControlExtFlags, self.data[self.cursor..@sizeOf(GraphicControlExtFlags)]);
                    self.cursor += @sizeOf(GraphicControlExtFlags);
                    control.delay = std.mem.bytesToValue(u16, self.data[self.cursor .. self.cursor + 1]);
                    self.cursor += 2;
                    std.debug.print("control: {any}", .{control});

                    break :blk control;
                };
            }
        }
    }
};

fn byteToEnum(comptime T: type, byte: u8) ParserError!T {
    const info = @typeInfo(T);
    switch (info) {
        .Enum => |e| {
            inline for (e.fields) |f| {
                if (f.value == byte) {
                    return @field(T, f.name);
                }
            }
        },
        else => return ParserError.KindError,
    }
    return ParserError.KindError;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const data = @embedFile("assets/spider-man.gif");
    const alloc = gpa.allocator();
    var parser = GifParser.init(alloc, data);
    try parser.parse();
    //  for (data, 0..) |b, i| {
    //      if (std.mem.eql(u8, &[_]u8{0x2c}, &[_]u8{b}) or std.mem.eql(u8, &[_]u8{0x21}, &[_]u8{b})) {
    //          std.debug.print("byte index {any} {any} \n", .{ i, b });
    //          counter -= 1;
    //          if (counter == 0) {
    //              break;
    //          }
    //      g
    //  }
}
