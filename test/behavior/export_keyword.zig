const std = @import("std");
const expect = std.testing.expect;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualStrings = std.testing.expectEqualStrings;
const mem = std.mem;
const builtin = @import("builtin");

// can't really run this test but we can make sure it has no compile error
// and generates code
const vram = @as([*]volatile u8, @ptrFromInt(0x20000000))[0..0x8000];
export fn writeToVRam() void {
    if (builtin.zig_backend == .stage2_riscv64) return;

    vram[0] = 'X';
}

const PackedStruct = packed struct {
    a: u8,
    b: u8,
};
const PackedUnion = packed union {
    a: u8,
    b: u32,
};

test "packed struct, enum, union parameters in extern function" {
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    testPackedStuff(&(PackedStruct{
        .a = 1,
        .b = 2,
    }), &(PackedUnion{ .a = 1 }));
}

export fn testPackedStuff(a: *const PackedStruct, b: *const PackedUnion) void {
    if (false) {
        a;
        b;
    }
}

test "export function alias" {
    if (builtin.zig_backend == .stage2_x86_64 and builtin.target.ofmt == .coff) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    _ = struct {
        fn foo_internal() callconv(.c) u32 {
            return 123;
        }
        export const foo_exported = foo_internal;
    };
    const Import = struct {
        extern fn foo_exported() u32;
    };
    try expect(Import.foo_exported() == 123);
}
