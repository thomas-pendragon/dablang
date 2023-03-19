require 'spec_helper'

require_relative '../../src/compiler/_requires'

describe DabNode do
  let(:test_object) do
    test_class = Class.new(DabNode) do
      attr_accessor :counter

      def initialize
        super
        self.counter = 0
      end

      def on_added
        self.counter += 1
      end

      def on_removed
        self.counter -= 1
      end
    end
    test_class.new
  end

  it 'calls on_added/on_removed hooks on clear' do
    expect(test_object.counter).to eq(0)

    parent = DabNode.new
    parent << test_object

    expect(test_object.counter).to eq(1)

    parent.clear

    expect(test_object.counter).to eq(0)
  end

  it 'calls on_added/on_removed hooks on remove!' do
    expect(test_object.counter).to eq(0)

    parent = DabNode.new
    parent << test_object

    expect(test_object.counter).to eq(1)

    test_object.remove!

    expect(test_object.counter).to eq(0)
  end
end
