const c = @cImport(@cInclude("SDL3/SDL.h"));
const std = @import("std");

// ---- error type ----

const SdlError = error{SdlFailed};

// ---- Scancode translation ----
// Translates SDL3 scancode integers to sequential Orhon Scancode enum indices.
// Order MUST match the `pub enum(u32) Scancode` declaration in tamga_sdl3.orh.
// Unknown/unmapped scancodes map to the last value (64 = Unknown).

const SCANCODE_A:         u32 = 0;
const SCANCODE_B:         u32 = 1;
const SCANCODE_C:         u32 = 2;
const SCANCODE_D:         u32 = 3;
const SCANCODE_E:         u32 = 4;
const SCANCODE_F:         u32 = 5;
const SCANCODE_G:         u32 = 6;
const SCANCODE_H:         u32 = 7;
const SCANCODE_I:         u32 = 8;
const SCANCODE_J:         u32 = 9;
const SCANCODE_K:         u32 = 10;
const SCANCODE_L:         u32 = 11;
const SCANCODE_M:         u32 = 12;
const SCANCODE_N:         u32 = 13;
const SCANCODE_O:         u32 = 14;
const SCANCODE_P:         u32 = 15;
const SCANCODE_Q:         u32 = 16;
const SCANCODE_R:         u32 = 17;
const SCANCODE_S:         u32 = 18;
const SCANCODE_T:         u32 = 19;
const SCANCODE_U:         u32 = 20;
const SCANCODE_V:         u32 = 21;
const SCANCODE_W:         u32 = 22;
const SCANCODE_X:         u32 = 23;
const SCANCODE_Y:         u32 = 24;
const SCANCODE_Z:         u32 = 25;
const SCANCODE_NUM1:      u32 = 26;
const SCANCODE_NUM2:      u32 = 27;
const SCANCODE_NUM3:      u32 = 28;
const SCANCODE_NUM4:      u32 = 29;
const SCANCODE_NUM5:      u32 = 30;
const SCANCODE_NUM6:      u32 = 31;
const SCANCODE_NUM7:      u32 = 32;
const SCANCODE_NUM8:      u32 = 33;
const SCANCODE_NUM9:      u32 = 34;
const SCANCODE_NUM0:      u32 = 35;
const SCANCODE_RETURN:    u32 = 36;
const SCANCODE_ESCAPE:    u32 = 37;
const SCANCODE_BACKSPACE: u32 = 38;
const SCANCODE_TAB:       u32 = 39;
const SCANCODE_SPACE:     u32 = 40;
const SCANCODE_F1:        u32 = 41;
const SCANCODE_F2:        u32 = 42;
const SCANCODE_F3:        u32 = 43;
const SCANCODE_F4:        u32 = 44;
const SCANCODE_F5:        u32 = 45;
const SCANCODE_F6:        u32 = 46;
const SCANCODE_F7:        u32 = 47;
const SCANCODE_F8:        u32 = 48;
const SCANCODE_F9:        u32 = 49;
const SCANCODE_F10:       u32 = 50;
const SCANCODE_F11:       u32 = 51;
const SCANCODE_F12:       u32 = 52;
const SCANCODE_DELETE:    u32 = 53;
const SCANCODE_RIGHT:     u32 = 54;
const SCANCODE_LEFT:      u32 = 55;
const SCANCODE_DOWN:      u32 = 56;
const SCANCODE_UP:        u32 = 57;
const SCANCODE_LCTRL:     u32 = 58;
const SCANCODE_LSHIFT:    u32 = 59;
const SCANCODE_LALT:      u32 = 60;
const SCANCODE_RCTRL:     u32 = 61;
const SCANCODE_RSHIFT:    u32 = 62;
const SCANCODE_RALT:      u32 = 63;
const SCANCODE_UNKNOWN:   u32 = 64;

// Translate an SDL3 scancode integer to the sequential Orhon Scancode index.
fn sdlScancodeToOrhon(sdl_sc: c_uint) u32 {
    return switch (sdl_sc) {
        4   => SCANCODE_A,
        5   => SCANCODE_B,
        6   => SCANCODE_C,
        7   => SCANCODE_D,
        8   => SCANCODE_E,
        9   => SCANCODE_F,
        10  => SCANCODE_G,
        11  => SCANCODE_H,
        12  => SCANCODE_I,
        13  => SCANCODE_J,
        14  => SCANCODE_K,
        15  => SCANCODE_L,
        16  => SCANCODE_M,
        17  => SCANCODE_N,
        18  => SCANCODE_O,
        19  => SCANCODE_P,
        20  => SCANCODE_Q,
        21  => SCANCODE_R,
        22  => SCANCODE_S,
        23  => SCANCODE_T,
        24  => SCANCODE_U,
        25  => SCANCODE_V,
        26  => SCANCODE_W,
        27  => SCANCODE_X,
        28  => SCANCODE_Y,
        29  => SCANCODE_Z,
        30  => SCANCODE_NUM1,
        31  => SCANCODE_NUM2,
        32  => SCANCODE_NUM3,
        33  => SCANCODE_NUM4,
        34  => SCANCODE_NUM5,
        35  => SCANCODE_NUM6,
        36  => SCANCODE_NUM7,
        37  => SCANCODE_NUM8,
        38  => SCANCODE_NUM9,
        39  => SCANCODE_NUM0,
        40  => SCANCODE_RETURN,
        41  => SCANCODE_ESCAPE,
        42  => SCANCODE_BACKSPACE,
        43  => SCANCODE_TAB,
        44  => SCANCODE_SPACE,
        58  => SCANCODE_F1,
        59  => SCANCODE_F2,
        60  => SCANCODE_F3,
        61  => SCANCODE_F4,
        62  => SCANCODE_F5,
        63  => SCANCODE_F6,
        64  => SCANCODE_F7,
        65  => SCANCODE_F8,
        66  => SCANCODE_F9,
        67  => SCANCODE_F10,
        68  => SCANCODE_F11,
        69  => SCANCODE_F12,
        76  => SCANCODE_DELETE,
        79  => SCANCODE_RIGHT,
        80  => SCANCODE_LEFT,
        81  => SCANCODE_DOWN,
        82  => SCANCODE_UP,
        224 => SCANCODE_LCTRL,
        225 => SCANCODE_LSHIFT,
        226 => SCANCODE_LALT,
        228 => SCANCODE_RCTRL,
        229 => SCANCODE_RSHIFT,
        230 => SCANCODE_RALT,
        else => SCANCODE_UNKNOWN,
    };
}

