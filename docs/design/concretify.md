---
layout: page
title: Concretify
exclude_from_nav: true
---

Typed function calls.

Untyped arguments are always `Nullable<Object>` (`Object?`).

If an actual type is known (specified as concrete class `Foo!` either by compiler marking a concrete type or because `Foo` is a leaf), it uses static dispatch. Otherwise dynamic dispatch is used.

So for example

```
func foo(a)
{
  print(a.class);
}
```

initially we compile method

```
Ffoo:
  STACK_RESERVE 0
  PUSH_ARG 0
  PUSH_SYMBOL class
  INSTCALL 0, 1
  SYSCALL 0
  PUSH_NIL 
  RETURN 
```

However if we call this method in other function:

```
func main()
{
  foo("hello");
}
```

we recompile `foo` to

```
F__foo_LiteralString:
  STACK_RESERVE 0
  PUSH_STRING "LiteralString"
  SYSCALL 0
  PUSH_NIL 
  RETURN 
```
