require_relative '../setup.rb'
require_relative '../src/shared/args.rb'
require 'random-word'

$scope = $settings[:scope] || 'basic'
$functions = $settings[:functions]&.to_i || 5
$length = $settings[:length]&.to_i || 20

def generate_random_word(adjs = 0)
  adjs = Array.new(adjs) { |_n| RandomWord.adjs.next }
  (adjs + [RandomWord.nouns.next]).join('_')
end

$function_names = Array.new($functions) { generate_random_word(2) }

class FunctionContext
  def initialize(name)
    @name = name
    @args = [generate_random_word, generate_random_word]
  end

  def generate
    ret = []
    ret << "func #{@name}(" + @args.join(', ') + ')'
    ret << '{'
    $length.times do
      ret += generate_random_instruction.map { |str| "  #{str}" }
    end
    ret << '}'
    ret.join("\n")
  end

  def generate_random_instruction
    case rand(100)
    when 0...80
      generate_random_simple_instruction
    when 80...90
      generate_random_vardef
    else
      generate_random_if
    end
  end

  def generate_random_simple_instruction
    [generate_random_call]
  end

  def generate_random_vardef
    ret = 'var ' + generate_random_word + ' = ' + generate_random_value + ';'
    [ret]
  end

  def generate_random_if
    ret = []
    ret << 'if (' + generate_random_value + ')'
    ret << '{'
    5.times do
      ret += generate_random_simple_instruction.map { |str| "  #{str}" }
    end
    ret << '}'
    ret
  end

  def generate_random_call
    $function_names.sample + '(' + generate_random_value + ', ' + generate_random_value + ');'
  end

  def generate_random_value
    case rand(100)
    when 0...40
      rand(200).to_s
    when 40...80
      '"' + generate_random_word + '"'
    else
      @args.sample
    end
  end
end

$function_names.each do |name|
  puts FunctionContext.new(name).generate
  puts
end