// ---- WindowHandle ----
// Mirrors the Orhon `pub struct WindowHandle { pub handle: Ptr(u8) }`.
// Returned by Window.getHandle() — downstream modules (vk3d) receive this struct.

pub const WindowHandle = struct {
    handle: *anyopaque,
};

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
    tag: u8,                // discriminator: TAG_* constants above
    key_scancode: u32,      // SDL scancode integer — Orhon layer maps to enum
    key_repeat: bool,
    mouse_x: f32,           // absolute cursor position
    mouse_y: f32,
    mouse_xrel: f32,        // relative delta since last motion event
    mouse_yrel: f32,
    mouse_button: u8,       // 1=left, 2=middle, 3=right
    mouse_down: bool,
    gamepad_which: u32,     // SDL_JoystickID cast to u32
    gamepad_axis: u8,       // axis index
    gamepad_axis_value: i16, // -32768..32767
    gamepad_button: u8,     // button index
    text: [32]u8,           // UTF-8 null-terminated text input
    window_w: i32,          // logical dimensions (WINDOW_RESIZED)
    window_h: i32,
    pixel_w: i32,           // pixel dimensions (WINDOW_PIXEL_SIZE_CHANGED for HiDPI)
    pixel_h: i32,
    timestamp: u64,         // SDL event timestamp in nanoseconds

    // ---- getter methods ----
    // Called by the bridge struct declarations in tamga_sdl3.orh.

    pub fn create() RawEvent {
        return std.mem.zeroes(RawEvent);
    }

    pub fn poll(self: *RawEvent) bool {
        return pollRawEvent(self);
    }

    pub fn getTag(self: *const RawEvent) u8 { return self.tag; }
    pub fn getKeyScancode(self: *const RawEvent) u32 { return self.key_scancode; }
    pub fn getKeyRepeat(self: *const RawEvent) bool { return self.key_repeat; }
    pub fn getMouseX(self: *const RawEvent) f32 { return self.mouse_x; }
    pub fn getMouseY(self: *const RawEvent) f32 { return self.mouse_y; }
    pub fn getMouseXRel(self: *const RawEvent) f32 { return self.mouse_xrel; }
    pub fn getMouseYRel(self: *const RawEvent) f32 { return self.mouse_yrel; }
    pub fn getMouseButton(self: *const RawEvent) u8 { return self.mouse_button; }
    pub fn getMouseDown(self: *const RawEvent) bool { return self.mouse_down; }
    pub fn getGamepadWhich(self: *const RawEvent) u32 { return self.gamepad_which; }
    pub fn getGamepadAxis(self: *const RawEvent) u8 { return self.gamepad_axis; }
    pub fn getGamepadAxisValue(self: *const RawEvent) i16 { return self.gamepad_axis_value; }
    pub fn getGamepadButton(self: *const RawEvent) u8 { return self.gamepad_button; }
    pub fn getText(self: *const RawEvent) []const u8 { return std.mem.span(@as([*:0]const u8, @ptrCast(&self.text))); }
    pub fn getWindowW(self: *const RawEvent) i32 { return self.window_w; }
    pub fn getWindowH(self: *const RawEvent) i32 { return self.window_h; }
    pub fn getPixelW(self: *const RawEvent) i32 { return self.pixel_w; }
    pub fn getPixelH(self: *const RawEvent) i32 { return self.pixel_h; }
    pub fn getTimestamp(self: *const RawEvent) u64 { return self.timestamp; }
};

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
            out.key_scancode = sdlScancodeToOrhon(ev.key.scancode);
            out.key_repeat = ev.key.repeat;
        },

        c.SDL_EVENT_KEY_UP => {
            out.tag = TAG_KEY_UP;
            out.key_scancode = sdlScancodeToOrhon(ev.key.scancode);
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
            // Translate SDL3 button (1=left, 2=middle, 3=right) to Orhon MouseButton (0=left, 1=middle, 2=right)
            out.mouse_button = if (ev.button.button > 0) ev.button.button - 1 else 0;
            out.mouse_down = true;
            out.mouse_x = ev.button.x;
            out.mouse_y = ev.button.y;
        },

        c.SDL_EVENT_MOUSE_BUTTON_UP => {
            out.tag = TAG_MOUSE_BUTTON_UP;
            out.mouse_button = if (ev.button.button > 0) ev.button.button - 1 else 0;
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
        return WindowHandle{ .handle = @ptrCast(self.handle) };
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

pub fn initPlatform() anyerror!bool {
    // Always initialize VIDEO, EVENTS, and GAMEPAD subsystems together.
    // GAMEPAD subsystem must be initialized at startup — cannot be added later (Pitfall 4).
    if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS | c.SDL_INIT_GAMEPAD)) {
        return error.SdlFailed;
    }
    return true;
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
