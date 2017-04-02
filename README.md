Dab programming language

[![Build Status](https://travis-ci.org/thomas-pendragon/dablang.svg?branch=master)](https://travis-ci.org/thomas-pendragon/dablang)

Very early prototype, with compiler and assembler written in Ruby, and VM in C++.

MIT license

## Design

Few words about the language design.

### Purpose of the language

For many years I've believed that we need something like "smarter C" or "modern C++". Then I've started to use Ruby, and loved it. However, the performance was not good enough to use it as an only language. I've tried to write an optimizing Ruby compiler, only to discover that by the very definition, Ruby can't be fast (it can be *fast enough* though). 

So, the basic idea is that you can use Dab to create everything - from low-level, close to the metal code to high-level DSL-based applications. Optimize for productivity first, and for performance only if necessary.

### Type system

Strong typing. Optional static typing. The compiler will try to deduct types by itself. All functions are initially compiled to a universal implementation that checks types in the runtime, and then if (possible) precise types are known, specialized version are created.

Typed objects don't accept `nil` by default:

- `String` will accept any `String` or any subclass of `String`
- `String?` will also accept `nil`
- `String!` will accept only concrete objects of type `String`, but not subclasses

If `MyClass` is a leaf (final) class, then `MyClass` is equal to `MyClass!`.

### Rings

A huge drawback of nearly all dynamic languages is runtime evaluation. If you create classes or methods in the runtime, the compiler cannot check or optimize them, the IDE cannot help you with the syntax, etc.

However the metaprogramming is a very useful technique, and Dab relies on it heavily. The implementation is however very different, as Dab creates programs from layers called Rings.

The first Ring is always just the Dab virtual kernel (and super minimal runtime). You decide what goes into each of the following Rings. You can either import an external library, or you can create the Ring from your own code. As an example, you can have the following setup:

- `Ring0` - kernel and minimal runtime
- `Ring1` - standard library
- `Ring2` - web development framework
- `Ring3` - your application metaprogramming code:

(syntax to be revised later)
```
@["foo", "bar", "xyz"].each do |name|
  define_method("method_#{name}") do
    print "Hello #{name}!"
  end
end
```

- `Ring4` - your application code

When you work on your application code (`Ring4`), you have access to all standard library methods, your web framework of choice, and also all "dynamically" created methods. That means that the Dab compiler will be able to optimize `method_foo` calls, the IDE autocompletion will work, etc.

Also, Rings are used as a caching mechanism, allowing for faster build times, because usually, you will be working only on the last Ring (application) code.
