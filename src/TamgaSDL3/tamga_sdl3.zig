const c = @cImport(@cInclude("SDL3/SDL.h"));

// ---- init flags ----

pub const INIT_VIDEO:  u32 = c.SDL_INIT_VIDEO;
pub const INIT_AUDIO:  u32 = c.SDL_INIT_AUDIO;
pub const INIT_EVENTS: u32 = c.SDL_INIT_EVENTS;

// ---- window flags ----

pub const WINDOW_FULLSCREEN:         u64 = c.SDL_WINDOW_FULLSCREEN;
pub const WINDOW_RESIZABLE:          u64 = c.SDL_WINDOW_RESIZABLE;
pub const WINDOW_BORDERLESS:         u64 = c.SDL_WINDOW_BORDERLESS;
pub const WINDOW_VULKAN:             u64 = c.SDL_WINDOW_VULKAN;
pub const WINDOW_OPENGL:             u64 = c.SDL_WINDOW_OPENGL;
pub const WINDOW_HIGH_PIXEL_DENSITY: u64 = c.SDL_WINDOW_HIGH_PIXEL_DENSITY;

// ---- event type constants ----

pub const EVENT_QUIT:              u32 = c.SDL_EVENT_QUIT;
pub const EVENT_KEY_DOWN:          u32 = c.SDL_EVENT_KEY_DOWN;
pub const EVENT_KEY_UP:            u32 = c.SDL_EVENT_KEY_UP;
pub const EVENT_MOUSE_MOTION:      u32 = c.SDL_EVENT_MOUSE_MOTION;
pub const EVENT_MOUSE_BUTTON_DOWN: u32 = c.SDL_EVENT_MOUSE_BUTTON_DOWN;
pub const EVENT_MOUSE_BUTTON_UP:   u32 = c.SDL_EVENT_MOUSE_BUTTON_UP;

// ---- scancode constants ----

pub const SCANCODE_ESCAPE: u32 = c.SDL_SCANCODE_ESCAPE;
pub const SCANCODE_SPACE:  u32 = c.SDL_SCANCODE_SPACE;
pub const SCANCODE_A:      u32 = c.SDL_SCANCODE_A;
pub const SCANCODE_W:      u32 = c.SDL_SCANCODE_W;
pub const SCANCODE_S:      u32 = c.SDL_SCANCODE_S;
pub const SCANCODE_D:      u32 = c.SDL_SCANCODE_D;

// ---- mouse button constants ----

pub const MOUSE_LEFT:   u8 = 1;
pub const MOUSE_MIDDLE: u8 = 2;
pub const MOUSE_RIGHT:  u8 = 3;

// ---- lifecycle ----

pub fn init(flags: u32) bool {
    return c.SDL_Init(flags);
}

pub fn quit() void {
    c.SDL_Quit();
}

pub fn getError() []const u8 {
    return std.mem.span(c.SDL_GetError());
}

// ---- window ----

const SdlError = error{SdlFailed};

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

    pub fn getHandle(self: *const Window) *anyopaque {
        return @ptrCast(self.handle);
    }
};

// ---- renderer ----

pub const Renderer = struct {
    handle: *c.SDL_Renderer,

    pub fn create(win: Window) anyerror!Renderer {
        const handle = c.SDL_CreateRenderer(win.handle, null) orelse {
            return SdlError.SdlFailed;
        };
        return Renderer{ .handle = handle };
    }

    pub fn destroy(self: *Renderer) void {
        c.SDL_DestroyRenderer(self.handle);
    }

    pub fn clear(self: *Renderer) void {
        _ = c.SDL_RenderClear(self.handle);
    }

    pub fn present(self: *Renderer) void {
        _ = c.SDL_RenderPresent(self.handle);
    }

    pub fn setDrawColor(self: *Renderer, r: u8, g: u8, b: u8, a: u8) void {
        _ = c.SDL_SetRenderDrawColor(self.handle, r, g, b, a);
    }
};

// ---- events ----

pub const Event = struct {
    inner: c.SDL_Event = undefined,

    pub fn create() Event {
        return Event{};
    }

    pub fn poll(self: *Event) bool {
        return c.SDL_PollEvent(&self.inner);
    }

    pub fn getType(self: *const Event) u32 {
        return @intCast(self.inner.type);
    }

    // keyboard
    pub fn getScancode(self: *const Event) u32 {
        return @intCast(self.inner.key.scancode);
    }

    pub fn getKeyRepeat(self: *const Event) bool {
        return self.inner.key.repeat;
    }

    // mouse motion
    pub fn getMouseX(self: *const Event) f32 {
        return self.inner.motion.x;
    }

    pub fn getMouseY(self: *const Event) f32 {
        return self.inner.motion.y;
    }

    pub fn getMouseXRel(self: *const Event) f32 {
        return self.inner.motion.xrel;
    }

    pub fn getMouseYRel(self: *const Event) f32 {
        return self.inner.motion.yrel;
    }

    // mouse button
    pub fn getMouseButton(self: *const Event) u8 {
        return self.inner.button.button;
    }

    pub fn getMouseButtonDown(self: *const Event) bool {
        return self.inner.button.down;
    }
};

// ---- timing ----

pub fn getTicks() u64 {
    return c.SDL_GetTicks();
}

pub fn delay(ms: u32) void {
    c.SDL_Delay(ms);
}

const std = @import("std");
