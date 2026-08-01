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
      FileUtils.cp(File.join(project_root, 'README.md'), root)
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

  it 'keeps the planned public content classified, linked, ordered, and explicitly provisional' do
    result = validate(project_root)

    expect(result.errors).to eq([])
  end

  it 'fails closed when the planned public content loses its product status, order, links, or state boundary' do
    with_docs_copy do |root|
      manifest = read_manifest(root)
      manifest.fetch('pages').find { |page| page['source'] == 'wordfreq.md' }['classification'] = 'public_reference'
      manifest['navigation'].reverse!
      write_manifest(root, manifest)

      index = File.join(root, 'docs/index.md')
      File.binwrite(index, File.binread(index).sub('## Planned Dab 0.1', '## Dab roadmap'))
      wordfreq = File.join(root, 'docs/wordfreq.md')
      File.binwrite(wordfreq, File.binread(wordfreq).sub('not implemented and not yet canonical Dab 0.1 source', 'an accepted source'))

      expect(validate(root).errors).to include(
        'public content page has wrong classification: wordfreq.md',
        'public navigation must preserve the declared product order',
        'public content must distinguish "Planned Dab 0.1": docs/index.md',
        'wordfreq reference must remain explicitly provisional and unimplemented'
      )
    end
  end

  it 'reports one stable schema error when navigation is not an array' do
    ['Dab 0.1', {'title' => 'Dab 0.1'}].each do |invalid_navigation|
      with_docs_copy do |root|
        manifest = read_manifest(root)
        manifest['navigation'] = invalid_navigation
        write_manifest(root, manifest)

        expect(validate(root).errors).to eq(['navigation must be an array'])
      end
    end
  end

  it 'accepts formatting changes while still requiring public-content cross-links' do
    with_docs_copy do |root|
      readme = File.join(root, 'README.md')
      File.binwrite(readme, File.binread(readme).gsub(
                              '[planned Dab 0.1 acceptance contract](docs/dab-0.1.md)',
                              '[planned Dab 0.1 acceptance contract]( <docs/dab-0.1.md> )'
                            ))

      expect(validate(root).errors).to eq([])
    end
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

  it 'requires the responsive editorial shell and accessibility hooks' do
    with_docs_copy do |root|
      default_layout = File.join(root, 'docs/_layouts/default.html')
      default_source = File.binread(default_layout)
                           .gsub('class="skip-link"', 'class="removed"')
                           .gsub('tabindex="-1"', 'tabindex="0"')
      File.binwrite(default_layout, default_source)
      stylesheet = File.join(root, 'docs/assets/main.scss')
      File.binwrite(stylesheet, File.binread(stylesheet).gsub('@media (prefers-reduced-motion: reduce)', '@media print'))
      header = File.join(root, 'docs/_includes/header.html')
      File.binwrite(header, File.binread(header).gsub('/vm/opcodes.html', '/removed.html'))
      footer = File.join(root, 'docs/_includes/footer.html')
      File.binwrite(footer, File.binread(footer).gsub('{{ site.author_bio | escape }}', 'Biography removed'))
      File.binwrite(stylesheet, File.binread(stylesheet).gsub('background: transparent;',
                                                              'background: #eef;'))
      File.binwrite(stylesheet, File.binread(stylesheet).gsub('margin-bottom: 0;',
                                                              'margin-bottom: 15px;'))
      config_path = File.join(root, 'docs/_config.yml')
      config = YAML.safe_load(File.binread(config_path), aliases: false)
      config.delete('author_bio')
      File.binwrite(config_path, YAML.dump(config))

      expect(validate(root).errors).to include(
        'default layout must include the skip link',
        'default layout must include a focusable main content landmark',
        'mobile header must link to the VM opcode reference',
        'shared footer must include the author biography and profile links',
        'Jekyll author_bio must be a non-empty string',
        'public-site stylesheet must reset nested code styling',
        'public-site stylesheet must collapse nested code-block spacing',
        'public-site stylesheet must preserve focus and reduced-motion handling'
      )
    end
  end

  it 'allows required shell hooks to coexist with additional classes' do
    with_docs_copy do |root|
      default_layout = File.join(root, 'docs/_layouts/default.html')
      default_source = File.binread(default_layout)
                           .gsub('class="site-shell"', 'class="site-shell theme-dark"')
                           .gsub('{%- include footer.html -%}', '{% include footer.html %}')
      File.binwrite(default_layout, default_source)
      stylesheet = File.join(root, 'docs/assets/main.scss')
      stylesheet_source = File.binread(stylesheet)
                              .gsub('@media (max-width: 850px)', '@media(max-width:850px)')
                              .gsub('@media (max-width: 560px)', '@media ( max-width : 560px )')
                              .gsub('@media (prefers-reduced-motion: reduce)',
                                    '@media(prefers-reduced-motion:reduce)')
      File.binwrite(stylesheet, stylesheet_source)

      expect(validate(root).errors).to eq([])
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
        'navigation[7].target is unsafe: "//other.example/page"'
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
