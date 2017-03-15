## Parser ##

- `if(true)` should pass
- allow semicolon after class/function
- alternative syntax (end instead of {})
- optional semicolons
- not require semicolons after if

## Compiler

- test: var<String> a; a = 15 should error
- test: self outside of class method should error

## New tools ##

- automatic formatting
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
- setters
    - Array []=
- nullables and non-null force
- constructors/destructors
- subclassing
    - function override
        - final functions
- function overloads
- default arguments
- exceptions
- keyword arguments

## Standard library ##

- Array.first
- Array.last
- Array.sort
- Array.max
- Array.min
- Array.join

## VM ##

## CI ##

- prebuild/pretest tasks in gitlab.yml (early fail)

## Misc ##

- dumping AST tree before and after postprocessing
- endianness in cvm/main.cpp
- return values should be reserved on stack
- negative offsets for JMP
- autogenerate kernel C enums
- property getters/instance calls as instructions
- specs for locating line/column for parsed nodes
- remove booleans from constant section
- rename KERNELCALL to SYSCALL
- offset-based instance variables
- typed instance variables
- weak instance variables
- automatic reference counting
	- weak pointers
		- weak arrays
- native compilation
- test frontend: don't show errors on should-fail test cases (eg. 59)
- lexer: pass actual EOF mark to compiler (see 59)
