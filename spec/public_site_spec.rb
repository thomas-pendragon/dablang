require 'spec_helper'

require 'fileutils'
require 'tmpdir'
require 'yaml'

require_relative '../lib/dab/public_site'

describe Dab::PublicSite::Contract do
  let(:project_root) { File.expand_path('..', __dir__) }

  def with_docs_copy
    Dir.mktmpdir('dab-public-site-contract') do |root|
      FileUtils.cp_r(File.join(project_root, 'docs'), root)
      workflow = File.join(root, '.github/workflows')
      FileUtils.mkdir_p(workflow)
      FileUtils.cp(File.join(project_root, '.github/workflows/ruby.yml'), workflow)
      yield root
    end
  end

  def manifest_path(root)
    File.join(root, Dab::PublicSite::MANIFEST_PATH)
  end

  def read_manifest(root)
    YAML.safe_load(File.binread(manifest_path(root)), aliases: false)
  end

  def write_manifest(root, manifest)
    File.binwrite(manifest_path(root), YAML.dump(manifest))
  end

  def validate(root)
    described_class.new(root: root).validate
  end

  it 'classifies every current page and uses explicit navigation' do
    result = validate(project_root)

    expect(result.errors).to eq([])
    expect(result.page_count).to eq(
      Dir[File.join(project_root, 'docs/**/*.md')].reject { |path| path.include?('/_') }.length
    )
  end

  it 'fails closed when a new documentation page is unclassified' do
    with_docs_copy do |root|
      File.binwrite(File.join(root, 'docs/new-page.md'), "---\ntitle: New page\n---\n")

      expect(validate(root).errors).to include('unclassified documentation page: new-page.md')
    end
  end

  it 'rejects implicit all-page navigation in the header' do
    with_docs_copy do |root|
      header = File.join(root, 'docs/_includes/header.html')
      File.binwrite(header, File.binread(header).gsub(
                              'site.data.public_site.navigation',
                              'site.pages'
                            ))

      expect(validate(root).errors).to include(
        'header must not enumerate implicit navigation via site.pages',
        'header must render the explicit public-site navigation manifest'
      )
    end
  end

  it 'rejects an internal page that is emitted or top-level navigable' do
    with_docs_copy do |root|
      config_path = File.join(root, 'docs/_config.yml')
      config = YAML.safe_load(File.binread(config_path), aliases: false)
      config.fetch('exclude').delete('address-sanitizer.md')
      File.binwrite(config_path, YAML.dump(config))

      manifest = read_manifest(root)
      manifest.fetch('navigation') << {
        'title' => 'AddressSanitizer',
        'target' => '/address-sanitizer.html',
      }
      write_manifest(root, manifest)

      expect(validate(root).errors).to include(
        'repository-only page is not excluded from Jekyll: address-sanitizer.md',
        'repository-only page is top-level navigable: address-sanitizer.md'
      )
    end
  end

  it 'rejects duplicate, broken, and unsafe navigation targets' do
    with_docs_copy do |root|
      manifest = read_manifest(root)
      manifest.fetch('navigation').push(
        {'title' => 'Duplicate', 'target' => '/building.html'},
        {'title' => 'Missing', 'target' => '/missing.html'},
        {'title' => 'Unsafe', 'target' => '//other.example/page'}
      )
      write_manifest(root, manifest)

      expect(validate(root).errors).to include(
        'duplicate navigation target: "/building.html"',
        'navigation target does not name a classified page: "/missing.html"',
        'navigation[5].target is unsafe: "//other.example/page"'
      )
    end
  end

  it 'rejects CNAME and canonical-domain drift' do
    with_docs_copy do |root|
      File.binwrite(File.join(root, 'docs/CNAME'), 'other.example')
      config_path = File.join(root, 'docs/_config.yml')
      config = YAML.safe_load(File.binread(config_path), aliases: false)
      config['url'] = 'https://other.example'
      File.binwrite(config_path, YAML.dump(config))

      expect(validate(root).errors).to include(
        'docs/CNAME must be exactly "dablang.net"',
        'Jekyll url must be "https://dablang.net"'
      )
    end
  end

  it 'keeps generated-page classification aligned with complete-gate ownership' do
    with_docs_copy do |root|
      manifest = read_manifest(root)
      manifest.fetch('pages').find { |page| page['source'] == 'vm/opcodes.md' }.delete('generated')
      write_manifest(root, manifest)

      expect(validate(root).errors).to include(
        'owned generated documentation is not declared generated: vm/opcodes.md'
      )
    end
  end
end

describe Dab::PublicSite::BuiltSite do
  let(:project_root) { File.expand_path('..', __dir__) }

  it 'fails when a declared public page is absent from the built site' do
    Dir.mktmpdir('dab-public-site-output') do |destination|
      result = described_class.new(root: project_root, destination: destination).validate

      expect(result.errors).to include('declared public page is missing from built site: index.html')
    end
  end
end
