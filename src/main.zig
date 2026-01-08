const std = @import("std");
const ast = std.zig.Ast;

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    // injectLogCalls(arena_allocator.allocator(), "/home/Paolo/code/zig-playground");
    // injectLogCalls(arena_allocator.allocator(), "C:/code/zig-logger/src");
    injectLogCalls(arena_allocator.allocator(), "C:/code/zig-logger/src");

    // var idx: [1]ast.Node.Index = undefined;
    // const function_prototype = tree.fnProto(@enumFromInt(1));

    // std.debug.print("{d}\n", .{function_prototype.ast.});
    // std.debug.print("Node's tag name is {s}.\n", .{fn_proto.?.ast.proto_node});
}

fn injectLogCalls(allocator: std.mem.Allocator, project_directory: []const u8) void {
    // const hash_map: std.StringHashMap(ast) = undefined;
    // const files = detecZigFiles(project_directory);

    std.debug.print("Injecting log calls project dir is {s}\n", .{project_directory});

    // const f = detectZigFiles(allocator, project_directory);
    var f = detectZigFiles(allocator, project_directory);
    defer f.deinit(allocator);

    // std.debug.print("Discovered files are {any}\n", .{f});

    for (0..f.items.len) |i| {
        var tree = parseZigFile(allocator, f.items[i]) catch |e| @panic(@errorName(e));
        defer tree.deinit(allocator);
        getTokens(allocator, tree);
    }
}

fn detectZigFiles(allocator: std.mem.Allocator, project_directory: []const u8) std.ArrayList([]u8) {
    var zig_files: std.ArrayList([]u8) = .empty;

    const dir_handle = std.fs.openDirAbsolute(project_directory, .{ .iterate = true }) catch |e| @panic(@errorName(e));

    var walker = std.fs.Dir.walk(dir_handle, allocator) catch |e| @panic(@errorName(e));
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

    return zig_files;
}

fn parseZigFile(allocator: std.mem.Allocator, file_path: []u8) !ast {
    var file = std.fs.openFileAbsolute(file_path, .{ .mode = .read_write }) catch |e| @panic(@errorName(e));
    var buf: [500000]u8 = undefined;
    const file_size = try file.read(buf[0..]);
    buf[file_size] = 0;
    const source: [:0]const u8 = buf[0..file_size :0];
    return try ast.parse(allocator, source, .zig);
}

fn getTokens(allocator: std.mem.Allocator, tree: ast) void {
    std.debug.print("getTokens\n", .{});
    // _ = tree;
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

    var tags: std.ArrayList(std.zig.Token.Tag) = .empty;
    defer tags.deinit(allocator);
    for (0..tree.tokens.len) |i| {
        tags.append(allocator, tree.tokenTag(@intCast(i))) catch |e| @panic(@errorName(e));
    }

    std.debug.print("Tags are {any}\n", .{tags});

    // return buf[0..total_len];
    // return buf[0..1];
}
