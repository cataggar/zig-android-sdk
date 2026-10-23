const std = @import("std");
const generator = @import("builtin_generator.zig");

pub fn main(init: std.process.Init) !void {
    var args = try init.minimal.args.iterateAllocator(init.gpa);
    defer args.deinit();
    _ = args.next();
    const input_path = args.next() orelse return error.MissingPackageNameFile;
    if (args.next() != null) return error.UnexpectedArgument;
    const input = try std.Io.Dir.cwd().readFileAlloc(init.io, input_path, init.gpa, .limited(8192));
    defer init.gpa.free(input);
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    try generator.generate(&writer.interface, input);
    try writer.interface.flush();
}
