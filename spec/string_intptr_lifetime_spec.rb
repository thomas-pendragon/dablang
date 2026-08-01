require 'spec_helper'

describe 'String-to-IntPtr lifetime contract' do
  let(:root) { File.expand_path('..', __dir__) }

  it 'binds the repaired cast to value-owned storage without changing adjacent conversions' do
    implementation = File.binread(File.join(root, 'src/cvm/main.cpp'))
    value_implementation = File.binread(File.join(root, 'src/cvm/dab_value.cpp'))

    expect(implementation).to include('return DabValue::allocate_string_intptr(value.string());')
    expect(implementation).not_to include('copy.data.intptr = (void *)value.string().c_str();')
    expect(value_implementation.scan('string_intptr_storage = other.string_intptr_storage;').length).to eq(2)
    expect(value_implementation).to include('string_intptr_storage.reset();')

    expect(implementation).to include('auto cstr        = strdup(str.c_str());')
    expect(implementation).to include('copy.data.intptr = &value.bytebuffer()[0];')
    expect(implementation).to include('DabValue::allocate_dynstr((const char *)value.data.intptr)')
  end

  it 'keeps the native regression in the normal and isolated sanitizer gates' do
    rakefile = File.binread(File.join(root, 'Rakefile'))
    address_gate = File.binread(File.join(root, 'lib/dab/address_sanitizer_gate.rb'))
    undefined_gate = File.binread(File.join(root, 'lib/dab/undefined_behavior_sanitizer_gate.rb'))

    expect(rakefile).to include(':string_intptr_lifetime_spec')
    expect(address_gate).to include('run_string_intptr_lifetime_regression')
    expect(undefined_gate).to include('run_string_intptr_lifetime_regression')
  end
end
