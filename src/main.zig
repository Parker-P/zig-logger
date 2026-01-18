const std = @import("std");
const ast = std.zig.Ast;
const TokenTag = std.zig.Token.Tag;

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

fn parseSettingsFromArguments(allocator: std.mem.Allocator, out_project_path: []u8, no_params: *bool) !usize {
    var args = std.process.argsWithAllocator(allocator) catch |e| @panic(@errorName(e));
    while (args.next() != null) {}
    var split = std.mem.splitAny(u8, args.inner.buffer, &[_]u8{0});
    _ = split.next();
    var project_dir = split.next();
    if (std.fs.path.dirname(project_dir.?) == null) {
        std.log.err("Folder invalid not provided\n", .{});
        return error.NoFolderProvided;
    }
    @memcpy(out_project_path[0..project_dir.?.len], project_dir.?[0..]);
    const no_parameters = split.next();
    if (no_parameters == null) {
        std.log.info("Including parameters in log calls\n", .{});
        return project_dir.?.len;
    }
    if (std.mem.eql(u8, no_parameters.?, "-noparams")) {
        std.log.info("Excluding parameters from log calls\n", .{});
        no_params.* = true;
    } else {
        std.log.info("Including parameters in log calls\n", .{});
    }
    return project_dir.?.len;
}

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const allocator = arena_allocator.allocator();
    var project_directory: [512]u8 = undefined;
    var no_params = true;
    const len = try parseSettingsFromArguments(allocator, &project_directory, &no_params);

    // std.debug.print("{s} - {}", .{ project_directory[0..len], no_params });
    var zig_file_paths = detectZigFiles(allocator, project_directory[0..len]);
    defer zig_file_paths.deinit(allocator);

    for (0..zig_file_paths.items.len) |i| {
        std.debug.print("Parsing file {s}\n", .{zig_file_paths.items[i]});
        var tree = parseZigFile(allocator, zig_file_paths.items[i]) catch |e| @panic(@errorName(e));
        defer tree.deinit(allocator);
        var functions_info: std.ArrayList(LogContext) = .empty;
        defer functions_info.deinit(allocator);
        getFunctionsInfo(allocator, tree, zig_file_paths.items[i], &functions_info);
        std.debug.print("Found {d} functions\n", .{functions_info.items.len});
        injectLogInstructions(allocator, functions_info, zig_file_paths.items[i], no_params);
        formatZigFile(allocator, zig_file_paths.items[i]);
    }
}

fn detectZigFiles(allocator: std.mem.Allocator, project_directory: []const u8) std.ArrayList([]u8) {
    var zig_files: std.ArrayList([]u8) = .empty;
    const dir_handle = std.fs.openDirAbsolute(project_directory, .{ .iterate = true }) catch |e| @panic(@errorName(e));

    var walker = std.fs.Dir.walk(dir_handle, allocator) catch |e| @panic(@errorName(e));
    defer walker.deinit();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;

    while (walker.next() catch |e| @panic(@errorName(e))) |entry| {
        const dir_path = entry.dir.realpath(".", &path_buf) catch |e| @panic(@errorName(e));
        const full_path = std.mem.concat(allocator, u8, &[_][]const u8{ dir_path, &[_]u8{std.fs.path.sep}, entry.path }) catch |e| @panic(@errorName(e));
        if (!std.mem.endsWith(u8, full_path, ".zig")) continue;
        zig_files.append(allocator, full_path) catch |e| @panic(@errorName(e));
    }

    return zig_files;
}

fn getFunctionsInfo(allocator: std.mem.Allocator, tree: ast, file_path: []u8, out_functions_info: *std.ArrayList(LogContext)) void {
    // if (!std.mem.containsAtLeast(u8, file_path, 1, "dupe.zig")) return;

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

        while (tag != TokenTag.r_paren and tag != TokenTag.eof) {
            i = parseFunctionParameter(tree, &i, &log_context);
            tag = tree.tokenTag(@intCast(i));
            if (tag == TokenTag.comma) {
                i += 1;
                tag = tree.tokenTag(@intCast(i));
            }
        }
        if (tag != TokenTag.r_paren) continue;
        i += 1;
        tag = tree.tokenTag(@intCast(i));

        while (tag != TokenTag.l_brace and tag != TokenTag.eof) {
            i += 1;
            tag = tree.tokenTag(@intCast(i));
        }

        if (tag != TokenTag.l_brace) continue;
        log_context.byte_offset = @intCast(tree.tokenStart(@intCast(i)) + 1);
        out_functions_info.*.append(allocator, log_context) catch |e| @panic(@errorName(e));
    }
}

fn parseFunctionParameter(tree: ast, i: *i32, log_ctx: *LogContext) i32 {
    var tag = tree.tokenTag(@intCast(i.*));
    if (tag != TokenTag.identifier) return i.*;
    log_ctx.*.addParameterName(tree.tokenSlice(@intCast(i.*))) catch |e| @panic(@errorName(e));
    i.* += 1;
    tag = tree.tokenTag(@intCast(i.*));
    if (tag != TokenTag.colon) return i.*;
    i.* += 1;
    tag = tree.tokenTag(@intCast(i.*));
    while (tag != TokenTag.r_paren and tag != TokenTag.eof and tag != TokenTag.comma) {
        i.* += 1;
        tag = tree.tokenTag(@intCast(i.*));
    }
    return i.*;
}

