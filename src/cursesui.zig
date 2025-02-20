const std = @import("std");
const curses = @import("curses.zig");
const core = @import("core.zig");


pub const Characters = struct {
    horiz_line: []const u8,         // -
    vert_line: []const u8,          // |
    crossing_up: []const u8,        // _|_
    crossing_down: []const u8,      // T
    crossing_left: []const u8,      // --|
    crossing_right: []const u8,     // |--
    crossing_plus: []const u8,      // --|--
    corner_topleft: []const u8,     // ,--
    corner_topright: []const u8,    // --.
    corner_bottomleft: []const u8,  // |__
    corner_bottomright: []const u8, // __|
    flag: []const u8,               // F
    mine: []const u8,               // *
};

pub const ascii_characters = Characters{
    .horiz_line = "-",
    .vert_line = "|",
    .crossing_up = "-",
    .crossing_down = "-",
    .crossing_left = "|",
    .crossing_right = "|",
    .crossing_plus = "+",
    .corner_topleft = ",",
    .corner_topright = ".",
    .corner_bottomleft = "`",
    .corner_bottomright = "'",
    .flag = "F",
    .mine = "*",
};

pub const unicode_characters = Characters{
    .horiz_line = "\xe2\x94\x80",           // BOX DRAWINGS LIGHT HORIZONTAL
    .vert_line = "\xe2\x94\x82",            // BOX DRAWINGS LIGHT VERTICAL
    .crossing_up = "\xe2\x94\xb4",          // BOX DRAWINGS LIGHT UP AND HORIZONTAL
    .crossing_down = "\xe2\x94\xac",        // BOX DRAWINGS LIGHT DOWN AND HORIZONTAL
    .crossing_left = "\xe2\x94\xa4",        // BOX DRAWINGS LIGHT VERTICAL AND LEFT
    .crossing_right = "\xe2\x94\x9c",       // BOX DRAWINGS LIGHT VERTICAL AND RIGHT
    .crossing_plus = "\xe2\x94\xbc",        // BOX DRAWINGS LIGHT VERTICAL AND HORIZONTAL
    .corner_topleft = "\xe2\x95\xad",       // BOX DRAWINGS LIGHT ARC DOWN AND RIGHT
    .corner_topright = "\xe2\x95\xae",      // BOX DRAWINGS LIGHT ARC DOWN AND LEFT
    .corner_bottomleft = "\xe2\x95\xb0",    // BOX DRAWINGS LIGHT ARC UP AND RIGHT
    .corner_bottomright = "\xe2\x95\xaf",   // BOX DRAWINGS LIGHT ARC UP AND LEFT
    .flag = "\xe2\x9a\x91",                 // BLACK FLAG
    .mine = "\xe2\x88\x97",                 // ASTERISK OPERATOR
};


