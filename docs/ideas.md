# Language Ideas

- Should we have a separate folder for compiled dynamic libraries? (clutters src dir)

- When a dynamic lib gets compiled, it gets an interface file — should the interface be tagged as `interface` instead of `module`?

- Union spreading: let a union be composed from other unions. e.g. `pub const GuiEvent: type = (...InputEvent | ButtonClickEvent | ScrollEvent)` where InputEvent is itself a union. Flattens at compile time. Useful for building event hierarchies across modules without repeating every type. Syntax TBD (spread operator `...`, or a keyword like `expand`).

- Allow comma-separated libraries in `#linkC`: `#linkC "vulkan, SDL3"` instead of multiple `#linkC` lines. Single string keeps the parser simple (no greedy multi-token issues with stray `"`). Split on `,` + trim in the directive handler. Library names never contain commas (C linker flags).

- Bridge struct value-pass semantics: bridge structs that contain only GPU handles (VkImage, VkBuffer, etc. — opaque integer handles) are safe to pass by value even to "destroy" functions. The Vulkan spec makes handles opaque integers, not owning pointers. Consider documenting that bridge structs with only handle fields can be pass-by-value in the bridge without ownership risk. May be worth a lint rule: "bridge struct with only Ptr/opaque fields — value semantics safe."

- Enforce same-folder rule for module files: require all `.orh` files declaring the same `module` to live in the same directory as the anchor file. Currently the compiler groups by declaration regardless of path, but every project follows same-folder convention anyway. Enforcing it improves discoverability (`ls` shows all module files), makes tooling trivial (infer module from path), and catches mistyped `module` declarations. The anchor file rule already ties modules to directories implicitly — this just closes the loop.
