---
layout: page
title: VM opcodes
exclude_from_nav: true
---
## NOP

|Opcode |Name    |Arguments|
|-------|--------|---------|
|`00`|`NOP`||

<br>
## MOV

|Opcode |Name    |Arguments|
|-------|--------|---------|
|`01`|`MOV`|`reg`, `reg`|
|`02`|`LOAD_NIL`|`reg`|
|`03`|`LOAD_TRUE`|`reg`|
|`04`|`LOAD_FALSE`|`reg`|
|`05`|`LOAD_UINT8`|`reg`, `uint8`|
|`06`|`LOAD_UINT16`|`reg`, `uint16`|
|`07`|`LOAD_UINT32`|`reg`, `uint32`|
|`08`|`LOAD_UINT64`|`reg`, `uint64`|
|`09`|`LOAD_INT8`|`reg`, `int8`|
|`0A`|`LOAD_INT16`|`reg`, `int16`|
|`0B`|`LOAD_INT32`|`reg`, `int32`|
|`0C`|`LOAD_INT64`|`reg`, `int64`|
|`0D`|`LOAD_CLASS`|`reg`, `uint16`|
|`0E`|`LOAD_CLASS_EX`|`reg`, `uint16`, `reglist`|
|`0F`|`LOAD_METHOD`|`reg`, `symbol`|
|`10`|`REFLECT`|`reg`, `symbol`, `uint16`, `uint16`|
|`11`|`LOAD_NUMBER`|`reg`, `uint64`|
|`12`|`LOAD_STRING`|`reg`, `uint64`, `uint64`|
|`13`|`NEW_ARRAY`|`reg`, `reglist`|
|`14`|`LOAD_SELF`|`reg`|
|`15`|`GET_INSTVAR`|`reg`, `symbol`|
|`16`|`LOAD_HAS_BLOCK`|`reg`|
|`17`|`LOAD_ARG`|`reg`, `uint16`|

<br>
## FLOW

|Opcode |Name    |Arguments|
|-------|--------|---------|
|`18`|`JMP`|`int16`|
|`19`|`JMP_IF`|`reg`, `int16`, `int16`|
|`1A`|`CALL`|`reg`, `symbol`, `reglist`|
|`1B`|`INSTCALL`|`reg`, `reg`, `symbol`, `reglist`|
|`1C`|`SYSCALL`|`reg`, `uint8`, `reglist`|
|`1D`|`RETURN`|`reg`|

<br>
## OTHER

|Opcode |Name    |Arguments|
|-------|--------|---------|
|`1E`|`RETAIN`|`reg`|
|`1F`|`RELEASE`|`reg`|
|`20`|`CAST`|`reg`, `reg`, `uint16`|
|`21`|`SET_INSTVAR`|`symbol`, `reg`|

<br>
## SPECIAL

|Opcode |Name    |Arguments|
|-------|--------|---------|
|`22`|`COV`|`uint16`, `uint16`|
|`23`|`STACK_RESERVE`|`uint16`|

<br>
## NEW

|Opcode |Name    |Arguments|
|-------|--------|---------|
|`24`|`LOAD_FLOAT`|`reg`, `float`|
|`25`|`LOAD_ARG_DEFAULT`|`reg`, `uint16`, `reg`|
|`26`|`LOAD_LOCAL_BLOCK`|`reg`, `reg`|
|`27`|`LOAD_CURRENT_BLOCK`|`reg`|
|`28`|`BOX`|`reg`, `reg`|
|`29`|`UNBOX`|`reg`, `reg`|
|`2A`|`SETBOX`|`reg`, `reg`, `reg`|
|`2B`|`GET_INSTVAR_EXT`|`reg`, `symbol`, `reg`|
|`2C`|`GET_CLASSVAR`|`reg`, `symbol`|
|`2D`|`SET_CLASSVAR`|`symbol`, `reg`|

<br>
Autogenerated from `src/shared/opcodes.rb`, last revised: 2024-10-08
