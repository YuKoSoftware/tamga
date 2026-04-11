const c = @cImport(@cInclude("SDL3/SDL.h"));
const std = @import("std");

// ---- error type ----

const SdlError = error{SdlFailed};

// ---- WindowHandle ----
// Mirrors the Orhon `pub type WindowHandle = Ptr(u8)` type alias.
// Returned by Window.getHandle() — downstream modules (vk3d) receive this pointer directly.

pub const WindowHandle = *anyopaque;

// ---- DisplayInfo ----
// Mirrors the Orhon `pub struct DisplayInfo { pub x, y, width, height, scale }`.
// Returned by getDisplayInfo() — avoids mutable out-pointer bridge violation.

pub const DisplayInfo = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    scale: f32,
};

// ---- RawEvent tag constants ----
// Used as discriminator in RawEvent.tag — u8 so Orhon bridge can read without enums

pub const TAG_NONE:                 u8 = 0;
pub const TAG_QUIT:                 u8 = 1;
pub const TAG_KEY_DOWN:             u8 = 2;
pub const TAG_KEY_UP:               u8 = 3;
pub const TAG_MOUSE_MOTION:         u8 = 4;
pub const TAG_MOUSE_BUTTON_DOWN:    u8 = 5;
pub const TAG_MOUSE_BUTTON_UP:      u8 = 6;
pub const TAG_GAMEPAD_AXIS:         u8 = 7;
pub const TAG_GAMEPAD_BUTTON_DOWN:  u8 = 8;
pub const TAG_GAMEPAD_BUTTON_UP:    u8 = 9;
pub const TAG_GAMEPAD_ADDED:        u8 = 10;
pub const TAG_GAMEPAD_REMOVED:      u8 = 11;
pub const TAG_TEXT_INPUT:           u8 = 12;
pub const TAG_WINDOW_RESIZED:       u8 = 13;
pub const TAG_WINDOW_PIXEL_RESIZED: u8 = 14;
pub const TAG_WINDOW_CLOSE:         u8 = 15;

// ---- RawEvent struct ----
// Flat discriminated struct — translates SDL_Event union into primitive-only fields.
// No SDL3 C types cross the bridge boundary.

pub const RawEvent = struct {
    pub tag: u8,                // discriminator: TAG_* constants above
    pub key_scancode: u32,      // SDL scancode integer — Orhon layer maps to enum
    pub key_repeat: bool,
    pub mouse_x: f32,           // absolute cursor position
    pub mouse_y: f32,
    pub mouse_xrel: f32,        // relative delta since last motion event
    pub mouse_yrel: f32,
    pub mouse_button: u8,       // 1=left, 2=middle, 3=right
    pub mouse_down: bool,
    pub gamepad_which: u32,     // SDL_JoystickID cast to u32
    pub gamepad_axis: u8,       // axis index
    pub gamepad_axis_value: i16, // -32768..32767
    pub gamepad_button: u8,     // button index
    pub text: [32]u8,           // UTF-8 null-terminated text input
    pub window_w: i32,          // logical dimensions (WINDOW_RESIZED)
    pub window_h: i32,
    pub pixel_w: i32,           // pixel dimensions (WINDOW_PIXEL_SIZE_CHANGED for HiDPI)
    pub pixel_h: i32,
    pub timestamp: u64,         // SDL event timestamp in nanoseconds
};

pub fn createRawEvent() RawEvent {
    return std.mem.zeroes(RawEvent);
}

// ---- event polling ----

