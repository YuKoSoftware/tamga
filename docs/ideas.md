# Language Ideas

- Should we have a separate folder for compiled dynamic libraries? (clutters src dir)

- When a dynamic lib gets compiled, it gets an interface file — should the interface be tagged as `interface` instead of `module`?

- Union spreading: let a union be composed from other unions. e.g. `pub const GuiEvent: type = (...InputEvent | ButtonClickEvent | ScrollEvent)` where InputEvent is itself a union. Flattens at compile time. Useful for building event hierarchies across modules without repeating every type. Syntax TBD (spread operator `...`, or a keyword like `expand`).

- Remove `#bitsize` metadata: bare numeric literals should always require explicit type annotations. Type aliases (`type Int = i32`) fill the convenience gap without hidden magic. `#bitsize` causes cross-module surprises (module A = 32, module B = 64 → same literal, different types) and adds a concept that the type system already handles better.
