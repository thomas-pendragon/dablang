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
  Int32
  Method
  IntPtr
  ByteBuffer
).freeze

STANDARD_CLASSES_REV = STANDARD_CLASSES.each_with_index.map { |item, index| [item, index] }.to_h

USER_CLASSES_OFFSET = 0x100
