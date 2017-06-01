## Parser ##

- alternative syntax (end instead of {})
- optional semicolons
- keep comments (for formatter)

## Compiler

- blocks should add implicit `return nil`

## Formatter


## New tools ##

- IDE
- package management
- game demo
- web demo
- separate debugging app
    - ncurses
    - disassembler support

## Language ##

- block support for C functions
- retrieving block return value
- comparing `"abc" > 123`
- Rings support
- void calls
- type: hash
- type: set
- type: range
- type: regexp
- class parameters (Foo<String>)
    - typed arrays
- nullables and non-null force
- constructors/destructors
- subclassing: final functions
- subclassing: final classes
- subclassing: check if inheriting from the same class on duplicates
- default arguments
- exceptions
- keyword arguments
- namespaces
- raw pointers, byte operations
- FFI

## Standard library ##

- Array.sort
- Array.max
- Array.min
- Array.join should take parameter

## VM ##

- breakpoints
- use exceptions

## Assembler ##

- remove `NOP`s, merge labels

## Testing ##

- test frontend: don't show errors on should-fail test cases (eg. 59)

## CI ##

- prebuild/pretest tasks in gitlab.yml (early fail)
- test formatting in /stdlib

## Coverage ##

- measure `if` coverage

## Misc ##

- endianness in cvm/main.cpp
- return values should be reserved on stack
- autogenerate kernel C enums
- property getters/instance calls as instructions
- specs for locating line/column for parsed nodes
- offset-based instance variables
- typed instance variables
- weak instance variables
- automatic reference counting
	- weak pointers
		- weak arrays
- native compilation
- lexer: pass actual EOF mark to compiler (see 59)
