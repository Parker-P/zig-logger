const std = @import("std");
pub fn main() !void {
    const file = std.fs.cwd().openFile("/home/Paolo/code/zig-playground/example.zig", .{ .mode = .read_write }) catch @panic("error opening file");
    var buf: [256]u8 = undefined;
    const file_size = file.read(buf[0..]) catch @panic("error reading file");
    std.debug.print("{s}", .{buf[0..file_size]});

    // Parse Zig AST
    var gpa = std.heap.DebugAllocator(.{}).init;
    // Now create the sentinel slice
    buf[file_size] = 0;
    const source: [:0]const u8 = buf[0..file_size :0];
    const ast = try std.zig.Ast.parse(gpa.allocator(), source, .zig);
    // catch |err| @panic(@errorName(err));
    std.debug.print("{}", .{ast});

    _ = gpa.deinit();

    // std.debug.print("{}", .{ast});

    // const tree = ast.tree;
    // const tokens = tree.tokens;

    // var insert_offset: ?usize = null;
    // var param_print: []u8 = &[]; // will hold generated format string

    // // Walk top-level declarations
    // for (tree.rootDecls()) |decl| {
    //     if (tree.nodeTag(decl) != .fn_decl)
    //         continue;

    //     const fn_decl = tree.nodeData(decl).fn_decl;
    //     const name_token = fn_decl.name_token orelse continue;
    //     const fn_name = tree.tokenSlice(name_token);

    //     if (!std.mem.eql(u8, fn_name, "main"))
    //         continue;

    //     // Prepare logging code
    //     const body_node = fn_decl.body_node orelse continue;
    //     if (tree.nodeTag(body_node) != .block)
    //         continue;
    //     const block = tree.nodeData(body_node).block;
    //     const lbrace_token = block.lbrace_token;
    //     const token_start = tokens.items(.start)[lbrace_token];
    //     const token_len = tokens.items(.len)[lbrace_token];
    //     insert_offset = token_start + token_len;

    //     // Collect parameter logging
    //     var builder = std.StringBuilder.init(allocator);
    //     try builder.append("std.debug.print(\"ENTER main");
    //     var first = true;

    //     for (fn_decl.params) |param| {
    //         const name_token = param.name_token orelse continue;
    //         const param_name = tree.tokenSlice(name_token);
    //         const type_expr = param.type orelse continue;
    //         const type_name = tree.tokenSlice(type_expr);

    //         // Only log simple supported types
    //         var fmt: []const u8 = "";
    //         if (std.mem.eql(u8, type_name, "i32") or std.mem.eql(u8, type_name, "u32") or
    //             std.mem.eql(u8, type_name, "f32") or std.mem.eql(u8, type_name, "f64") or
    //             std.mem.eql(u8, type_name, "u8") or std.mem.eql(u8, type_name, "char"))
    //         {
    //             fmt = " = {d}";
    //         } else if (std.mem.eql(u8, type_name, "[]const u8")) {
    //             fmt = " = {s}";
    //         } else {
    //             continue; // skip unsupported types
    //         }

    //         if (first) first = false; else try builder.append(", ");
    //         try builder.append(param_name);
    //         try builder.append(fmt);
    //     }
    //     try builder.append("\\n\", .{");

    //     first = true;
    //     for (fn_decl.params) |param| {
    //         const name_token = param.name_token orelse continue;
    //         const param_name = tree.tokenSlice(name_token);
    //         const type_expr = param.type orelse continue;
    //         const type_name = tree.tokenSlice(type_expr);

    //         if (std.mem.eql(u8, type_name, "i32") or std.mem.eql(u8, type_name, "u32") or
    //             std.mem.eql(u8, type_name, "f32") or std.mem.eql(u8, type_name, "f64") or
    //             std.mem.eql(u8, type_name, "u8") or std.mem.eql(u8, type_name, "char") or
    //             std.mem.eql(u8, type_name, "[]const u8"))
    //         {
    //             if (first) first = false; else try builder.append(", ");
    //             try builder.append(param_name);
    //         }
    //     }
    //     try builder.append("});\n");

    //     param_print = try builder.toOwnedSlice();
    //     break;
    // }

    // if (insert_offset == null) {
    //     std.debug.print("main function not found\n", .{});
    //     return;
    // }

    // // Emit modified source
    // try std.io.getStdOut().writer().writeAll(source[0..insert_offset.?]);
    // try std.io.getStdOut().writer().writeAll(param_print);
    // try std.io.getStdOut().writer().writeAll(source[insert_offset.?..]);
}