pub const Ui = struct {
    selected_x: u8,
    selected_y: u8,
    game: *core.Game,
    window: curses.Window,
    chars: Characters,
    colors: bool,
    number_attrs: [9]c_int,  // for coloring the numbers that show how many mines are around
    status_message: ?[]const u8,

    pub fn init(game: *core.Game, window: curses.Window, characters: Characters, want_color: bool) !Ui {
        var self = Ui{
            .selected_x = 0,
            .selected_y = 0,
            .game = game,
            .window = window,
            .chars = characters,
            .colors = false,
            .number_attrs = undefined,
            .status_message = null,
        };
        try self.setupColors(want_color and curses.has_colors());
        return self;
    }

    fn setupColors(self: *Ui, use_colors: bool) !void {
        if (!use_colors) {
            @memset(&self.number_attrs, 0);
            return;
        }

        try curses.start_color();
        const colors = comptime[_]c_short{
            curses.COLOR_BLUE,
            curses.COLOR_GREEN,
            curses.COLOR_YELLOW,
            curses.COLOR_RED,
            curses.COLOR_CYAN,
            curses.COLOR_MAGENTA,
            curses.COLOR_MAGENTA,
            curses.COLOR_MAGENTA,
            curses.COLOR_MAGENTA,
        };
        std.debug.assert(colors.len == self.number_attrs.len);
        for (colors, 0..) |color, i| {
            const pair = try curses.ColorPair.init(@intCast(i+1), color, curses.COLOR_BLACK);
            self.number_attrs[i] = pair.attr();
        }
    }

    fn getWidth(self: *const Ui) u16 { return (self.game.width * @as(u16, "|---".len)) + @as(u16, "|".len); }
    fn getHeight(self: *const Ui) u16 { return (self.game.height * 2) + 1; }

    fn drawLine(self: *const Ui, y: u16, xleft: u16, left: []const u8, mid: []const u8, right: []const u8, horiz: []const u8) !void {
        var x: u16 = xleft;

        var i: u8 = 0;
        while (i < self.game.width) : (i += 1) {
            try self.window.mvaddstr(y, x, (if (i == 0) left else mid));
            x += 1;
            var j: u8 = 0;
            while (j < 3) : (j += 1) {
                try self.window.mvaddstr(y, x, horiz);
                x += 1;
            }
        }
        try self.window.mvaddstr(y, x, right);
    }

    fn drawGrid(self: *const Ui) !void {
        const top: u16 = (self.window.getmaxy() - self.getHeight()) / 2;
        const left: u16 = (self.window.getmaxx() - self.getWidth()) / 2;

        var gamey: u8 = 0;
        var y: u16 = top;
        while (gamey < self.game.height) : (gamey += 1) {
            if (gamey == 0) {
                try self.drawLine(y, left,
                    self.chars.corner_topleft, self.chars.crossing_down, self.chars.corner_topright,
                    self.chars.horiz_line);
            } else {
                try self.drawLine(y, left,
                    self.chars.crossing_right, self.chars.crossing_plus, self.chars.crossing_left,
                    self.chars.horiz_line);
            }
            y += 1;

            var x: u16 = left;
            var gamex: u8 = 0;
            while (gamex < self.game.width) : (gamex += 1) {
                var attrs: c_int = 0;
                if (gamex == self.selected_x and gamey == self.selected_y) {
                    attrs |= curses.A_STANDOUT;
                }

                const info = self.game.getSquareInfo(gamex, gamey);
                var msg1: []const u8 = "";
                var msg2: []const u8 = "";
                const numbers = "012345678";

                if ((self.game.status == core.GameStatus.PLAY and info.opened)
                 or (self.game.status != core.GameStatus.PLAY and !info.mine)) {
                    msg1 = numbers[info.n_mines_around..info.n_mines_around+1];
                    attrs |= self.number_attrs[info.n_mines_around];
                } else if (self.game.status == core.GameStatus.PLAY) {
                    if (info.flagged) {
                        msg1 = self.chars.flag;
                    }
                } else {
                    msg1 = self.chars.mine;
                    if (info.flagged) {
                        msg2 = self.chars.flag;
                    }
                }

                try self.window.mvaddstr(y, x, self.chars.vert_line);
                x += 1;

                try self.window.attron(attrs);
                {
                    try self.window.mvaddstr(y, x, "   ");  // make sure that all 3 character places get attrs
                    x += 1;
                    try self.window.mvaddstr(y, x, msg1);
                    x += 1;
                    try self.window.mvaddstr(y, x, msg2);
                    x += 1;
                }
                try self.window.attroff(attrs);
            }
            try self.window.mvaddstr(y, x, self.chars.vert_line);
            y += 1;
        }

        try self.drawLine(y, left,
            self.chars.corner_bottomleft, self.chars.crossing_up, self.chars.corner_bottomright,
            self.chars.horiz_line);
    }

    pub fn setStatusMessage(self: *Ui, msg: []const u8) void {
        self.status_message = msg;
    }

    // this may overlap the grid on a small terminal, it doesn't matter
    fn drawStatusText(self: *const Ui, msg: []const u8) !void {
        try self.window.attron(curses.A_STANDOUT);
        try self.window.mvaddstr(self.window.getmaxy()-1, 0, msg);
        try self.window.attroff(curses.A_STANDOUT);
    }

    pub fn draw(self: *Ui) !void {
        try self.drawGrid();

        if (self.status_message == null) {
            switch(self.game.status) {
                core.GameStatus.PLAY => {},
                core.GameStatus.WIN => self.setStatusMessage("You won! :D Press n to play again."),
                core.GameStatus.LOSE => self.setStatusMessage("Game Over :( Press n to play again."),
            }
        }
        if (self.status_message) |msg| {
            try self.drawStatusText(msg);
            self.status_message = null;
        }
    }

    // returns whether to keep running the game
    pub fn onResize(self: *const Ui) !bool {
        if (self.window.getmaxy() < self.getHeight() or self.window.getmaxx() < self.getWidth()) {
            try curses.endwin();
            var stderr = std.io.getStdErr().writer();
            try stderr.print("Terminal is too small :( Need {}x{}.\n", .{ self.getWidth(), self.getHeight() });
            return false;
        }
        return true;
    }

    pub fn moveSelection(self: *Ui, xdiff: i8, ydiff: i8) void {
        switch (xdiff) {
            1 => if (self.selected_x != self.game.width-1) { self.selected_x += 1; },
            -1 => if (self.selected_x != 0) { self.selected_x -= 1; },
            0 => {},
            else => unreachable,
        }
        switch(ydiff) {
            1 => if (self.selected_y != self.game.height-1) { self.selected_y += 1; },
            -1 => if (self.selected_y != 0) { self.selected_y -= 1; },
            0 => {},
            else => unreachable,
        }
    }

    pub fn openSelected(self: *const Ui) void { self.game.open(self.selected_x, self.selected_y); }
    pub fn toggleFlagSelected(self: *const Ui) void { self.game.toggleFlag(self.selected_x, self.selected_y); }
    pub fn openAroundIfSafe(self: *const Ui) void { self.game.openAroundIfSafe(self.selected_x, self.selected_y); }
    pub fn openAroundEverythingSafe(self: *const Ui) void { self.game.openAroundEverythingSafe(); }
};
