const std = @import("std");
const ast = std.zig.Ast;

const LogContext = struct {
    allocator: std.mem.Allocator,
    file_name: []const u8,
    function_location: std.zig.Ast.Location,
    function_name: []const u8,
    byte_offset: usize,
    parameter_names: std.ArrayList([]const u8),

    fn init(self: *LogContext, allocator: std.mem.Allocator) void {
        self.* = .{
            .allocator = allocator,
            .file_name = undefined,
            .function_location = undefined,
            .function_name = undefined,
            .byte_offset = undefined,
            .parameter_names = .empty,
        };
    }

    fn deinit(self: *LogContext) void {
        for (self.parameter_names.items) |name| {
            self.allocator.free(name);
        }
        self.parameter_names.deinit(self.allocator);
    }

    fn addParameterName(self: *LogContext, name: []const u8) !void {
        const owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned);

        try self.parameter_names.append(self.allocator, owned);
    }
};

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    // injectLogCalls(arena_allocator.allocator(), "/home/Paolo/code/zig-playground");
    injectLogCalls(arena_allocator.allocator(), "C:/code/zig-logger/src");
}

fn injectLogCalls(allocator: std.mem.Allocator, project_directory: []const u8) void {
    var f = detectZigFiles(allocator, project_directory);
    defer f.deinit(allocator);

    var tree = parseZigFile(allocator, f.items[0]) catch |e| @panic(@errorName(e));
    defer tree.deinit(allocator);

    getFunctionInfo(allocator, tree, f.items[0]);
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

fn getFunctionInfo(allocator: std.mem.Allocator, tree: ast, file_path: []u8) void {
    const TokenTag = std.zig.Token.Tag;
    var log_ctxs: std.ArrayList(LogContext) = .empty;
    defer log_ctxs.deinit(allocator);
    var i: i32 = -1;
    while (i < tree.tokens.len - 1) {
        i += 1;
        var tag = tree.tokenTag(@intCast(i));
        if (tag != TokenTag.keyword_fn) continue;
        i += 1;
        tag = tree.tokenTag(@intCast(i));
        if (tag != TokenTag.identifier) continue;
        var log_context: LogContext = undefined;
        log_context.init(allocator);
        log_context.file_name = std.fs.path.basename(file_path);
        log_context.function_name = tree.tokenSlice(@intCast(i));
        log_context.function_location = tree.tokenLocation(0, @intCast(i));
        log_context.function_location.line += 1;
        i += 1;
        tag = tree.tokenTag(@intCast(i));
        if (tag != TokenTag.l_paren) continue;
        i += 1;

        while (tag != TokenTag.r_paren or tag != TokenTag.eof) {
            tag = tree.tokenTag(@intCast(i));
            if (tag == TokenTag.comma) {
                i += 1;
                tag = tree.tokenTag(@intCast(i));
            }
            if (tag != TokenTag.identifier) break;
            log_context.addParameterName(tree.tokenSlice(@intCast(i))) catch |e| @panic(@errorName(e));
            i += 1;
            tag = tree.tokenTag(@intCast(i));
            if (tag != TokenTag.colon) break;
            i += 1;
            tag = tree.tokenTag(@intCast(i));
            if (tag != TokenTag.identifier) break;
            i += 1;
        }

        if (tag != TokenTag.r_paren) continue;
        i += 1;
        tag = tree.tokenTag(@intCast(i));
        if (tag != TokenTag.identifier) continue;
        i += 1;
        tag = tree.tokenTag(@intCast(i));
        if (tag != TokenTag.l_brace) continue;
        log_context.byte_offset = @intCast(tree.tokenStart(@intCast(i)) + 1);
        log_ctxs.append(allocator, log_context) catch |e| @panic(@errorName(e));
    }

    for (0..log_ctxs.items.len) |ictx| {
        var log_instruction: [200]u8 = undefined;
        const tmp = "std.log.info(\"%file_name% @ %line%:%column% - %funcion_name%: {any}\", .{%parameters%});";
        @memcpy(log_instruction[0..tmp.len], tmp[0..]);
        var buf: [64]u8 = undefined;
        _ = std.mem.replace(u8, log_instruction[0..], "%file_name%", log_ctxs.items[ictx].file_name, log_instruction[0..]);
        _ = std.mem.replace(u8, log_instruction[0..], "%line%", toString(buf[0..], log_ctxs.items[ictx].function_location.line), log_instruction[0..]);
        _ = std.mem.replace(u8, log_instruction[0..], "%column%", toString(buf[0..], log_ctxs.items[ictx].function_location.column), log_instruction[0..]);
        _ = std.mem.replace(u8, log_instruction[0..], "%funcion_name%", log_ctxs.items[ictx].function_name, log_instruction[0..]);

        var parameters: [128]u8 = undefined;
        @memcpy(parameters[0..2], ".{");
        const p_names = log_ctxs.items[ictx].parameter_names.items;
        var k: usize = 2;
        for (0..p_names.len) |j| {
            @memcpy(parameters[k .. k + 1], ".");
            k += 1;
            @memcpy(parameters[k .. k + p_names[j].len], p_names[j]);
            k += p_names[j].len;
            @memcpy(parameters[k .. k + 3], " = ");
            k += 3;
            @memcpy(parameters[k .. k + p_names[j].len], p_names[j]);
            k += p_names[j].len;
            if (j < p_names.len - 1) {
                @memcpy(parameters[k .. k + 2], ", ");
                k += 2;
            }
        }

        @memcpy(parameters[k .. k + 1], "}");
        k += 1;
        var buf1: [256]u8 = undefined;
        _ = std.mem.replace(u8, log_instruction[0..], "%parameters%", parameters[0..k], buf1[0..]);
        const last = std.mem.find(u8, buf1[0..], &[_]u8{';'});
        insertText(file_path, log_ctxs.items[ictx].byte_offset, buf1[0 .. last.? + 1]);
    }
}

fn toString(buf: []u8, value: anytype) []u8 {
    return std.fmt.bufPrint(buf[0..], "{any}", .{value}) catch |e| @panic(@errorName(e));
}

fn insertText(file_path: []const u8, offset: usize, text: []const u8) void {
    const file = std.fs.openFileAbsolute(file_path, .{ .mode = .read_write }) catch |e| @panic(@errorName(e));
    var buf: [500000]u8 = undefined;
    var tmp: [500000]u8 = undefined;
    const byte_count = file.read(buf[0..]) catch |e| @panic(@errorName(e));
    const new_byte_count = byte_count + text.len;
    @memcpy(tmp[0..offset], buf[0..offset]);
    @memcpy(tmp[offset .. offset + text.len], text);
    @memcpy(tmp[offset + text.len .. new_byte_count], buf[offset..byte_count]);
    file.seekTo(0) catch |e| @panic(@errorName(e));
    file.writeAll(tmp[0..new_byte_count]) catch |e| @panic(@errorName(e));
}

// fn isTokenStartOfFunctionDeclaration(tree: ast, i: ast.TokenIndex) false!struct {} {}
