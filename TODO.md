## Parser ##

- `if(true)` should pass
- allow semicolon after class/function
- alternative syntax (end instead of {})
- optional semicolons
- not require semicolons after if
- keep comments (for formatter)

## Compiler

- test: var<String> a; a = 15 should error
- test: self outside of class method should error

## New tools ##

- IDE
- package management
- game demo
- web demo
- separate debugging app
    - ncurses
    - disassembler support

## Language ##

- || && should short-circuit
- void calls
- type: hash
- type: set
- type: range
- type: regexp
- class parameters (Foo<String>)
    - typed arrays
- nullables and non-null force
- constructors/destructors
- subclassing
    - function override
        - final functions
- function overloads
- default arguments
- exceptions
- keyword arguments
- functions with blocks

## Standard library ##

- Array.sort
- Array.max
- Array.min
- Array.join should take parameter

## VM ##

- `==` and `!=` operators on mismatching types
- breakpoints

## Testing ##

- test frontend: don't show errors on should-fail test cases (eg. 59)

## CI ##

- prebuild/pretest tasks in gitlab.yml (early fail)

## Misc ##

- endianness in cvm/main.cpp
- return values should be reserved on stack
- negative offsets for JMP
- autogenerate kernel C enums
- property getters/instance calls as instructions
- specs for locating line/column for parsed nodes
- rename KERNELCALL to SYSCALL
- offset-based instance variables
- typed instance variables
- weak instance variables
- automatic reference counting
	- weak pointers
		- weak arrays
- native compilation
- lexer: pass actual EOF mark to compiler (see 59)