pub fn pollRawEvent(out: *RawEvent) bool {
    var ev: c.SDL_Event = undefined;
    if (!c.SDL_PollEvent(&ev)) return false;

    // zero-initialize all fields before filling tag-specific ones
    out.* = std.mem.zeroes(RawEvent);

    out.timestamp = ev.common.timestamp;

    switch (ev.type) {
        c.SDL_EVENT_QUIT => {
            out.tag = TAG_QUIT;
        },

        c.SDL_EVENT_KEY_DOWN => {
            out.tag = TAG_KEY_DOWN;
            out.key_scancode = @intCast(ev.key.scancode);
            out.key_repeat = ev.key.repeat;
        },

        c.SDL_EVENT_KEY_UP => {
            out.tag = TAG_KEY_UP;
            out.key_scancode = @intCast(ev.key.scancode);
            out.key_repeat = ev.key.repeat;
        },

        c.SDL_EVENT_MOUSE_MOTION => {
            out.tag = TAG_MOUSE_MOTION;
            out.mouse_x = ev.motion.x;
            out.mouse_y = ev.motion.y;
            out.mouse_xrel = ev.motion.xrel;
            out.mouse_yrel = ev.motion.yrel;
        },

        c.SDL_EVENT_MOUSE_BUTTON_DOWN => {
            out.tag = TAG_MOUSE_BUTTON_DOWN;
            out.mouse_button = ev.button.button;
            out.mouse_down = true;
            out.mouse_x = ev.button.x;
            out.mouse_y = ev.button.y;
        },

        c.SDL_EVENT_MOUSE_BUTTON_UP => {
            out.tag = TAG_MOUSE_BUTTON_UP;
            out.mouse_button = ev.button.button;
            out.mouse_down = false;
            out.mouse_x = ev.button.x;
            out.mouse_y = ev.button.y;
        },

        c.SDL_EVENT_GAMEPAD_AXIS_MOTION => {
            out.tag = TAG_GAMEPAD_AXIS;
            out.gamepad_which = @intCast(ev.gaxis.which);
            out.gamepad_axis = @intCast(ev.gaxis.axis);
            out.gamepad_axis_value = ev.gaxis.value;
        },

        c.SDL_EVENT_GAMEPAD_BUTTON_DOWN => {
            out.tag = TAG_GAMEPAD_BUTTON_DOWN;
            out.gamepad_which = @intCast(ev.gbutton.which);
            out.gamepad_button = @intCast(ev.gbutton.button);
        },

        c.SDL_EVENT_GAMEPAD_BUTTON_UP => {
            out.tag = TAG_GAMEPAD_BUTTON_UP;
            out.gamepad_which = @intCast(ev.gbutton.which);
            out.gamepad_button = @intCast(ev.gbutton.button);
        },

        c.SDL_EVENT_GAMEPAD_ADDED => {
            out.tag = TAG_GAMEPAD_ADDED;
            out.gamepad_which = @intCast(ev.gdevice.which);
        },

        c.SDL_EVENT_GAMEPAD_REMOVED => {
            out.tag = TAG_GAMEPAD_REMOVED;
            out.gamepad_which = @intCast(ev.gdevice.which);
        },

        c.SDL_EVENT_TEXT_INPUT => {
            out.tag = TAG_TEXT_INPUT;
            const src = std.mem.span(ev.text.text);
            const len = @min(src.len, out.text.len - 1);
            @memcpy(out.text[0..len], src[0..len]);
            out.text[len] = 0;
        },

        c.SDL_EVENT_WINDOW_RESIZED => {
            out.tag = TAG_WINDOW_RESIZED;
            out.window_w = ev.window.data1;
            out.window_h = ev.window.data2;
        },

        c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => {
            out.tag = TAG_WINDOW_PIXEL_RESIZED;
            out.pixel_w = ev.window.data1;
            out.pixel_h = ev.window.data2;
        },

        c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => {
            out.tag = TAG_WINDOW_CLOSE;
        },

        else => {
            out.tag = TAG_NONE;
        },
    }

    return true;
}

// ---- Window struct ----

pub const Window = struct {
    handle: *c.SDL_Window,

    pub fn create(title: []const u8, w: i32, h: i32, flags: u64) anyerror!Window {
        // copy into a null-terminated stack buffer — SDL3 needs const char*
        var buf: [512]u8 = undefined;
        const len = @min(title.len, buf.len - 1);
        @memcpy(buf[0..len], title[0..len]);
        buf[len] = 0;

        const handle = c.SDL_CreateWindow(@ptrCast(&buf), @intCast(w), @intCast(h), flags) orelse {
            return SdlError.SdlFailed;
        };
        return Window{ .handle = handle };
    }

    pub fn destroy(self: *Window) void {
        c.SDL_DestroyWindow(self.handle);
    }

    pub fn setTitle(self: *Window, title: []const u8) void {
        var buf: [512]u8 = undefined;
        const len = @min(title.len, buf.len - 1);
        @memcpy(buf[0..len], title[0..len]);
        buf[len] = 0;
        _ = c.SDL_SetWindowTitle(self.handle, @ptrCast(&buf));
    }

    pub fn getWidth(self: *const Window) i32 {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.SDL_GetWindowSize(self.handle, &w, &h);
        return @intCast(w);
    }

    pub fn getHeight(self: *const Window) i32 {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.SDL_GetWindowSize(self.handle, &w, &h);
        return @intCast(h);
    }

    pub fn getPixelWidth(self: *const Window) i32 {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.SDL_GetWindowSizeInPixels(self.handle, &w, &h);
        return @intCast(w);
    }

    pub fn getPixelHeight(self: *const Window) i32 {
        var w: c_int = 0;
        var h: c_int = 0;
        _ = c.SDL_GetWindowSizeInPixels(self.handle, &w, &h);
        return @intCast(h);
    }

    pub fn getDisplayScale(self: *const Window) f32 {
        return c.SDL_GetWindowDisplayScale(self.handle);
    }

    pub fn getHandle(self: *const Window) WindowHandle {
        return @ptrCast(self.handle);
    }

    pub fn setRelativeMouseMode(self: *const Window, enabled: bool) bool {
        return c.SDL_SetWindowRelativeMouseMode(self.handle, enabled);
    }

    pub fn startTextInput(self: *const Window) void {
        _ = c.SDL_StartTextInput(self.handle);
    }

    pub fn stopTextInput(self: *const Window) void {
        _ = c.SDL_StopTextInput(self.handle);
    }
};

