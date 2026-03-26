# Language Ideas

- Should we have a separate folder for compiled dynamic libraries? (clutters src dir)

- When a dynamic lib gets compiled, it gets an interface file — should the interface be tagged as `interface` instead of `module`?

- Union spreading: let a union be composed from other unions. e.g. `pub const GuiEvent: type = (...InputEvent | ButtonClickEvent | ScrollEvent)` where InputEvent is itself a union. Flattens at compile time. Useful for building event hierarchies across modules without repeating every type. Syntax TBD (spread operator `...`, or a keyword like `expand`).

- ~~Remove `#bitsize` metadata~~ — DONE: directive removed from compiler (2026-03-26)

- Allow comma-separated libraries in `#linkC`: `#linkC "vulkan, SDL3"` instead of multiple `#linkC` lines. Single string keeps the parser simple (no greedy multi-token issues with stray `"`). Split on `,` + trim in the directive handler. Library names never contain commas (C linker flags).
