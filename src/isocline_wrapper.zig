const std = @import("std");

const c = @cImport({
    @cInclude("isocline.h");
});

/// Initialize isocline with history
pub fn init(history_file: ?[]const u8, max_entries: i32) !void {
    if (history_file) |file| {
        const file_z = try std.heap.c_allocator.dupeZ(u8, file);
        defer std.heap.c_allocator.free(file_z);
        c.ic_set_history(file_z.ptr, max_entries);
    } else {
        c.ic_set_history(null, max_entries);
    }
}

/// Read a line of input with editing capabilities
/// Returns null on EOF (Ctrl+D)
/// Caller must free the returned string with std.heap.c_allocator.free()
pub fn readline(prompt: [:0]const u8) ?[]const u8 {
    const line_ptr = c.ic_readline(prompt.ptr);
    if (line_ptr == null) return null;

    const len = std.mem.len(line_ptr);
    return line_ptr[0..len];
}

/// Free a line returned by readline
pub fn freeLine(line: []const u8) void {
    std.heap.c_allocator.free(line);
}

/// Print with bbcode formatting
pub fn print(s: [:0]const u8) void {
    c.ic_print(s.ptr);
}

/// Print with bbcode formatting and newline
pub fn println(s: [:0]const u8) void {
    c.ic_println(s.ptr);
}

/// Set the prompt marker (default is "> ")
pub fn setPromptMarker(marker: [:0]const u8) void {
    c.ic_set_prompt_marker(marker.ptr);
}

/// Enable/disable multiline editing
pub fn enableMultiline(enable: bool) void {
    c.ic_enable_multiline(enable);
}

/// Enable/disable auto-tab completion
pub fn enableAutoTab(enable: bool) void {
    c.ic_enable_auto_tab(enable);
}

/// Enable/disable completion preview (automatic popup)
pub fn enableCompletionPreview(enable: bool) void {
    _ = c.ic_enable_completion_preview(enable);
}

/// Enable/disable syntax highlighting
pub fn enableHighlight(enable: bool) void {
    _ = c.ic_enable_highlight(enable);
}

// Completion API types
pub const CompletionEnv = c.ic_completion_env_t;
pub const CompleterFun = *const fn (cenv: ?*CompletionEnv, prefix: [*c]const u8) callconv(std.builtin.CallingConvention.c) void;

/// Set the default completion handler
pub fn setDefaultCompleter(completer: CompleterFun, arg: ?*anyopaque) void {
    c.ic_set_default_completer(completer, arg);
}

/// Add a completion
pub fn addCompletion(cenv: ?*CompletionEnv, completion: [*c]const u8) bool {
    return c.ic_add_completion(cenv, completion);
}

/// Add a completion with optional display and help text
pub fn addCompletionEx(cenv: ?*CompletionEnv, completion: [*c]const u8, display: ?[*c]const u8, help: ?[*c]const u8) bool {
    return c.ic_add_completion_ex(cenv, completion, display, help);
}

/// Complete a filename with given separator, roots, and extensions
/// Pass null for roots to use current directory, null for extensions to match all
pub fn completeFilename(cenv: ?*CompletionEnv, prefix: [*c]const u8, dir_separator: u8, roots: ?[*c]const u8, extensions: ?[*c]const u8) void {
    c.ic_complete_filename(cenv, prefix, @intCast(dir_separator), roots orelse null, extensions orelse null);
}

/// Complete a word (token) using a custom completer function
pub fn completeWord(cenv: ?*CompletionEnv, prefix: [*c]const u8, fun: CompleterFun, is_word_char: ?*const fn ([*c]const u8, c_long) callconv(std.builtin.CallingConvention.c) bool) void {
    c.ic_complete_word(cenv, prefix, fun, is_word_char);
}

/// Get the full input line from completion environment
pub fn completionInput(cenv: ?*CompletionEnv, cursor: ?*c_long) [*c]const u8 {
    return c.ic_completion_input(cenv, cursor);
}

// Highlighting API types
pub const HighlightEnv = c.ic_highlight_env_t;
pub const HighlighterFun = *const fn (henv: ?*HighlightEnv, input: [*c]const u8, arg: ?*anyopaque) callconv(std.builtin.CallingConvention.c) void;

/// Set the default syntax highlighter
pub fn setDefaultHighlighter(highlighter: HighlighterFun, arg: ?*anyopaque) void {
    c.ic_set_default_highlighter(highlighter, arg);
}

/// Highlight characters at position with given style
pub fn highlight(henv: ?*HighlightEnv, pos: c_long, count: c_long, style: [*c]const u8) void {
    c.ic_highlight(henv, pos, count, style);
}
