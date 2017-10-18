## Parser ##

- alternative syntax (end instead of {})
- optional semicolons
- keep comments (for formatter)
- in '.dabca' files, allow extra blank lines (`CODE:\n\nNOP`)

## Compiler

- unified cache invalidation

## Language/VM

- register management (remove register stack)
- limited number of registers
- typed registers
- explicit calls (IP/SP regs management)

## Formatter

## Disasm

## new assembly format

- FUNC section should be allowed before actual functions

## Performance

- runtime performance specs
- optimize type lookup
- optimize SSA nodes

## New tools ##

- IDE
- package management
- web demo
- separate debugging app
    - ncurses
    - disassembler support
- automated OpenGL import
- automated libc import

## Language ##

- structures (with C memory mapping)
- comparing `"abc" > 123`
- Rings support
- extra opcodes for void calls
- class parameters (Foo<String>)
    - typed arrays
- nullables (`String?`) and checking if regular types (`String`) are not nil
- final type checks (`String!`)
- constructors/destructors should call whole chain
- constructors with parameters
- subclassing: final functions
- subclassing: final classes
- subclassing: check if inheriting from the same class on duplicates
- default arguments
- exceptions
  - yield without block should throw
- keyword arguments
- namespaces
- syntax for functions with required block
- common syntax for vars and arguments: `func foo(a<String>); var a<String>;`
- coroutines

## Standard library ##

- type: hash
- type: set
- type: range
- type: regexp
- Array.sort
- Array.max
- Array.min
- Array.join should take parameter

## VM ##

- code-based breakpoints (`__break()`)
- use exceptions
- debug: disasm should respect function boundary
- debug: should disasm single function at a time

## Assembler ##

## Testing ##

- test frontend: don't show errors on should-fail test cases (eg. 59)

## CI ##

- prebuild/pretest tasks in gitlab.yml (early fail)
- new step: precompile examples

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
- new format for Dab binary with headers
