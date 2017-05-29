require_relative '../shared/base_context.rb'

class DabAsmContext < DabBaseContext
  attr_accessor :numeric_labels

  def initialize(stream, context = nil, numeric_labels: false)
    super(stream, context)
    @numeric_labels = numeric_labels
  end

  def clone(new_context = nil)
    ret = super
    ret.numeric_labels = self.numeric_labels
    ret
  end

  def read_program
    ret = []
    until @stream.eof?
      if instr = read_instruction
        ret << instr
      elsif read_newline
      else
        raise 'unknown token'
      end
      @stream.skip_whitespace
    end
    ret
  end

  def read_instruction
    on_subcontext do |subcontext|
      label = subcontext.read_label
      subcontext.read_newline
      next unless op = subcontext.read_identifier
      arglist = subcontext.read_arglist
      next unless subcontext.read_newline
      {
        op: op,
        arglist: arglist,
        label: label,
      }
    end
  end

  def read_identifier_fname
    on_subcontext do |subcontext|
      next unless ident = subcontext.read_identifier(:extended)
      if subcontext.read_operator('=')
        ident += '='
      end
      ident
    end
  end

  def read_label
    return read_numeric_label if @numeric_labels

    on_subcontext do |subcontext|
      next unless identifier = subcontext.read_identifier(:extended)
      next unless subcontext.read_operator(':')
      identifier
    end
  end

  def read_numeric_label
    on_subcontext do |subcontext|
      next unless identifier = subcontext.read_fixnum
      next unless subcontext.read_operator(':')
      identifier
    end
  end

  def read_arglist
    _read_list(:read_arg)
  end

  def read_fixnum
    on_subcontext do |subcontext|
      next unless str = subcontext.read_number
      str.to_i
    end
  end

  def read_arg
    read_identifier_fname || read_fixnum || read_string
  end

  def _read_list(item_method, separator = ',')
    __read_list(item_method, separator, []) do |array, item, _|
      array << item
    end
  end
end
