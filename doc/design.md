Typed function calls.

Untyped arguments are always `Nullable<Object>` (`Object?`).

If an actual type is known (specified as concrete class `Foo!` either by compiler marking a concrete type or because `Foo` is a leaf), it uses static dispatch. Otherwise dynamic dispatch is used.

So for example

```
func foo(a)
{
    print(a.class_name);
}
```

initially we compile method

```
`foo_[Object?]`:
   - $a := GET_ARG0 [Object?]
   - $b := VIRT_CALL :class_name, $a
   - VIRT_CALL :print, $b
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
`foo_[LiteralString!]`:
   - <$a optimized away>
   - $b := "LiteralString" <because .class_name is pure>
   - STATIC_CALL :print_[LiteralString!], $b <which can be optimized to kernel print>
```
