const std = @import("std");
const tar = @import("../tar.zig");
const testing = std.testing;

const Case = struct {
    const File = struct {
        name: []const u8,
        size: u64 = 0,
        mode: u32 = 0,
        link_name: []const u8 = &[0]u8{},
        kind: tar.FileKind = .file,
        truncated: bool = false, // when there is no file body, just header, useful for huge files
    };

    data: []const u8, // testdata file content
    files: []const File = &[_]@This().File{}, // expected files to found in archive
    chksums: []const []const u8 = &[_][]const u8{}, // chksums of each file content
    err: ?anyerror = null, // parsing should fail with this error
};

const gnu_case: Case = .{
    .data = @embedFile("testdata/gnu.tar"),
    .files = &[_]Case.File{
        .{
            .name = "small.txt",
            .size = 5,
            .mode = 0o640,
        },
        .{
            .name = "small2.txt",
            .size = 11,
            .mode = 0o640,
        },
    },
    .chksums = &[_][]const u8{
        "e38b27eaccb4391bdec553a7f3ae6b2f",
        "c65bd2e50a56a2138bf1716f2fd56fe9",
    },
};

const gnu_multi_headers_case: Case = .{
    .data = @embedFile("testdata/gnu-multi-hdrs.tar"),
    .files = &[_]Case.File{
        .{
            .name = "GNU2/GNU2/long-path-name",
            .link_name = "GNU4/GNU4/long-linkpath-name",
            .kind = .sym_link,
        },
    },
};

const trailing_slash_case: Case = .{
    .data = @embedFile("testdata/trailing-slash.tar"),
    .files = &[_]Case.File{
        .{
            .name = "123456789/" ** 30,
            .kind = .directory,
        },
    },
};

const writer_big_long_case: Case = .{
    // Size in gnu extended format, and name in pax attribute.
    .data = @embedFile("testdata/writer-big-long.tar"),
    .files = &[_]Case.File{
        .{
            .name = "longname/" ** 15 ++ "16gig.txt",
            .size = 16 * 1024 * 1024 * 1024,
            .mode = 0o644,
            .truncated = true,
        },
    },
};

const fuzz1_case: Case = .{
    .data = @embedFile("testdata/fuzz1.tar"),
    .err = error.TarInsufficientBuffer,
};

