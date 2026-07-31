---
layout: page
title: Complete validation gate
---

From the repository root, run the complete inherited validation gate with:

```shell
ruby script/complete_gate.rb
```

The command first runs the supported-toolchain preflight, then runs the
existing `bundle exec rake` build, fixture-test, and documentation gate without
omitting any of its current tasks. Each stage is announced before it runs;
failures stop the command immediately, preserve the failing stage's exit code,
and leave its diagnostics visible.

The command supports the same Linux, macOS, and Windows environments as the
preflight. Set `PREMAKE` and `CLANG_FORMAT` when the supported tools are not on
`PATH`, as described in the [supported toolchain preflight](/toolchain-preflight.html).

The inherited Rake gate can regenerate tracked documentation. Run the complete
gate in a disposable checkout when those generated-file changes must not affect
your working tree.

This gate intentionally does not run the standalone Ruby RSpec suite. Its
current meaning is preserved until the separately planned RSpec-gate work.
