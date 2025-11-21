const std = @import("std");
const ast = @import("ast.zig");
const Parser = @import("parser.zig").Parser;
const engine = @import("engine.zig");
const isocline = @import("isocline_wrapper.zig");
const highlighter = @import("highlighter.zig");

fn rawPrint(text: []const u8) !void {
    const builtin = @import("builtin");
    if (builtin.os.tag == .windows) {
        const windows = std.os.windows;
        const handle = windows.GetStdHandle(windows.STD_OUTPUT_HANDLE) catch return error.StdoutUnavailable;
        _ = try windows.WriteFile(handle, text, null);
    } else {
        _ = try std.posix.write(std.posix.STDOUT_FILENO, text);
    }
}

// Command completer - called by ic_complete_word for REPL commands
// The prefix here is just the word part (e.g., "help" not ":help")
fn commandCompleter(cenv: ?*isocline.CompletionEnv, prefix: [*c]const u8) callconv(std.builtin.CallingConvention.c) void {
    const commands = [_][*c]const u8{
        "help",
        "quit",
        "load",
        "clear",
    };

    const prefix_len = std.mem.len(prefix);
    const prefix_slice = prefix[0..prefix_len];

    for (commands) |cmd| {
        const cmd_len = std.mem.len(cmd);
        const cmd_slice = cmd[0..cmd_len];
        if (std.mem.startsWith(u8, cmd_slice, prefix_slice)) {
            _ = isocline.addCompletion(cenv, cmd);
        }
    }
}

// Character classifier for commands - ':' is NOT a word character
// This makes ic_complete_word extract just the command part after ':'
fn isCommandChar(s: [*c]const u8, len: c_long) callconv(std.builtin.CallingConvention.c) bool {
    if (len <= 0) return false;
    const char = s[0];
    return (char >= 'a' and char <= 'z') or
        (char >= 'A' and char <= 'Z') or
        char == '_';
}

// Custom completer for ziglog REPL
// This is called by isocline for every completion request
fn ziglogCompleter(cenv: ?*isocline.CompletionEnv, prefix: [*c]const u8) callconv(std.builtin.CallingConvention.c) void {
    const prefix_len = std.mem.len(prefix);
    if (prefix_len == 0) return;

    // Get the full input line to check context
    const input = isocline.completionInput(cenv, null);
    const input_len = std.mem.len(input);
    const input_slice = input[0..input_len];

    // If input starts with ":", it's a REPL command
    if (std.mem.startsWith(u8, input_slice, ":")) {
        // Check if this is ":load " - complete filenames
        if (std.mem.startsWith(u8, input_slice, ":load ")) {
            isocline.completeFilename(cenv, prefix, '/', null, ".pl");
            return;
        }

        // Find the position of the first space in the input
        const space_pos = std.mem.indexOfScalar(u8, input_slice, ' ');

        // If there's no space, we're still completing the command itself
        if (space_pos == null) {
            isocline.completeWord(cenv, prefix, commandCompleter, isCommandChar);
        }
        // Otherwise, there's already a space, so we're past the command
        // Don't offer any completions for arguments to other commands
        return;
    }

    // For regular Prolog input (rules, facts, queries), no completion
    // This avoids accidentally triggering filename completion when typing
    // Prolog syntax that contains '.' (end of clause) or other punctuation
}

