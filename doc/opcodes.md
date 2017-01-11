VARIABLE LENGTH CODING

0-254 - direct
255 -> +8 bytes of length

[250] [250 bytes]

[255] [64bits: length = 1000] [1000 bytes]

VM FORMAT

all binary numbers are little endian

"DAB"
8 bytes: compiler version 
8 bytes: vm version
8 bytes: code length
8 bytes: code crc32

VM OPCODES

0x00 [VLC] - START FUNCTION + symbol name
0x01 [VLC] - CONSTANT SYMBOL + symbol name
0x02 [VLC] - CONSTANT STRING + string
0x03 [2bytes index into constants] - PUSH CONSTANT
0x04 [16bit] - CALL + number of arguments
0x05 - END FUNCTION