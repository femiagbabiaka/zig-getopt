const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const os = std.os;
const expect = std.testing.expect;

/// Long option definition struct.
pub const LongOption = struct {
    /// Long option name (without leading dashes).
    name: []const u8,

    /// Argument requirement: 0 = no argument, 1 = required argument, 2 = optional argument.
    has_arg: u8,

    /// Pointer to flag variable (null if not used).
    flag: ?*c_int = null,

    /// Value to set flag to, or value to return if flag is null.
    val: c_int,

    pub const no_argument = 0;
    pub const required_argument = 1;
    pub const optional_argument = 2;
};

/// Parsed option struct.
pub const Option = struct {
    /// Option character (0 for long options without short equivalent).
    opt: u8,

    /// Option argument, if any.
    arg: ?[]const u8 = null,

    /// Long option name for long options, null for short options.
    long_name: ?[]const u8 = null,

    /// Index in the long options array (only set for long options).
    long_index: ?usize = null,
};

pub const Error = error{ InvalidOption, MissingArgument };

pub const OptionsIterator = struct {
    argv: [][*:0]const u8,
    opts: []const u8,
    long_opts: ?[]const LongOption = null,

    /// Index of the current element of the argv vector.
    optind: usize = 1,

    optpos: usize = 1,

    /// Current option character.
    optopt: u8 = undefined,

    /// Index of the long option that was found (for getopt_long).
    longind: ?*usize = null,

    pub fn next(self: *OptionsIterator) Error!?Option {
        if (self.optind == self.argv.len)
            return null;

        const arg = self.argv[self.optind];
        const arg_str = mem.span(arg);

        if (mem.eql(u8, arg_str, "--")) {
            self.optind += 1;
            return null;
        }

        // Handle long options (--option)
        if (self.long_opts != null and arg_str.len > 2 and mem.startsWith(u8, arg_str, "--")) {
            return self.parseLongOption(arg_str[2..]);
        }

        // Handle short options (-o)
        if (arg[0] != '-' or arg[1] == 0)
            return null;

        // Skip non-alphanumeric characters for short options
        if (!ascii.isAlphanumeric(arg[1]))
            return null;

        self.optopt = arg[self.optpos];

        const maybe_idx = mem.indexOfScalar(u8, self.opts, self.optopt);
        if (maybe_idx) |idx| {
            if (idx < self.opts.len - 1 and self.opts[idx + 1] == ':') {
                if (arg[self.optpos + 1] != 0) {
                    const res = Option{
                        .opt = self.optopt,
                        .arg = mem.span(arg + self.optpos + 1),
                    };
                    self.optind += 1;
                    self.optpos = 1;
                    return res;
                } else if (self.optind + 1 < self.argv.len) {
                    const res = Option{
                        .opt = self.optopt,
                        .arg = mem.span(self.argv[self.optind + 1]),
                    };
                    self.optind += 2;
                    self.optpos = 1;
                    return res;
                } else return Error.MissingArgument;
            } else {
                self.optpos += 1;
                if (arg[self.optpos] == 0) {
                    self.optind += 1;
                    self.optpos = 1;
                }
                return Option{ .opt = self.optopt };
            }
        } else return Error.InvalidOption;
    }

    fn parseLongOption(self: *OptionsIterator, long_name: []const u8) Error!?Option {
        const long_opts = self.long_opts.?;

        // Check for option=value format
        const eq_pos = mem.indexOfScalar(u8, long_name, '=');
        const option_name = if (eq_pos) |pos| long_name[0..pos] else long_name;
        const option_value = if (eq_pos) |pos| long_name[pos + 1 ..] else null;

        // Find matching long option
        for (long_opts, 0..) |long_opt, i| {
            if (mem.eql(u8, long_opt.name, option_name)) {
                if (self.longind) |longind_ptr| {
                    longind_ptr.* = i;
                }

                var result = Option{
                    .opt = if (long_opt.val >= 0 and long_opt.val <= 255) @intCast(long_opt.val) else 0,
                    .long_name = long_opt.name,
                    .long_index = i,
                };

                // Handle argument requirements
                switch (long_opt.has_arg) {
                    LongOption.no_argument => {
                        if (option_value != null) {
                            // Error: option doesn't take an argument but one was provided
                            return Error.InvalidOption;
                        }
                        self.optind += 1;
                        return result;
                    },
                    LongOption.required_argument => {
                        if (option_value) |val| {
                            result.arg = val;
                            self.optind += 1;
                            return result;
                        } else if (self.optind + 1 < self.argv.len) {
                            result.arg = mem.span(self.argv[self.optind + 1]);
                            self.optind += 2;
                            return result;
                        } else {
                            return Error.MissingArgument;
                        }
                    },
                    LongOption.optional_argument => {
                        if (option_value) |val| {
                            result.arg = val;
                        }
                        self.optind += 1;
                        return result;
                    },
                    else => return Error.InvalidOption,
                }
            }
        }

        return Error.InvalidOption;
    }

    /// Return remaining arguments, if any.
    pub fn args(self: *OptionsIterator) ?[][*:0]const u8 {
        if (self.optind < self.argv.len)
            return self.argv[self.optind..]
        else
            return null;
    }
};