// ---- cursor functions ----

pub fn hideCursor() void {
    _ = c.SDL_HideCursor();
}

pub fn showCursor() void {
    _ = c.SDL_ShowCursor();
}

// ---- gamepad functions ----

// Returns opaque handle to the opened gamepad, or a null pointer on failure.
// Caller must check for null before use (null = gamepad not available or already open).
pub fn openGamepad(id: u32) *anyopaque {
    const handle = c.SDL_OpenGamepad(@intCast(id)) orelse return @ptrFromInt(0);
    return @ptrCast(handle);
}

pub fn closeGamepad(handle: *anyopaque) void {
    c.SDL_CloseGamepad(@ptrCast(@alignCast(handle)));
}

// ---- display info functions ----

pub fn getDisplayCount() i32 {
    var count: c_int = 0;
    const displays = c.SDL_GetDisplays(&count);
    if (displays != null) {
        c.SDL_free(displays);
    }
    return @intCast(count);
}

// Returns display bounds and content scale as a single struct.
// Avoids mutable out-pointer bridge parameters (bridge safety rule: &T not allowed except self).
// Returns zeroed DisplayInfo on invalid index or failure.
pub fn getDisplayInfo(index: i32) DisplayInfo {
    var count: c_int = 0;
    const displays = c.SDL_GetDisplays(&count) orelse return std.mem.zeroes(DisplayInfo);
    defer c.SDL_free(displays);

    if (index < 0 or index >= count) return std.mem.zeroes(DisplayInfo);

    const display_id = displays[@intCast(index)];
    var rect: c.SDL_Rect = undefined;
    if (!c.SDL_GetDisplayBounds(display_id, &rect)) return std.mem.zeroes(DisplayInfo);

    return DisplayInfo{
        .x = @intCast(rect.x),
        .y = @intCast(rect.y),
        .width = @intCast(rect.w),
        .height = @intCast(rect.h),
        .scale = c.SDL_GetDisplayContentScale(display_id),
    };
}

pub fn getDisplayName(index: i32, out_buf: [*]u8, buf_len: usize) bool {
    var count: c_int = 0;
    const displays = c.SDL_GetDisplays(&count) orelse return false;
    defer c.SDL_free(displays);

    if (index < 0 or index >= count) return false;

    const display_id = displays[@intCast(index)];
    const name_ptr = c.SDL_GetDisplayName(display_id) orelse return false;
    const name = std.mem.span(name_ptr);
    const len = @min(name.len, buf_len - 1);
    @memcpy(out_buf[0..len], name[0..len]);
    out_buf[len] = 0;
    return true;
}

// ---- lifecycle ----

pub fn initPlatform() anyerror!void {
    // Always initialize VIDEO, EVENTS, and GAMEPAD subsystems together.
    // GAMEPAD subsystem must be initialized at startup — cannot be added later (Pitfall 4).
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS | c.SDL_INIT_GAMEPAD)) {
        return error.SdlFailed;
    }
}

pub fn quitPlatform() void {
    c.SDL_Quit();
}

pub fn getError() []const u8 {
    return std.mem.span(c.SDL_GetError());
}

// ---- timing ----

pub fn getTicksNS() u64 {
    return c.SDL_GetTicksNS();
}

pub fn delayNS(ns: u64) void {
    c.SDL_DelayNS(ns);
}

