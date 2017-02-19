require 'spec_helper'

require_relative '../../src/shared/parser.rb'

describe DabParser do
  describe 'comments' do
    it 'should strip' do
      input = 'test/*abc*/foo'
      output = DabParser.new(input).content
      expect(output).to eq 'test foo'
    end

    it 'should not strip /*/' do
      input = 'test/*/foo'
      output = DabParser.new(input).content
      expect(output).to eq 'test/*/foo'
    end

    it 'should not crash on not closed' do
      input = 'test/* foo'
      output = DabParser.new(input).content
      expect(output).to eq 'test/* foo'
    end
  end
end