test "run test cases" {
    try testCase(gnu_case);
    try testCase(.{
        .data = @embedFile("testdata/sparse-formats.tar"),
        .err = error.TarUnsupportedHeader,
    });
    try testCase(.{
        .data = @embedFile("testdata/star.tar"),
        .files = &[_]Case.File{
            .{
                .name = "small.txt",
                .size = 5,
                .mode = 0o640,
            },
            .{
                .name = "small2.txt",
                .size = 11,
                .mode = 0o640,
            },
        },
        .chksums = &[_][]const u8{
            "e38b27eaccb4391bdec553a7f3ae6b2f",
            "c65bd2e50a56a2138bf1716f2fd56fe9",
        },
    });
    try testCase(.{
        .data = @embedFile("testdata/v7.tar"),
        .files = &[_]Case.File{
            .{
                .name = "small.txt",
                .size = 5,
                .mode = 0o444,
            },
            .{
                .name = "small2.txt",
                .size = 11,
                .mode = 0o444,
            },
        },
        .chksums = &[_][]const u8{
            "e38b27eaccb4391bdec553a7f3ae6b2f",
            "c65bd2e50a56a2138bf1716f2fd56fe9",
        },
    });
    try testCase(.{
        .data = @embedFile("testdata/pax.tar"),
        .files = &[_]Case.File{
            .{
                .name = "a/123456789101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899100",
                .size = 7,
                .mode = 0o664,
            },
            .{
                .name = "a/b",
                .size = 0,
                .kind = .sym_link,
                .mode = 0o777,
                .link_name = "123456789101112131415161718192021222324252627282930313233343536373839404142434445464748495051525354555657585960616263646566676869707172737475767778798081828384858687888990919293949596979899100",
            },
        },
        .chksums = &[_][]const u8{
            "3c382e8f5b6631aa2db52643912ffd4a",
        },
    });
    try testCase(.{
        // pax attribute don't end with \n
        .data = @embedFile("testdata/pax-bad-hdr-file.tar"),
        .err = error.PaxInvalidAttributeEnd,
    });
    try testCase(.{
        // size is in pax attribute
        .data = @embedFile("testdata/pax-pos-size-file.tar"),
        .files = &[_]Case.File{
            .{
                .name = "foo",
                .size = 999,
                .kind = .file,
                .mode = 0o640,
            },
        },
        .chksums = &[_][]const u8{
            "0afb597b283fe61b5d4879669a350556",
        },
    });
    try testCase(.{
        // has pax records which we are not interested in
        .data = @embedFile("testdata/pax-records.tar"),
        .files = &[_]Case.File{
            .{
                .name = "file",
            },
        },
    });
    try testCase(.{
        // has global records which we are ignoring
        .data = @embedFile("testdata/pax-global-records.tar"),
        .files = &[_]Case.File{
            .{
                .name = "file1",
            },
            .{
                .name = "file2",
            },
            .{
                .name = "file3",
            },
            .{
                .name = "file4",
            },
        },
    });
    try testCase(.{
        .data = @embedFile("testdata/nil-uid.tar"),
        .files = &[_]Case.File{
            .{
                .name = "P1050238.JPG.log",
                .size = 14,
                .kind = .file,
                .mode = 0o664,
            },
        },
        .chksums = &[_][]const u8{
            "08d504674115e77a67244beac19668f5",
        },
    });
    try testCase(.{
        // has xattrs and pax records which we are ignoring
        .data = @embedFile("testdata/xattrs.tar"),
        .files = &[_]Case.File{
            .{
                .name = "small.txt",
                .size = 5,
                .kind = .file,
                .mode = 0o644,
            },
            .{
                .name = "small2.txt",
                .size = 11,
                .kind = .file,
                .mode = 0o644,
            },
        },
        .chksums = &[_][]const u8{
            "e38b27eaccb4391bdec553a7f3ae6b2f",
            "c65bd2e50a56a2138bf1716f2fd56fe9",
        },
    });
    try testCase(gnu_multi_headers_case);
    try testCase(.{
        // has gnu type D (directory) and S (sparse) blocks
        .data = @embedFile("testdata/gnu-incremental.tar"),
        .err = error.TarUnsupportedHeader,
    });
    try testCase(.{
        // should use values only from last pax header
        .data = @embedFile("testdata/pax-multi-hdrs.tar"),
        .files = &[_]Case.File{
            .{
                .name = "bar",
                .link_name = "PAX4/PAX4/long-linkpath-name",
                .kind = .sym_link,
            },
        },
    });
    try testCase(.{
        .data = @embedFile("testdata/gnu-long-nul.tar"),
        .files = &[_]Case.File{
            .{
                .name = "0123456789",
                .mode = 0o644,
            },
        },
    });
    try testCase(.{
        .data = @embedFile("testdata/gnu-utf8.tar"),
        .files = &[_]Case.File{
            .{
                .name = "☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹☺☻☹",
                .mode = 0o644,
            },
        },
    });
    try testCase(.{
        .data = @embedFile("testdata/gnu-not-utf8.tar"),
        .files = &[_]Case.File{
            .{
                .name = "hi\x80\x81\x82\x83bye",
                .mode = 0o644,
            },
        },
    });
    try testCase(.{
        // null in pax key
        .data = @embedFile("testdata/pax-nul-xattrs.tar"),
        .err = error.PaxNullInKeyword,
    });
    try testCase(.{
        .data = @embedFile("testdata/pax-nul-path.tar"),
        .err = error.PaxNullInValue,
    });
    try testCase(.{
        .data = @embedFile("testdata/neg-size.tar"),
        .err = error.TarHeader,
    });
    try testCase(.{
        .data = @embedFile("testdata/issue10968.tar"),
        .err = error.TarHeader,
    });
    try testCase(.{
        .data = @embedFile("testdata/issue11169.tar"),
        .err = error.TarHeader,
    });
    try testCase(.{
        .data = @embedFile("testdata/issue12435.tar"),
        .err = error.TarHeaderChksum,
    });
    try testCase(.{
        // has magic with space at end instead of null
        .data = @embedFile("testdata/invalid-go17.tar"),
        .files = &[_]Case.File{
            .{
                .name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/foo",
            },
        },
    });
    try testCase(.{
        .data = @embedFile("testdata/ustar-file-devs.tar"),
        .files = &[_]Case.File{
            .{
                .name = "file",
                .mode = 0o644,
            },
        },
    });
    try testCase(trailing_slash_case);
    try testCase(.{
        // Has size in gnu extended format. To represent size bigger than 8 GB.
        .data = @embedFile("testdata/writer-big.tar"),
        .files = &[_]Case.File{
            .{
                .name = "tmp/16gig.txt",
                .size = 16 * 1024 * 1024 * 1024,
                .truncated = true,
                .mode = 0o640,
            },
        },
    });
    try testCase(writer_big_long_case);
    try testCase(fuzz1_case);
    try testCase(.{
        .data = @embedFile("testdata/fuzz2.tar"),
        .err = error.PaxSizeAttrOverflow,
    });
}

fn testCase(case: Case) !void {
    var file_name_buffer: [std.fs.max_path_bytes]u8 = undefined;
    var link_name_buffer: [std.fs.max_path_bytes]u8 = undefined;

    var br: std.io.Reader = .fixed(case.data);
    var it: tar.Iterator = .init(&br, .{
        .file_name_buffer = &file_name_buffer,
        .link_name_buffer = &link_name_buffer,
    });
    var i: usize = 0;
    while (it.next() catch |err| {
        if (case.err) |e| {
            try testing.expectEqual(e, err);
            return;
        } else {
            return err;
        }
    }) |actual| : (i += 1) {
        const expected = case.files[i];
        try testing.expectEqualStrings(expected.name, actual.name);
        try testing.expectEqual(expected.size, actual.size);
        try testing.expectEqual(expected.kind, actual.kind);
        try testing.expectEqual(expected.mode, actual.mode);
        try testing.expectEqualStrings(expected.link_name, actual.link_name);

        if (case.chksums.len > i) {
            var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
            defer aw.deinit();
            try it.streamRemaining(actual, &aw.writer);
            const chksum = std.fmt.bytesToHex(std.crypto.hash.Md5.hashResult(aw.getWritten()), .lower);
            try testing.expectEqualStrings(case.chksums[i], &chksum);
        } else {
            if (expected.truncated) {
                it.unread_file_bytes = 0;
            }
        }
    }
    try testing.expectEqual(case.files.len, i);
}