fn getoptArgv(argv: [][*:0]const u8, optstring: []const u8) OptionsIterator {
    return OptionsIterator{
        .argv = argv,
        .opts = optstring,
    };
}

fn getoptLongArgv(argv: [][*:0]const u8, optstring: []const u8, longopts: []const LongOption, longindex: ?*usize) OptionsIterator {
    return OptionsIterator{
        .argv = argv,
        .opts = optstring,
        .long_opts = longopts,
        .longind = longindex,
    };
}

/// Parse os.argv according to the optstring.
pub fn getopt(optstring: []const u8) OptionsIterator {
    // https://github.com/ziglang/zig/issues/8808
    const argv: [][*:0]const u8 = @ptrCast(os.argv);
    return getoptArgv(argv, optstring);
}

/// Parse os.argv according to the optstring and long options.
pub fn getopt_long(optstring: []const u8, longopts: []const LongOption, longindex: ?*usize) OptionsIterator {
    // https://github.com/ziglang/zig/issues/8808
    const argv: [][*:0]const u8 = @ptrCast(os.argv);
    return getoptLongArgv(argv, optstring, longopts, longindex);
}

test "no args separate" {
    var argv = [_][*:0]const u8{
        "getopt",
        "-a",
        "-b",
    };

    const expected = [_]Option{
        .{ .opt = 'a' },
        .{ .opt = 'b' },
    };

    var opts = getoptArgv(&argv, "ab");

    var i: usize = 0;
    while (try opts.next()) |opt| : (i += 1) {
        try expect(opt.opt == expected[i].opt);
        if (opt.arg != null and expected[i].arg != null) {
            try expect(mem.eql(u8, opt.arg.?, expected[i].arg.?));
        } else {
            try expect(opt.arg == null and expected[i].arg == null);
        }
    }

    try expect(opts.args() == null);
}

test "no args joined" {
    var argv = [_][*:0]const u8{
        "getopt",
        "-abc",
    };

    const expected = [_]Option{
        .{ .opt = 'a' },
        .{ .opt = 'b' },
        .{ .opt = 'c' },
    };

    var opts = getoptArgv(&argv, "abc");

    var i: usize = 0;
    while (try opts.next()) |opt| : (i += 1) {
        try expect(opt.opt == expected[i].opt);
        if (opt.arg != null and expected[i].arg != null) {
            try expect(mem.eql(u8, opt.arg.?, expected[i].arg.?));
        } else {
            try expect(opt.arg == null and expected[i].arg == null);
        }
    }
}

test "with args separate" {
    var argv = [_][*:0]const u8{
        "getopt",
        "-a10",
        "-b",
        "-c",
        "42",
    };

    const expected = [_]Option{
        .{ .opt = 'a', .arg = "10" },
        .{ .opt = 'b' },
        .{ .opt = 'c', .arg = "42" },
    };

    var opts = getoptArgv(&argv, "a:bc:");

    var i: usize = 0;
    while (try opts.next()) |opt| : (i += 1) {
        try expect(opt.opt == expected[i].opt);
        if (opt.arg != null and expected[i].arg != null) {
            try expect(mem.eql(u8, opt.arg.?, expected[i].arg.?));
        } else {
            try expect(opt.arg == null and expected[i].arg == null);
        }
    }
}

