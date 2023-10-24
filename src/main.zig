// https://viewsourcecode.org/snaptoken/kilo/02.enteringRawMode.html

const std = @import("std");
const sys = std.os.system;
const Allocator = std.mem.Allocator;

const ZeditError = error{
    WinSize,
};

const WindowSize = struct {
    rows: u16,
    cols: u16,

    fn init() !WindowSize {
        var winsize = std.mem.zeroes(sys.winsize);
        const err = sys.ioctl(std.os.STDOUT_FILENO, sys.T.IOCGWINSZ, @intFromPtr(&winsize));
        if (std.os.errno(err) != .SUCCESS) {
            return ZeditError.WinSize;
        }
        return .{
            .rows = winsize.ws_row,
            .cols = winsize.ws_col,
        };
    }
};

const State = struct {
    const Self = @This();

    fd: sys.fd_t,
    orig_termios: sys.termios,
    winsize: WindowSize,

    fn init() !Self {
        const fd = std.os.STDIN_FILENO;
        const orig = try std.os.tcgetattr(fd);
        const winsize = try WindowSize.init();

        return .{
            .orig_termios = orig,
            .fd = fd,
            .winsize = winsize,
        };
    }

    fn get_winsize(self: Self) WindowSize {
        return self.winsize;
    }

    fn enable_raw_mode(self: Self) !void {
        var attr = self.orig_termios;
        attr.iflag &= ~(sys.IXON | sys.ICRNL | sys.BRKINT | sys.INPCK | sys.ISTRIP);
        attr.oflag &= ~(sys.OPOST);
        attr.lflag &= ~(sys.ECHO | sys.ICANON | sys.ISIG | sys.IEXTEN);
        attr.cflag |= sys.CS8;

        attr.cc[sys.V.MIN] = 0;
        attr.cc[sys.V.TIME] = 1;
        try std.os.tcsetattr(self.fd, .FLUSH, attr);
    }

    fn disable_raw_mode(self: Self) !void {
        try std.os.tcsetattr(self.fd, .FLUSH, self.orig_termios);
    }
};

// check if input is 'q' or 'Ctrl+q'
fn is_quit(c: u8) bool {
    // ASCII tricks:
    // 1. 'Ctrl' clears bits 5 and 6 of the following character
    // 2. Set and clear bit 5 to switch between lowercase and uppercase
    return (c == 'q') or (c == 'q' & 0x1f);
}

const EditorCommand = enum {
    Noop,
    Quit,

    fn from_char(c: u8) EditorCommand {
        if (is_quit(c)) {
            return .Quit;
        } else {
            return .Noop;
        }
    }
};

// TODO: Pass a generic writer around?
fn move_cursor(writer: anytype) !void {
    _ = try writer.write("\x1b[H"); // move cursor to top-left corner
}

fn draw(writer: anytype, winsize: WindowSize) !void {
    const msg = "Kilo editor clone -- version 0.1";
    const msg_start_row = winsize.rows / 3;
    const msg_start_col = (winsize.cols - 1 - msg.len) / 2;

    for (0..winsize.rows) |y| {
        _ = try writer.write("~");
        if (y == msg_start_row) {
            for (0..msg_start_col) |_| {
                _ = try writer.write(" ");
            }
            _ = try writer.write(msg);
        }
        if (y < winsize.rows - 1) {
            _ = try writer.write("\r\n");
        }
    }
}

// TODO: Does this always pass in state by reference?
fn refresh(writer: anytype, state: State) !void {
    _ = try writer.write("\x1b[?25l"); // hide cursor
    _ = try writer.write("\x1b[2J"); // clear screen
    try move_cursor(writer);
    try draw(writer, state.get_winsize());
    try move_cursor(writer);
    _ = try writer.write("\x1b[?25h"); // show cursor again
}

pub fn main() !void {
    const state = try State.init();
    try state.enable_raw_mode();
    defer state.disable_raw_mode() catch unreachable;

    const reader = std.io.getStdIn().reader();
    var writer = std.io.bufferedWriter(std.io.getStdOut().writer());

    // read stdin byte-by-byte
    loop: while (true) {
        try refresh(&writer, state);
        try writer.flush();

        const c = reader.readByte() catch 0;
        const cmd = EditorCommand.from_char(c);
        switch (cmd) {
            .Noop => {},
            .Quit => {
                break :loop;
            },
        }
    }
}