test "pax/gnu long names with small buffer" {
    try testLongNameCase(gnu_multi_headers_case);
    try testLongNameCase(trailing_slash_case);
    try testLongNameCase(.{
        .data = @embedFile("testdata/fuzz1.tar"),
        .err = error.TarInsufficientBuffer,
    });
}

fn testLongNameCase(case: Case) !void {
    // should fail with insufficient buffer error

    var min_file_name_buffer: [256]u8 = undefined;
    var min_link_name_buffer: [100]u8 = undefined;

    var br: std.io.Reader = .fixed(case.data);
    var iter: tar.Iterator = .init(&br, .{
        .file_name_buffer = &min_file_name_buffer,
        .link_name_buffer = &min_link_name_buffer,
    });

    var iter_err: ?anyerror = null;
    while (iter.next() catch |err| brk: {
        iter_err = err;
        break :brk null;
    }) |_| {}

    try testing.expect(iter_err != null);
    try testing.expectEqual(error.TarInsufficientBuffer, iter_err.?);
}

test "insufficient buffer in Header name filed" {
    var min_file_name_buffer: [9]u8 = undefined;
    var min_link_name_buffer: [100]u8 = undefined;

    var br: std.io.Reader = .fixed(gnu_case.data);
    var iter: tar.Iterator = .init(&br, .{
        .file_name_buffer = &min_file_name_buffer,
        .link_name_buffer = &min_link_name_buffer,
    });

    var iter_err: ?anyerror = null;
    while (iter.next() catch |err| brk: {
        iter_err = err;
        break :brk null;
    }) |_| {}

    try testing.expect(iter_err != null);
    try testing.expectEqual(error.TarInsufficientBuffer, iter_err.?);
}

test "should not overwrite existing file" {
    // Starting from this folder structure:
    // $ tree root
    //    root
    //    ├── a
    //    │   └── b
    //    │       └── c
    //    │           └── file.txt
    //    └── d
    //        └── b
    //            └── c
    //                └── file.txt
    //
    // Packed with command:
    // $ cd root; tar cf overwrite_file.tar *
    // Resulting tar has following structure:
    // $ tar tvf overwrite_file.tar
    //  size path
    //  0    a/
    //  0    a/b/
    //  0    a/b/c/
    //  2    a/b/c/file.txt
    //  0    d/
    //  0    d/b/
    //  0    d/b/c/
    //  2    d/b/c/file.txt
    //
    // Note that there is no root folder in archive.
    //
    // With strip_components = 1 resulting unpacked folder was:
    //  root
    //     └── b
    //         └── c
    //             └── file.txt
    //
    // a/b/c/file.txt is overwritten with d/b/c/file.txt !!!
    // This ensures that file is not overwritten.
    //
    const data = @embedFile("testdata/overwrite_file.tar");
    var r: std.io.Reader = .fixed(data);

    // Unpack with strip_components = 1 should fail
    var root = std.testing.tmpDir(.{});
    defer root.cleanup();
    try testing.expectError(
        error.PathAlreadyExists,
        tar.pipeToFileSystem(root.dir, &r, .{ .mode_mode = .ignore, .strip_components = 1 }),
    );

    // Unpack with strip_components = 0 should pass
    r = .fixed(data);
    var root2 = std.testing.tmpDir(.{});
    defer root2.cleanup();
    try tar.pipeToFileSystem(root2.dir, &r, .{ .mode_mode = .ignore, .strip_components = 0 });
}

test "case sensitivity" {
    // Mimicking issue #18089, this tar contains, same file name in two case
    // sensitive name version. Should fail on case insensitive file systems.
    //
    // $ tar tvf 18089.tar
    //     18089/
    //     18089/alacritty/
    //     18089/alacritty/darkermatrix.yml
    //     18089/alacritty/Darkermatrix.yml
    //
    const data = @embedFile("testdata/18089.tar");
    var r: std.io.Reader = .fixed(data);

    var root = std.testing.tmpDir(.{});
    defer root.cleanup();

    tar.pipeToFileSystem(root.dir, &r, .{ .mode_mode = .ignore, .strip_components = 1 }) catch |err| {
        // on case insensitive fs we fail on overwrite existing file
        try testing.expectEqual(error.PathAlreadyExists, err);
        return;
    };

    // on case sensitive os both files are created
    try testing.expect((try root.dir.statFile("alacritty/darkermatrix.yml")).kind == .file);
    try testing.expect((try root.dir.statFile("alacritty/Darkermatrix.yml")).kind == .file);
}
