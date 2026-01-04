const std = @import("std");
const ast = std.zig.Ast;

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    injectLogCalls(arena_allocator.allocator(), std.Io.Dir.openDir()));

    // var idx: [1]ast.Node.Index = undefined;
    // const function_prototype = tree.fnProto(@enumFromInt(1));

    // std.debug.print("{d}\n", .{function_prototype.ast.});
    // std.debug.print("Node's tag name is {s}.\n", .{fn_proto.?.ast.proto_node});
}

fn injectLogCalls(allocator: std.mem.Allocator, project_directory: std.fs.Dir) void {
    const hash_map: std.StringHashMap(ast) = undefined;
    const files = detecZigFiles(project_directory);
}

fn detectZigFiles(project_directory: std.fs.Dir) []std.fs.File {
    const allocator = std.heap.page_allocator;
    std.fs.Dir.walk(project_directory, allocator);
}

fn parseZigFiles() []ast {
    const file = std.fs.cwd().openFile("/home/Paolo/code/zig-playground/example.zig", .{ .mode = .read_write }) catch @panic("error opening file");
    var buf: [512]u8 = undefined;
    const file_size = file.read(buf[0..]) catch @panic("error reading file");

    var gpa = std.heap.DebugAllocator(.{}).init;
    buf[file_size] = 0;
    const source: [:0]const u8 = buf[0..file_size :0];
    const tree = try ast.parse(gpa.allocator(), source, .zig);
}

fn getTokens(buf: []u8, tree: ast) []u8 {
    std.debug.print("getTokens\n", .{});
    var total_len: usize = 0;
    for (0..tree.tokens.len) |i| {
        const slice = tree.tokenSlice(@intCast(i));
        tree.tokenStart())
        @memmove(buf[total_len .. total_len + slice.len], slice);
        total_len += slice.len;
    }

    // TODO: 
    // 1. get token tags via tree.tokenTag()
    // 2. detect function declarations using the tags, you will have something like fn + identifier + open bracket + ...
    // 3. use tree.tokenStart() to get the byte offset of the function's open bracket { in the source code
    // 4. copy the source code buffer
    // 5. into the copied buffer, inject a log call that prints at least the identifier of the function you found at step 2
    // 6. save the file to the original location

    return buf[0..total_len];
}
