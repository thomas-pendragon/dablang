require 'spec_helper'

require_relative '../../src/shared/parser.rb'

describe DabParser do
  describe 'comments' do
    it 'should strip' do
      input = 'test/*abc*/foo'
      output = DabParser.new(input).non_comment_content
      expect(output).to eq 'test foo'
    end

    it 'should fail on /*/' do
      input = 'test/*/foo'
      parser = DabParser.new(input)
      expect { parser.non_comment_content }.to raise_error DabEndOfStreamError
    end

    it 'should not crash on not closed' do
      input = 'test/* foo'
      parser = DabParser.new(input)
      expect { parser.non_comment_content }.to raise_error DabEndOfStreamError
    end
  end
end
