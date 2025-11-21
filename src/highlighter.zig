const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const TokenType = @import("lexer.zig").TokenType;
const isocline = @import("isocline_wrapper.zig");

/// Highlight a Prolog input line for isocline REPL
/// This function applies syntax colors as the user types
/// Uses a stack allocator for temporary lexer allocations
pub fn highlightForIsocline(henv: ?*isocline.HighlightEnv, input: [*c]const u8) void {
    const input_len = std.mem.len(input);
    if (input_len == 0) return;

    const input_slice = input[0..input_len];

    // Special case: REPL commands (starting with ':')
    if (std.mem.startsWith(u8, input_slice, ":")) {
        // Highlight the colon in cyan
        isocline.highlight(henv, 0, 1, "cyan");

        // Find the end of the command (space or end of string)
        var cmd_end: usize = 1;
        while (cmd_end < input_len) : (cmd_end += 1) {
            const ch = input_slice[cmd_end];
            if (ch == ' ' or ch == '\t') break;
        }

        // Highlight the command name in cyan bold
        if (cmd_end > 1) {
            isocline.highlight(henv, 1, @intCast(cmd_end - 1), "cyan bold");
        }

        // The rest (arguments) remain default color
        return;
    }

    // For Prolog code, tokenize and highlight
    // Use a small stack buffer for lexer allocations
    var buf: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();

    var lexer = Lexer.init(alloc, input_slice);

    while (true) {
        const start_pos = lexer.pos;
        const token = lexer.next();
        const end_pos = lexer.pos;

        if (token.tag == .eof) break;

        const token_len: c_long = @intCast(end_pos - start_pos);
        if (token_len <= 0) continue;

        const style = getStyleForToken(token.tag);
        if (style) |s| {
            isocline.highlight(henv, @intCast(start_pos), token_len, s);
        }
    }
}

/// Map token types to isocline color styles
/// Returns null for tokens that should use default color
/// Uses HTML color names supported by isocline
fn getStyleForToken(tag: TokenType) ?[*:0]const u8 {
    return switch (tag) {
        // Variables (uppercase or underscore) - lime is bright green
        .variable => "lime",

        // Atoms and keywords
        .atom => "yellow",

        // Numbers
        .number => "magenta",

        // Strings
        .string => "gold",

        // Operators and punctuation
        .turnstile => "cyan",          // :-
        .arrow => "cyan",              // -->
        .if_then => "cyan",            // ->
        .lparen, .rparen => null,      // default color
        .lbracket, .rbracket => "dodgerblue",
        .lbrace, .rbrace => null,      // default color
        .bar => "dodgerblue",          // | (list separator)
        .comma => null,                // default color
        .period => null,               // default color
        .semicolon => "cyan",          // ; (disjunction)
        .not => "red",                 // \+ (negation)
        .is => "cyan",                 // is

        // Comparison operators
        .equal => "cyan",              // =
        .not_equal => "cyan",          // \=
        .arith_equal => "cyan",        // =:=
        .arith_not_equal => "cyan",    // =\=
        .less => "cyan",               // <
        .greater => "cyan",            // >
        .less_equal => "cyan",         // =<
        .greater_equal => "cyan",      // >=

        // Arithmetic operators
        .plus => "cyan",
        .minus => "cyan",
        .mul => "cyan",
        .div => "cyan",
        .int_div => "cyan",            // // (integer division)

        // Default/unknown
        .eof => null,
    };
}
