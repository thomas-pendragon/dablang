require_relative '../setup'
require_relative '../src/shared/system'

clang_format_app = ENV['CLANG_FORMAT'] || 'clang-format'

signatures = '
int32 -> int32
-> uint64
uint32 -> int32
void* -> int32
void* -> void
uint32 -> void
string -> uint64
void*, int32, uint32 -> void*
void*, uint8, uint8, uint8, uint8 -> int32
void*, int32, int32, int32, int32, -> int32
string, int32, int32, int32, int32, uint32 -> void*
int32, int32, int32 -> int32
int32, int32, int32, void*, int32 -> int32
int32, void*, int32 -> int32
int32, int32 -> int32
int32, void*, void* -> int32
int32, void*, uint64 -> uint64
string -> void*
void* -> uint32
void* -> string
void*, string -> void*
void*, string -> int32
void*, int32, int32 -> void*
void*, int32, int32 -> int32
void*, string, int32, void*, void*, void*, void*, int32 -> void*
'

DAB_CLASSES = {
  'int8' => 'CLASS_INT8',
  'int16' => 'CLASS_INT16',
  'int32' => 'CLASS_INT32',
  'int64' => 'CLASS_INT64',
  'uint8' => 'CLASS_UINT8',
  'uint16' => 'CLASS_UINT16',
  'uint32' => 'CLASS_UINT32',
  'uint64' => 'CLASS_UINT64',
  'void*' => 'CLASS_INTPTR',
  'string' => 'CLASS_STRING',
  'void' => 'CLASS_NILCLASS',
}.freeze

C_CLASSES = {
  'int8' => 'int8_t',
  'int16' => 'int16_t',
  'int32' => 'int32_t',
  'int64' => 'int64_t',
  'uint8' => 'uint8_t',
  'uint16' => 'uint16_t',
  'uint32' => 'uint32_t',
  'uint64' => 'uint64_t',
  'void*' => 'void*',
  'string' => 'const char*',
  'void' => 'void',
}.freeze

DAB_DATA = {
  'int32' => 'data.num_int32',
  'uint8' => 'data.num_uint8',
  'uint32' => 'data.num_uint32',
  'uint64' => 'data.num_uint64',
  'void*' => 'data.intptr',
  'string' => 'string().c_str()',
}.freeze

class Hash
  def safe_get(key)
    raise "no #{key}" unless key?(key)

    self[key]
  end
end

signatures.strip.split("\n").each do |line|
  body = ''

  args, ret = line.split('->').map(&:strip)
  args = args&.split(',')&.map(&:strip)

  voidret = ret == 'void'

  body += 'else if (arg_klasses.size() == ' + args.count.to_s
  args.each_with_index do |arg, index|
    body += " && arg_klasses[#{index}] == #{DAB_CLASSES.safe_get(arg)}"
  end
  body += " && ret_klass == #{DAB_CLASSES.safe_get(ret)})\n"
  body += "{\n"
  body += "    typedef #{C_CLASSES.safe_get(ret)} (*int_fun)("
  body += args.map do |arg|
    C_CLASSES[arg]
  end.join(', ')
  body += ");\n"
  body += "    auto int_symbol = (int_fun)symbol;\n\n"

  args.to_enum.with_index.each do |arg, index|
    body += "    auto value#{index} = $VM->cast(args[#{index}], #{DAB_CLASSES.safe_get(arg)});\n"
  end

  body += "\n"

  args.each_with_index do |arg, index|
    body += "    auto value#{index}_data = value#{index}.#{DAB_DATA.safe_get(arg)};\n"
  end

  body += "\n"

  body += '    '
  body += 'auto return_value = ' unless voidret
  body += '(*int_symbol)('
  body += Array.new(args.count) { |n| "value#{n}_data" }.join(', ')
  body += ");\n"

  body += "\n"

  body += '    return ('
  body += if voidret
            'DabValue(nullptr)'
          else
            "DabValue(#{DAB_CLASSES.safe_get(ret)}, return_value)"
          end
  body += ");\n"

  body += "}\n"

  format_body = body

  IO.popen(clang_format_app, 'r+') do |pipe|
    pipe.puts body
    pipe.close_write
    format_body = pipe.read
  end

  puts format_body
end
