# Minimal POSIX getopt(3) and getopt_long(3) implementation in Zig

This is a minimal, allocation-free getopt(3) and getopt_long(3) implementation with [POSIX-conforming](http://pubs.opengroup.org/onlinepubs/9699919799/functions/getopt.html) argument parsing semantics. It supports both short options (like `-v`, `-h`) and long options (like `--verbose`, `--help`).

## Examples

### Basic getopt (short options only)

```zig
const std = @import("std");
const debug = std.debug;
const getopt = @import("getopt.zig");

pub fn main() void {
    var arg: []const u8 = undefined;
    var verbose: bool = false;

    var opts = getopt.getopt("a:vh");

    while (opts.next()) |maybe_opt| {
        if (maybe_opt) |opt| {
            switch (opt.opt) {
                'a' => {
                    arg = opt.arg.?;
                    debug.print("arg = {s}\n", .{arg});
                },
                'v' => {
                    verbose = true;
                    debug.print("verbose = {}\n", .{verbose});
                },
                'h' => debug.print(
                    \\usage: example [-a arg] [-hv]
                    \\
                , .{}),
                else => unreachable,
            }
        } else break;
    } else |err| {
        switch (err) {
            getopt.Error.InvalidOption => debug.print("invalid option: {c}\n", .{opts.optopt}),
            getopt.Error.MissingArgument => debug.print("option requires an argument: {c}\n", .{opts.optopt}),
        }
    }

    debug.print("remaining args: {?s}\n", .{opts.args()});
}
```

```
$ zig run example.zig -- -hv -a42 foo bar
usage: example [-a arg] [-hv]
verbose = true
arg = 42
remaining args: { foo, bar }
```

### getopt_long (short and long options)

```zig
const std = @import("std");
const debug = std.debug;
const getopt = @import("getopt.zig");

pub fn main() void {
    var arg_file: ?[]const u8 = null;
    var verbose: bool = false;

    const long_options = [_]getopt.LongOption{
        .{ .name = "file", .has_arg = getopt.LongOption.required_argument, .val = 'f' },
        .{ .name = "verbose", .has_arg = getopt.LongOption.no_argument, .val = 'v' },
        .{ .name = "help", .has_arg = getopt.LongOption.no_argument, .val = 'h' },
        .{ .name = "version", .has_arg = getopt.LongOption.no_argument, .val = 1000 }, // Long-only option
    };

    var long_index: usize = undefined;
    var opts = getopt.getopt_long("f:vh", &long_options, &long_index);

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
                'v' => {
                    verbose = true;
                    if (opt.long_name) |name| {
                        debug.print("--{s} enabled\n", .{name});
                    } else {
                        debug.print("-v enabled\n", .{});
                    }
                },
                'h' => debug.print(
                    \\usage: example [OPTIONS]
                    \\  -f, --file FILE    Input file
                    \\  -v, --verbose      Enable verbose output
                    \\  -h, --help         Show this help
                    \\      --version      Show version
                    \\
                , .{}),
                0 => {
                    // Handle long-only options
                    if (opt.long_name) |name| {
                        if (std.mem.eql(u8, name, "version")) {
                            debug.print("Version 1.0.0\n", .{});
                        }
                    }
                },
                else => unreachable,
            }
        } else break;
    } else |err| {
        switch (err) {
            getopt.Error.InvalidOption => debug.print("Invalid option\n", .{}),
            getopt.Error.MissingArgument => debug.print("Option requires an argument\n", .{}),
        }
    }

    debug.print("File: {?s}, Verbose: {}\n", .{ arg_file, verbose });
    debug.print("Remaining args: {?s}\n", .{opts.args()});
}
```

```
$ zig run example_long.zig -- --verbose --file=input.txt --help
--verbose enabled
--file = input.txt
usage: example [OPTIONS]
  -f, --file FILE    Input file
  -v, --verbose      Enable verbose output
  -h, --help         Show this help
      --version      Show version

$ zig run example_long.zig -- -v -f input.txt remaining args
-v enabled
-f = input.txt
File: input.txt, Verbose: true
Remaining args: { remaining, args }
```

## API Reference

### LongOption

```zig
pub const LongOption = struct {
    name: []const u8,           // Long option name (without leading dashes)
    has_arg: u8,               // Argument requirement (see constants below)  
    flag: ?*c_int = null,      // Pointer to flag variable (usually null)
    val: c_int,                // Value to return or set flag to

    pub const no_argument = 0;       // Option takes no argument
    pub const required_argument = 1; // Option requires an argument  
    pub const optional_argument = 2; // Option has optional argument
};
```

### Functions

- `getopt(optstring: []const u8)` - Parse short options only
- `getopt_long(optstring: []const u8, longopts: []const LongOption, longindex: ?*usize)` - Parse both short and long options

### Option Structure

The returned `Option` struct contains:
- `opt: u8` - Option character (0 for long-only options)
- `arg: ?[]const u8` - Option argument, if any
- `long_name: ?[]const u8` - Long option name (null for short options)  
- `long_index: ?usize` - Index in long options array (null for short options)