fn parseZigFile(allocator: std.mem.Allocator, file_path: []u8) !ast {
    var file = std.fs.openFileAbsolute(file_path, .{ .mode = .read_write }) catch |e| @panic(@errorName(e));
    var buf: [500000]u8 = undefined;
    const file_size = try file.read(buf[0..]);
    buf[file_size] = 0;
    const source: [:0]const u8 = buf[0..file_size :0];
    return try ast.parse(allocator, source, .zig);
}

fn injectLogInstructions(allocator: std.mem.Allocator, log_ctxs: std.ArrayList(LogContext), file_path: []const u8, no_params: bool) void {
    for (0..log_ctxs.items.len) |i| {
        var buf: [256]u8 = undefined;
        const log_instruction = createLoggingInstruction(log_ctxs.items[i], &buf, no_params);
        for (i + 1..log_ctxs.items.len) |j| {
            log_ctxs.items[j].byte_offset += log_instruction.len;
            log_ctxs.items[j].function_location.line += 1;
        }
        insertText(allocator, file_path, log_ctxs.items[i].byte_offset, log_instruction);
    }
}

fn createLoggingInstruction(log_ctx: LogContext, output_buffer: *[256]u8, no_params: bool) []u8 {
    const tmp = if (no_params)
        "std.log.info(\"%file_name% @ %line%:%column% - %funcion_name%\", .{});"
    else
        "std.log.info(\"%file_name% @ %line%:%column% - %funcion_name%: {any}\", .{%params%});";
    @memcpy(output_buffer[0..tmp.len], tmp[0..]);
    var last = tmp.len;
    var buf: [64]u8 = undefined;
    var replacement_buffer: [256]u8 = undefined;

    _ = std.mem.replace(u8, output_buffer[0..last], "%file_name%", log_ctx.file_name, replacement_buffer[0..]);
    @memcpy(output_buffer, &replacement_buffer);
    last = std.mem.find(u8, output_buffer[0..], &[_]u8{';'}).? + 1;

    _ = std.mem.replace(u8, output_buffer[0..last], "%line%", toString(buf[0..], log_ctx.function_location.line), replacement_buffer[0..]);
    @memcpy(output_buffer, &replacement_buffer);
    last = std.mem.find(u8, output_buffer[0..], &[_]u8{';'}).? + 1;

    _ = std.mem.replace(u8, output_buffer[0..last], "%column%", toString(buf[0..], log_ctx.function_location.column), replacement_buffer[0..]);
    @memcpy(output_buffer, &replacement_buffer);
    last = std.mem.find(u8, output_buffer[0..], &[_]u8{';'}).? + 1;

    _ = std.mem.replace(u8, output_buffer[0..last], "%funcion_name%", log_ctx.function_name, replacement_buffer[0..]);
    @memcpy(output_buffer, &replacement_buffer);
    last = std.mem.find(u8, output_buffer[0..], &[_]u8{';'}).? + 1;

    if (!no_params) {
        var parameters: [128]u8 = undefined;
        @memcpy(parameters[0..2], ".{");
        const p_names = log_ctx.parameter_names.items;
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

        _ = std.mem.replace(u8, output_buffer[0..last], "%params%", parameters[0..k], replacement_buffer[0..]);
        @memcpy(output_buffer, &replacement_buffer);
    }

    last = std.mem.find(u8, output_buffer[0..], &[_]u8{';'}).? + 1;
    return output_buffer[0..last];
}

fn toString(buf: []u8, value: anytype) []u8 {
    return std.fmt.bufPrint(buf[0..], "{any}", .{value}) catch |e| @panic(@errorName(e));
}

fn insertText(allocator: std.mem.Allocator, file_path: []const u8, where: usize, text: []const u8) void {
    const file = std.fs.openFileAbsolute(file_path, .{ .mode = .read_write }) catch |e| @panic(@errorName(e));
    const file_size = file.getEndPos() catch |e| @panic(@errorName(e));
    if (where > file_size) return;
    var file_content: []u8 = allocator.alloc(u8, file_size + text.len) catch |e| @panic(@errorName(e));
    _ = file.read(file_content) catch |e| @panic(@errorName(e));
    const remainder = file_size - where;
    @memmove(file_content[where + text.len .. where + text.len + remainder], file_content[where .. where + remainder]);
    @memcpy(file_content[where .. where + text.len], text);
    file.seekTo(0) catch |e| @panic(@errorName(e));
    file.writeAll(file_content) catch |e| @panic(@errorName(e));
}

fn formatZigFile(allocator: std.mem.Allocator, file_path: []const u8) void {
    var res = std.process.Child.run(.{ .allocator = allocator, .argv = &[_][]const u8{ "zig", "fmt", file_path } }) catch |e| @panic(@errorName(e));
    if (res.stderr.len > 0) std.debug.print("{s}\n", .{res.stderr});
}
