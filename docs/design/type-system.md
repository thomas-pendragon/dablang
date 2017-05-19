---
layout: page
title: Type system
exclude_from_nav: true
---

Strong typing. Optional static typing. The compiler will try to deduct types by itself. All functions are initially compiled to a universal implementation that checks types in the runtime, and then if (possible) precise types are known, specialized version are created.

Typed objects don't accept `nil` by default:

- `String` will accept any `String` or any subclass of `String`
- `String?` will also accept `nil`
- `String!` will accept only concrete objects of type `String`, but not subclasses

If `MyClass` is a leaf (final) class, then `MyClass` is equal to `MyClass!`.