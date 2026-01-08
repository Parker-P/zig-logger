const std = @import("std");
const ast = std.zig.Ast;

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    injectLogCalls(arena_allocator.allocator(), std.fs.openDirAbsolute("/home/Paolo/code/zig-playground", .{ .iterate = true }) catch |e| @panic(@errorName(e)));

    // var idx: [1]ast.Node.Index = undefined;
    // const function_prototype = tree.fnProto(@enumFromInt(1));

    // std.debug.print("{d}\n", .{function_prototype.ast.});
    // std.debug.print("Node's tag name is {s}.\n", .{fn_proto.?.ast.proto_node});
}

fn injectLogCalls(allocator: std.mem.Allocator, project_directory: []u8) void {
    // const hash_map: std.StringHashMap(ast) = undefined;
    // const files = detecZigFiles(project_directory);

    const f = detectZigFiles(allocator, project_directory);
    for (0..f.items.len) |i| {
        var tree = parseZigFile(allocator, f.items[i]) catch |e| @panic(@errorName(e));
        defer tree.deinit(allocator);
        getTokens(tree);
    }
}

fn detectZigFiles(allocator: std.mem.Allocator, project_directory: std.fs.Dir) std.ArrayList([]u8) {
    var zig_files = std.ArrayList([]u8).allocatedSlice();
    var walker = std.fs.Dir.walk(project_directory, allocator) catch |e| @panic(@errorName(e));
    defer walker.deinit();

    var file_count: usize = 0;
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    while (walker.next() catch |e| @panic(@errorName(e))) |entry| {
        const dir_path = entry.dir.realpath(".", &path_buf) catch |e| @panic(@errorName(e));

        const full_path = std.mem.concat(allocator, u8, &[_][]const u8{
            dir_path,
            &[_]u8{std.fs.path.sep},
            entry.path,
        }) catch |e| @panic(@errorName(e));

        if (!std.mem.endsWith(u8, full_path, ".zig")) continue;

        zig_files.append(allocator, full_path) catch |e| @panic(@errorName(e));
        file_count += 1;
    }

    std.debug.print("{any}\n", .{zig_files});
    return zig_files;
}

fn parseZigFile(allocator: std.mem.Allocator, file_path: []u8) !ast {
    std.debug.print("Parsing file {any}\n", .{file_path});
    var file = std.fs.openFileAbsolute(file_path, .{ .mode = .read_write }) catch |e| @panic(@errorName(e));
    var buf: [512]u8 = undefined;
    const file_size = try file.read(buf[0..]);
    buf[file_size] = 0;
    const source: [:0]const u8 = buf[0..file_size :0];
    return try ast.parse(allocator, source, .zig);
}

fn getTokens(tree: ast) void {
    std.debug.print("getTokens\n", .{});
    _ = tree;
    // var total_len: usize = 0;
    // for (0..tree.tokens.len) |i| {
    //     const slice = tree.tokenSlice(@intCast(i));
    //     tree.tokenStart();
    //     @memmove(buf[total_len .. total_len + slice.len], slice);
    //     total_len += slice.len;
    // }

    // TODO:
    // 1. get token tags via tree.tokenTag()
    // 2. detect function declarations using the tags, you will have something like fn + identifier + open bracket + ...
    // 3. use tree.tokenStart() to get the byte offset of the function's open bracket { in the source code
    // 4. copy the source code buffer
    // 5. into the copied buffer, inject a log call that prints at least the identifier of the function you found at step 2
    // 6. save the file to the original location

    // return buf[0..total_len];
    // return buf[0..1];
}