// Syntax highlighter for ziglog REPL
// This is called by isocline to highlight the input as the user types
fn ziglogHighlighter(henv: ?*isocline.HighlightEnv, input: [*c]const u8, _: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void {
    highlighter.highlightForIsocline(henv, input);
}

fn loadFile(alloc: std.mem.Allocator, engine_instance: *engine.Engine, filename: []const u8) !void {
    const filename_z = try alloc.dupeZ(u8, filename);
    defer alloc.free(filename_z);

    const file = try std.fs.cwd().openFile(filename_z, .{});
    defer file.close();

    const content = try file.readToEndAlloc(alloc, 1024 * 1024); // 1MB max
    defer alloc.free(content);

    var parser = Parser.init(alloc, content);

    while (parser.lexer.peek().tag != .eof) {
        const rule = parser.parseRule() catch |err| {
            try rawPrint("Error parsing file: ");
            try rawPrint(@errorName(err));
            try rawPrint("\n");
            return err;
        };
        try engine_instance.addRule(rule);
        try rawPrint("Loaded: ");
        var buf: [256]u8 = undefined;
        var fixed_buf_stream = std.io.fixedBufferStream(&buf);
        try rule.head.format("", .{}, fixed_buf_stream.writer());
        try rawPrint(fixed_buf_stream.getWritten());
        try rawPrint(".\n");
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var engine_instance = engine.Engine.init(alloc);
    defer engine_instance.deinit();

    // Setup isocline (pure C, much simpler!)
    try isocline.init(".ziglog_history", 200);

    // Set custom completer for context-aware completion
    isocline.setDefaultCompleter(ziglogCompleter, null);

    // Set custom highlighter for syntax highlighting
    isocline.setDefaultHighlighter(ziglogHighlighter, null);

    // Enable automatic completion preview
    isocline.enableCompletionPreview(true);

    // Enable syntax highlighting
    isocline.enableHighlight(true);

    try rawPrint("Ziglog REPL (with isocline support)\n");
    try rawPrint("Type a rule/fact. Type ?- query. Type :help for commands.\n\n");

    while (true) {
        // Read line with isocline (history, editing capabilities)
        // Pass empty prompt_text; isocline will use default prompt_marker ("> ")
        const line = isocline.readline("") orelse break; // Ctrl+D to exit
        defer isocline.freeLine(line); // isocline returns malloc'd memory

        const trimmed = std.mem.trim(u8, line, " \r\t");
        if (trimmed.len == 0) continue;

        // Skip comment-only lines
        if (std.mem.startsWith(u8, trimmed, "%")) continue;

        // Handle REPL commands
        if (std.mem.startsWith(u8, trimmed, ":")) {
            if (std.mem.eql(u8, trimmed, ":quit") or std.mem.eql(u8, trimmed, ":q")) {
                break;
            } else if (std.mem.eql(u8, trimmed, ":help") or std.mem.eql(u8, trimmed, ":h")) {
                try rawPrint("Ziglog REPL Commands:\n");
                try rawPrint("  :help            Show this help\n");
                try rawPrint("  :quit            Exit the REPL\n");
                try rawPrint("  :load <file>     Load Prolog file\n");
                try rawPrint("  :clear           Clear screen\n");
                try rawPrint("\n");
                try rawPrint("Editing:\n");
                try rawPrint("  Tab              Auto-complete predicates\n");
                try rawPrint("  Up/Down          Navigate history\n");
                try rawPrint("  Ctrl+R           Search history\n");
                try rawPrint("  Ctrl+D           Exit (EOF)\n");
                try rawPrint("\n");
                try rawPrint("Syntax:\n");
                try rawPrint("  ?- query.        Run a query\n");
                try rawPrint("  fact.            Add a fact\n");
                try rawPrint("  head :- body.    Add a rule\n");
            } else if (std.mem.eql(u8, trimmed, ":clear")) {
                // Clear screen using ANSI escape code
                try rawPrint("\x1B[2J\x1B[H");
            } else if (std.mem.startsWith(u8, trimmed, ":load ")) {
                const filename = std.mem.trim(u8, trimmed[6..], " \r\t\n");
                if (filename.len == 0) {
                    try rawPrint("Usage: :load <filename>\n");
                    continue;
                }
                loadFile(alloc, &engine_instance, filename) catch |err| {
                    try rawPrint("Error loading file: ");
                    try rawPrint(@errorName(err));
                    try rawPrint("\n");
                };
            } else {
                try rawPrint("Unknown command. Type :help for available commands.\n");
            }
            continue;
        }

        const is_query = std.mem.startsWith(u8, trimmed, "?-");
        var parse_input = trimmed;
        if (is_query) parse_input = std.mem.trim(u8, trimmed[2..], " ");

        var parser = Parser.init(alloc, parse_input);

        if (is_query) {
            while (parser.lexer.peek().tag != .eof) {
                const goals = parser.parseQuery() catch {
                    try rawPrint("Error parsing query\n");
                    break;
                };
                var env = engine.createEnv();
                var has_printed = false;
                const stdout = StdOutWriter{};
                var ctx = HandlerContext{ .writer = stdout, .has_printed = &has_printed, .alloc = alloc };
                const handler = engine.Engine.SolutionHandler{
                    .context = &ctx,
                    .handle = defaultHandle,
                };
                _ = try engine_instance.solve(goals, &env, 0, 0, handler, stdout);
                if (!has_printed) try rawPrint("  false.\n");
            }
        } else {
            while (parser.lexer.peek().tag != .eof) {
                const rule = parser.parseRule() catch {
                    try rawPrint("Error parsing rule\n");
                    break;
                };
                try engine_instance.addRule(rule);
                try rawPrint("  Added.\n");
            }
        }
    }
}

const StdOutWriter = struct {
    pub const Error = error{SystemResources};

    pub fn print(_: StdOutWriter, comptime fmt: []const u8, args: anytype) Error!void {
        var buf: [4096]u8 = undefined;
        const slice = std.fmt.bufPrint(&buf, fmt, args) catch return error.SystemResources;
        _ = std.posix.write(std.posix.STDOUT_FILENO, slice) catch return error.SystemResources;
    }

    pub fn writeAll(_: StdOutWriter, bytes: []const u8) Error!void {
        _ = std.posix.write(std.posix.STDOUT_FILENO, bytes) catch return error.SystemResources;
    }

    pub fn writeByteNTimes(_: StdOutWriter, byte: u8, n: usize) Error!void {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            _ = std.posix.write(std.posix.STDOUT_FILENO, &[_]u8{byte}) catch return error.SystemResources;
        }
    }
};

const HandlerContext = struct {
    writer: StdOutWriter,
    has_printed: *bool,
    alloc: std.mem.Allocator,
};

fn defaultHandle(ctx_ptr: ?*anyopaque, env: engine.EnvMap, _: *engine.Engine) !void {
    const ctx: *HandlerContext = @ptrCast(@alignCast(ctx_ptr));

    var it = env.iterator();
    var found_vars = false;
    var output = std.ArrayListUnmanaged(u8){};
    const out_writer = output.writer(ctx.alloc);

    while (it.next()) |entry| {
        if (std.mem.indexOf(u8, entry.key_ptr.*, "_") == null) {
            if (found_vars) try out_writer.print(", ", .{});
            const val = try engine.copyTerm(ctx.alloc, entry.value_ptr.*, env);
            try out_writer.print("{s} = ", .{entry.key_ptr.*});
            try val.format("", .{}, out_writer);
            found_vars = true;
        }
    }

    if (found_vars) {
        try ctx.writer.print("  {s}\n", .{output.items});
        ctx.has_printed.* = true;
    } else {
        if (!ctx.has_printed.*) {
            try ctx.writer.print("  true.\n", .{});
            ctx.has_printed.* = true;
        }
    }
}

test {
    _ = @import("lexer.zig");
    _ = @import("parser.zig");
    _ = @import("ast.zig");
    _ = @import("engine.zig");
}
