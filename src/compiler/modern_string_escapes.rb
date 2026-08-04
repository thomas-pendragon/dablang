module DabModernStringEscapes
  NAMED_ENCODINGS = {
    '"' => '\\"',
    '\\' => '\\\\',
    "\n" => '\\n',
    "\r" => '\\r',
    "\t" => '\\t',
    "\b" => '\\b',
    "\f" => '\\f',
    "\v" => '\\v',
    "\a" => '\\a',
    "\e" => '\\e',
  }.freeze

module_function

  def encode(value)
    utf8 = value.b.dup.force_encoding(Encoding::UTF_8)
    unless utf8.valid_encoding?
      raise ArgumentError.new('Modern String rendering requires valid UTF-8')
    end
    if utf8.include?("\0")
      raise ArgumentError.new('Modern String rendering does not allow NUL')
    end

    characters = utf8.each_char.to_a
    encoded = +'"'.b
    index = 0
    while index < characters.length
      character = characters[index]
      if character == '#' && characters[index + 1] == '{'
        encoded << '\\#{'.b
        index += 2
        next
      end

      encoding = NAMED_ENCODINGS[character]
      codepoint = character.ord
      encoded_character = if encoding
                            encoding
                          elsif codepoint < 0x20 || codepoint.between?(0x7f, 0x9f)
                            sprintf('\\u{%X}', codepoint)
                          else
                            character
                          end
      encoded << encoded_character.b
      index += 1
    end
    encoded << '"'.b
  end
end
