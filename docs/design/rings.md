---
layout: page
title: Rings
exclude_from_nav: true
---

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

Last revised: 2017-05-19
