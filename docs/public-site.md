---
layout: page
title: Public site publication contract
---

# Public site publication contract

`docs/_data/public_site.yml` classifies every documentation page as a public
product page, a public reference page, or a repository-only page. The same
manifest defines the ordered top-level navigation. Repository-only pages stay
tracked in `docs/`, but `docs/_config.yml` excludes them from the Jekyll build.

From a clean checkout, install the repository-pinned documentation bundle and
run the public-site validation from the repository root:

```shell
BUNDLE_GEMFILE=docs/Gemfile bundle install
BUNDLE_GEMFILE=docs/Gemfile bundle exec ruby script/public_site.rb
```

The validator rejects unclassified documentation pages, unsafe or duplicate
navigation targets, publication/exclusion drift, generated-documentation
ownership drift, and canonical-domain or CNAME changes. It also protects the
ordered public navigation and the public-content contract: the current 0.0.x
prototype, planned Dab 0.1 acceptance target, and Dab 1.0 design vision must
remain distinct; the acceptance and provisional `wordfreq` pages must remain
public and cross-linked; and aspirational README copy cannot stand in for
implementation evidence. The README and public product pages carry their key
language and release information directly: they do not expose internal
coordination names or send readers to the project Wiki for essential context.
The validator builds the site in a disposable directory and checks the
expected output, navigation, canonical URLs, and local links. It does not write
`docs/_site` or any tracked generated documentation.

The public pages share a responsive editorial shell defined by the local
layouts and `docs/assets/main.scss`. On wide screens it uses a persistent
project rail, explicit primary navigation, high-contrast display typography,
and a structured project footer. On narrow screens the rail collapses into a
compact header while every public destination remains reachable. The shell
uses semantic landmarks, a keyboard skip link, visible focus treatment, and
reduced-motion handling. This visual system does not change which pages are
public or make new claims about the language.
