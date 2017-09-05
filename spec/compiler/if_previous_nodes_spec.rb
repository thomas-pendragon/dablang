require 'spec_helper'

require_relative '../../src/compiler/_requires.rb'

describe DabNodeIf do
  context '[flat]' do
    before :each do
      @true_symbol = DabNodeSymbol.new(:find_true)
      @false_symbol = DabNodeSymbol.new(:find_false)

      true_branch = DabNodeTreeBlock.new << :before_true << @true_symbol << :after_true
      false_branch = DabNodeTreeBlock.new << :before_false << @false_symbol << :after_false

      if_node = DabNodeIf.new(:condition, true_branch, false_branch)

      @tree = DabNodeTreeBlock.new << :before_if << if_node << :after_if
    end

    it 'performs a correct lookup of previous nodes for if_true branch' do
      array = [':before_if', ':condition', ':before_true']
      expect(@true_symbol.previous_nodes(DabNodeSymbol).map(&:extra_dump)).to eq array
    end

    it 'performs a correct lookup of previous nodes for if_false branch' do
      array = [':before_if', ':condition', ':before_false']
      expect(@false_symbol.previous_nodes(DabNodeSymbol).map(&:extra_dump)).to eq array
    end
  end

  context '[tree]' do
    before :each do
      @true_symbol = DabNodeSymbol.new(:find_true)
      @false_symbol = DabNodeSymbol.new(:find_false)

      true_tree = DabNodeTreeBlock.new << :before_true_tree << @true_symbol << :after_true_tree
      false_tree = DabNodeTreeBlock.new << :before_false_tree << @false_symbol << :after_false_tree

      true_branch = DabNodeTreeBlock.new << :before_true << true_tree << :after_true
      false_branch = DabNodeTreeBlock.new << :before_false << false_tree << :after_false

      if_node = DabNodeIf.new(:condition, true_branch, false_branch)

      @tree = DabNodeTreeBlock.new << :before_if << if_node << :after_if
    end

    it 'performs a correct lookup of previous nodes for if_true branch' do
      array = [':before_if', ':condition', ':before_true', ':before_true_tree']
      expect(@true_symbol.previous_nodes(DabNodeSymbol).map(&:extra_dump)).to eq array
    end

    it 'performs a correct lookup of previous nodes for if_false branch' do
      array = [':before_if', ':condition', ':before_false', ':before_false_tree']
      expect(@false_symbol.previous_nodes(DabNodeSymbol).map(&:extra_dump)).to eq array
    end
  end
end