test "with args joined" {
    var argv = [_][*:0]const u8{
        "getopt",
        "-a10",
        "-bc",
        "42",
    };

    const expected = [_]Option{
        .{ .opt = 'a', .arg = "10" },
        .{ .opt = 'b' },
        .{ .opt = 'c', .arg = "42" },
    };

    var opts = getoptArgv(&argv, "a:bc:");

    var i: usize = 0;
    while (try opts.next()) |opt| : (i += 1) {
        try expect(opt.opt == expected[i].opt);
        if (opt.arg != null and expected[i].arg != null) {
            try expect(mem.eql(u8, opt.arg.?, expected[i].arg.?));
        } else {
            try expect(opt.arg == null and expected[i].arg == null);
        }
    }
}

test "invalid option" {
    var argv = [_][*:0]const u8{
        "getopt",
        "-az",
    };

    var opts = getoptArgv(&argv, "a");

    // -a is ok
    try expect((try opts.next()).?.opt == 'a');

    const maybe_opt = opts.next();
    if (maybe_opt) |_| {
        unreachable;
    } else |err| {
        try expect(err == Error.InvalidOption);
        try expect(opts.optopt == 'z');
    }
}

test "missing argument" {
    var argv = [_][*:0]const u8{
        "getopt",
        "-az",
    };

    var opts = getoptArgv(&argv, "az:");

    // -a is ok
    try expect((try opts.next()).?.opt == 'a');

    const maybe_opt = opts.next();
    if (maybe_opt) |_| {
        unreachable;
    } else |err| {
        try expect(err == Error.MissingArgument);
        try expect(opts.optopt == 'z');
    }
}

test "positional args" {
    var argv = [_][*:0]const u8{
        "getopt",
        "-abc10",
        "-d",
        "foo",
        "bar",
    };

    const expected = [_]Option{
        .{ .opt = 'a' },
        .{ .opt = 'b' },
        .{ .opt = 'c', .arg = "10" },
        .{ .opt = 'd' },
    };

    var opts = getoptArgv(&argv, "abc:d");

    var i: usize = 0;
    while (try opts.next()) |opt| : (i += 1) {
        try expect(opt.opt == expected[i].opt);
        if (opt.arg != null and expected[i].arg != null) {
            try expect(mem.eql(u8, opt.arg.?, expected[i].arg.?));
        } else {
            try expect(opt.arg == null and expected[i].arg == null);
        }
    }

    try expect(mem.eql([*:0]const u8, opts.args().?, &[_][*:0]const u8{ "foo", "bar" }));
}

test "positional args with separator" {
    var argv = [_][*:0]const u8{
        "getopt",
        "-ab",
        "--",
        "foo",
        "bar",
    };

    const expected = [_]Option{
        .{ .opt = 'a' },
        .{ .opt = 'b' },
    };

    var opts = getoptArgv(&argv, "ab");

    var i: usize = 0;
    while (try opts.next()) |opt| : (i += 1) {
        try expect(opt.opt == expected[i].opt);
        if (opt.arg != null and expected[i].arg != null) {
            try expect(mem.eql(u8, opt.arg.?, expected[i].arg.?));
        } else {
            try expect(opt.arg == null and expected[i].arg == null);
        }
    }

    try expect(mem.eql([*:0]const u8, opts.args().?, &[_][*:0]const u8{ "foo", "bar" }));
}

test "long options no args" {
    var argv = [_][*:0]const u8{
        "getopt",
        "--verbose",
        "--help",
    };

    const long_options = [_]LongOption{
        .{ .name = "verbose", .has_arg = LongOption.no_argument, .val = 'v' },
        .{ .name = "help", .has_arg = LongOption.no_argument, .val = 'h' },
    };

    const expected = [_]Option{
        .{ .opt = 'v', .long_name = "verbose", .long_index = 0 },
        .{ .opt = 'h', .long_name = "help", .long_index = 1 },
    };

    var opts = getoptLongArgv(&argv, "vh", &long_options, null);

    var i: usize = 0;
    while (try opts.next()) |opt| : (i += 1) {
        try expect(opt.opt == expected[i].opt);
        if (opt.long_name != null and expected[i].long_name != null) {
            try expect(mem.eql(u8, opt.long_name.?, expected[i].long_name.?));
        }
        try expect(opt.long_index == expected[i].long_index);
    }
}

