require_relative '../shared/base_context.rb'

class DabAsmContext < DabBaseContext
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
      next unless ident = subcontext.read_identifier
      if subcontext.read_operator('=')
        ident += '='
      end
      ident
    end
  end

  def read_label
    on_subcontext do |subcontext|
      next unless identifier = subcontext.read_identifier
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
