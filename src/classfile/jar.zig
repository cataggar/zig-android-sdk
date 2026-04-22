//! JAR (= ZIP) walker that yields `.class` file bytes to a caller-provided
//! callback. Built on `std.zip` + `std.compress.flate`; supports `store`
//! and `deflate` (the two methods used by every JAR in practice).
//!
//! The callback receives a borrowed slice that aliases a per-entry arena.
//! The arena is reset between entries, so don't retain the slice past the
//! callback return — copy it if you need to keep it.

const std = @import("std");
const zip = std.zip;
const flate = std.compress.flate;

const classfile = @import("classfile.zig");

pub const Entry = struct {
    name: []const u8,
    bytes: []const u8,
};

pub const WalkError = anyerror;

/// Iterate `.class` entries in a JAR. `callback` is invoked once per class
/// entry; return an error from it to abort the walk. Directories and
/// non-`.class` entries are skipped.
pub fn walkClasses(
    gpa: std.mem.Allocator,
    io: std.Io,
    jar_path: []const u8,
    context: anytype,
    comptime callback: fn (ctx: @TypeOf(context), entry: Entry) anyerror!void,
) !void {
    const cwd = std.Io.Dir.cwd();
    var file = try cwd.openFile(io, jar_path, .{ .mode = .read_only });
    defer file.close(io);

    // Large-ish buffer so the Reader doesn't thrash on sequential reads;
    // this also satisfies flate.Decompress's 10-byte minimum requirement.
    var file_read_buf: [64 * 1024]u8 = undefined;
    var fr = file.reader(io, &file_read_buf);

    var it = try zip.Iterator.init(&fr);

    // Reusable buffers across all entries:
    //   - `filename_buf`: max 16-bit ZIP filename length.
    //   - `decomp_window`: flate's sliding window (must be >= flate.max_window_len).
    //   - `entry_arena`: reset between entries; holds the decompressed class bytes.
    var filename_buf: [std.math.maxInt(u16)]u8 = undefined;
    var decomp_window: [flate.max_window_len]u8 = undefined;
    var entry_arena = std.heap.ArenaAllocator.init(gpa);
    defer entry_arena.deinit();

    while (try it.next()) |entry| {
        _ = entry_arena.reset(.retain_capacity);

        // Read the filename (stored right after the central-directory header).
        if (entry.filename_len > filename_buf.len) return error.ZipFilenameTooLong;
        const filename = filename_buf[0..entry.filename_len];
        try fr.seekTo(entry.header_zip_offset + @sizeOf(zip.CentralDirectoryFileHeader));
        try fr.interface.readSliceAll(filename);

        if (!std.mem.endsWith(u8, filename, ".class")) continue;

        const class_bytes = try readEntryBytes(
            &fr,
            &decomp_window,
            entry,
            entry_arena.allocator(),
        );

        try callback(context, .{ .name = filename, .bytes = class_bytes });
    }
}

fn readEntryBytes(
    fr: *std.Io.File.Reader,
    decomp_window: []u8,
    entry: zip.Iterator.Entry,
    arena: std.mem.Allocator,
) ![]u8 {
    // Position at the local header, then skip its variable-length
    // filename + extra fields to reach the actual (compressed) payload.
    try fr.seekTo(entry.file_offset);
    const local = fr.interface.takeStruct(zip.LocalFileHeader, .little) catch |err| switch (err) {
        error.ReadFailed => return fr.err.?,
        error.EndOfStream => return error.ZipTruncated,
    };
    if (!std.mem.eql(u8, &local.signature, &zip.local_file_header_sig)) return error.ZipBadFileOffset;
    try fr.interface.discardAll(@as(u64, local.filename_len) + @as(u64, local.extra_len));

    // Allocate the uncompressed payload in the per-entry arena.
    const out = try arena.alloc(u8, entry.uncompressed_size);

    switch (entry.compression_method) {
        .store => try fr.interface.readSliceAll(out),
        .deflate => {
            // ZIP uses raw DEFLATE (no gzip/zlib header).
            var dec: flate.Decompress = .init(&fr.interface, .raw, decomp_window);
            try dec.reader.readSliceAll(out);
        },
        else => return error.UnsupportedCompressionMethod,
    }
    return out;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test {
    std.testing.refAllDecls(@This());
}
