const std = @import("std");
const debug = std.debug;
const getopt = @import("getopt.zig");

pub fn main() void {
    var arg_file: ?[]const u8 = null;
    var arg_output: ?[]const u8 = null;
    var verbose: bool = false;
    var count: u32 = 1;

    const long_options = [_]getopt.LongOption{
        .{ .name = "file", .has_arg = getopt.LongOption.required_argument, .val = 'f' },
        .{ .name = "output", .has_arg = getopt.LongOption.required_argument, .val = 'o' },
        .{ .name = "verbose", .has_arg = getopt.LongOption.no_argument, .val = 'v' },
        .{ .name = "count", .has_arg = getopt.LongOption.required_argument, .val = 'c' },
        .{ .name = "help", .has_arg = getopt.LongOption.no_argument, .val = 'h' },
        .{ .name = "version", .has_arg = getopt.LongOption.no_argument, .val = 1000 }, // Long-only option
    };

    var long_index: usize = undefined;
    var opts = getopt.getopt_long("f:o:vc:h", &long_options, &long_index);

    while (opts.next()) |maybe_opt| {
        if (maybe_opt) |opt| {
            switch (opt.opt) {
                'f' => {
                    arg_file = opt.arg.?;
                    if (opt.long_name) |name| {
                        debug.print("--{s} = {s}\n", .{ name, arg_file.? });
                    } else {
                        debug.print("-f = {s}\n", .{arg_file.?});
                    }
                },
                'o' => {
                    arg_output = opt.arg.?;
                    if (opt.long_name) |name| {
                        debug.print("--{s} = {s}\n", .{ name, arg_output.? });
                    } else {
                        debug.print("-o = {s}\n", .{arg_output.?});
                    }
                },
                'v' => {
                    verbose = true;
                    if (opt.long_name) |name| {
                        debug.print("--{s} enabled\n", .{name});
                    } else {
                        debug.print("-v enabled\n", .{});
                    }
                },
                'c' => {
                    count = std.fmt.parseInt(u32, opt.arg.?, 10) catch {
                        debug.print("Invalid count value: {s}\n", .{opt.arg.?});
                        return;
                    };
                    if (opt.long_name) |name| {
                        debug.print("--{s} = {}\n", .{ name, count });
                    } else {
                        debug.print("-c = {}\n", .{count});
                    }
                },
                'h' => {
                    debug.print(
                        \\usage: example_long [OPTIONS]
                        \\
                        \\Options:
                        \\  -f, --file FILE      Input file
                        \\  -o, --output FILE    Output file
                        \\  -v, --verbose        Enable verbose output
                        \\  -c, --count COUNT    Set count value
                        \\  -h, --help           Show this help message
                        \\      --version        Show version information
                        \\
                    , .{});
                    return;
                },
                0 => {
                    // This handles long options that don't have short equivalents
                    // Check the long_name to determine which option it was
                    if (opt.long_name) |name| {
                        if (std.mem.eql(u8, name, "version")) {
                            debug.print("example_long version 1.0.0\n", .{});
                            return;
                        } else {
                            debug.print("Long option: {s}\n", .{name});
                        }
                    }
                },
                else => unreachable,
            }
        } else break;
    } else |err| {
        switch (err) {
            getopt.Error.InvalidOption => {
                debug.print("Invalid option\n", .{});
            },
            getopt.Error.MissingArgument => {
                debug.print("Option requires an argument\n", .{});
            },
        }
        return;
    }

    debug.print("\nConfiguration:\n", .{});
    debug.print("  File: {?s}\n", .{arg_file});
    debug.print("  Output: {?s}\n", .{arg_output});
    debug.print("  Verbose: {}\n", .{verbose});
    debug.print("  Count: {}\n", .{count});

    if (opts.args()) |remaining| {
        debug.print("  Remaining args: ", .{});
        for (remaining) |arg| {
            debug.print("{s} ", .{std.mem.span(arg)});
        }
        debug.print("\n", .{});
    }
}
