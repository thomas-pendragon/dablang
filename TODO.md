## PRIORITIES ##

1. fix Test CI stage, should not rebuild binaries (?)

2a. Compiler ring support
  - read binary images
    - add user class lookup
  - create program based on image
  - calculate new functions offset

2b. Ring support (look up java annotation processing)
  - let VM dump its binary image (+ tests)
    - dump new functions
    - dump class functions
  - let VM modify its internal functions and classes
  - multi layer example

3. example: generate database model entities from schema

4. register management (remove register stack)
5. dumping low-level ring code for inspection

6. VS 2013- compatibility

## Parser ##

- alternative syntax (end instead of {})
- optional semicolons
- keep comments (for formatter)
- in '.dabca' files, allow extra blank lines (`CODE:\n\nNOP`)

## Compiler

- unified cache invalidation
- change all `"S#{node_identifier.symbol_index}"` to `.asm_operand`

## Language/VM

- allow to define static functions
- limited number of registers
- typed registers
- explicit calls (IP/SP regs management)

## Formatter

## Disasm

- test for dumping strings as strings, not bytes

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

- COV should not steal opcode labels
- reorganize and rename opcodes

## Testing ##

- test frontend: don't show errors on should-fail test cases (eg. 59)

## CI ##

- prebuild/pretest tasks in gitlab.yml (early fail)
- new step: precompile examples

## Coverage ##

- measure `if` coverage
- rewrite coverage to be line-based, not opcode based

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
