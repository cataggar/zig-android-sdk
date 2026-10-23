const std = @import("std");

pub fn generate(writer: *std.Io.Writer, input: []const u8) !void {
    const package_name = std.mem.trimEnd(u8, input, " \r\n");
    try writer.print("pub const package_name: [:0]const u8 = \"{f}\";\n", .{std.zig.fmtString(package_name)});
}

test "package name output preserves the sentinel and trims aapt line endings" {
    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try generate(&writer, "cataggar.apk2 \r\n");
    try std.testing.expectEqualStrings("pub const package_name: [:0]const u8 = \"cataggar.apk2\";\n", writer.buffered());
}

test "package name output escapes Zig source characters" {
    var buffer: [256]u8 = undefined;
    var writer: std.Io.Writer = .fixed(&buffer);
    try generate(&writer, "a\"\\b\nc\r\n");
    try std.testing.expectEqualStrings("pub const package_name: [:0]const u8 = \"a\\\"\\\\b\\nc\";\n", writer.buffered());
}