test "long options with args" {
    var argv = [_][*:0]const u8{
        "getopt",
        "--file=test.txt",
        "--output",
        "result.txt",
    };

    const long_options = [_]LongOption{
        .{ .name = "file", .has_arg = LongOption.required_argument, .val = 'f' },
        .{ .name = "output", .has_arg = LongOption.required_argument, .val = 'o' },
    };

    const expected = [_]Option{
        .{ .opt = 'f', .arg = "test.txt", .long_name = "file", .long_index = 0 },
        .{ .opt = 'o', .arg = "result.txt", .long_name = "output", .long_index = 1 },
    };

    var opts = getoptLongArgv(&argv, "f:o:", &long_options, null);

    var i: usize = 0;
    while (try opts.next()) |opt| : (i += 1) {
        try expect(opt.opt == expected[i].opt);
        if (opt.arg != null and expected[i].arg != null) {
            try expect(mem.eql(u8, opt.arg.?, expected[i].arg.?));
        }
        if (opt.long_name != null and expected[i].long_name != null) {
            try expect(mem.eql(u8, opt.long_name.?, expected[i].long_name.?));
        }
        try expect(opt.long_index == expected[i].long_index);
    }
}

test "mixed short and long options" {
    var argv = [_][*:0]const u8{
        "getopt",
        "-v",
        "--file=test.txt",
        "-h",
        "--output",
        "result.txt",
    };

    const long_options = [_]LongOption{
        .{ .name = "file", .has_arg = LongOption.required_argument, .val = 'f' },
        .{ .name = "output", .has_arg = LongOption.required_argument, .val = 'o' },
    };

    const expected = [_]Option{
        .{ .opt = 'v' },
        .{ .opt = 'f', .arg = "test.txt", .long_name = "file", .long_index = 0 },
        .{ .opt = 'h' },
        .{ .opt = 'o', .arg = "result.txt", .long_name = "output", .long_index = 1 },
    };

    var opts = getoptLongArgv(&argv, "vhf:o:", &long_options, null);

    var i: usize = 0;
    while (try opts.next()) |opt| : (i += 1) {
        try expect(opt.opt == expected[i].opt);
        if (opt.arg != null and expected[i].arg != null) {
            try expect(mem.eql(u8, opt.arg.?, expected[i].arg.?));
        } else {
            try expect(opt.arg == null and expected[i].arg == null);
        }
        if (opt.long_name != null and expected[i].long_name != null) {
            try expect(mem.eql(u8, opt.long_name.?, expected[i].long_name.?));
        }
        if (expected[i].long_index) |expected_idx| {
            try expect(opt.long_index.? == expected_idx);
        } else {
            try expect(opt.long_index == null);
        }
    }
}

test "long option invalid" {
    var argv = [_][*:0]const u8{
        "getopt",
        "--invalid",
    };

    const long_options = [_]LongOption{
        .{ .name = "verbose", .has_arg = LongOption.no_argument, .val = 'v' },
    };

    var opts = getoptLongArgv(&argv, "v", &long_options, null);

    const maybe_opt = opts.next();
    if (maybe_opt) |_| {
        unreachable;
    } else |err| {
        try expect(err == Error.InvalidOption);
    }
}

test "long option missing argument" {
    var argv = [_][*:0]const u8{
        "getopt",
        "--file",
    };

    const long_options = [_]LongOption{
        .{ .name = "file", .has_arg = LongOption.required_argument, .val = 'f' },
    };

    var opts = getoptLongArgv(&argv, "f:", &long_options, null);

    const maybe_opt = opts.next();
    if (maybe_opt) |_| {
        unreachable;
    } else |err| {
        try expect(err == Error.MissingArgument);
    }
}
