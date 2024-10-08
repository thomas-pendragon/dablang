STANDARD_CLASSES = %w(
  Object
  String
  Fixnum
  Boolean
  NilClass
  Array
  Uint8
  Uint16
  Uint32
  Uint64
  Int8
  Int16
  Int32
  Int64
  Method
  IntPtr
  ByteBuffer
  LiteralString
  DynamicString
  Float
).freeze

STANDARD_CLASSES_MAP = STANDARD_CLASSES.each_with_index.map { |item, index| [index, item] }.to_h
STANDARD_CLASSES_REV = STANDARD_CLASSES.each_with_index.map { |item, index| [item, index] }.to_h

USER_CLASSES_OFFSET = 0x100
