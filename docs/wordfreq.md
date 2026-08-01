---
layout: page
title: Provisional wordfreq reference program
---

# Provisional `wordfreq` Bare CLI

**Status:** executable design specimen; not implemented and not yet canonical Dab 0.1 source.<br>
**Program:** `wordfreq`<br>
**Layer:** bare CLI

This public reference reproduces the accepted provisional program so language
and standard-library discussions can critique complete code. It is a planned
Dab 0.1 acceptance specimen, not proof of current prototype behavior or of a
final API. The bounded target is described in the
[planned Dab 0.1 acceptance contract](/dab-0.1.html). The complete public
specimen and its open decisions are recorded directly on this page.

The source deliberately proposes names for APIs that have not been finalized.
Their presence below is not confirmation that the current prototype implements
them.

## Complete provisional source

```ruby
class UsageError < Error
end

class InputError < Error
end

class CommandLine
  public let @top : Int = 20
  public let @files : const Set[String] = {,}
  public let @help : Bool = false
  public let @stdin : Bool = false

  autoinitialize
end

class CommandLineParser
  private writable var @top : Int? = nil
  private let @files : Set[String] = {,}
  private let @remaining : Array[String]
  private writable var @option_mode = true
  private writable var @stdin = false

  initialize(values : const Array[out String])
    @remaining = values.shallow_copy
  end

  mutable def parse_arguments : CommandLine
    while !@remaining.empty?
      let argument = @remaining.shift!

      unless option_mode?
        add_source!(argument)
        next
      end

      case argument
      when "-"
        @stdin = true
      when "--"
        @option_mode = false
      when "--help", "-h"
        return CommandLine.new(help: true)
      when "--top", "-n"
        raise UsageError.new("missing value for #{argument}") if @remaining.empty?
        @top = parse_top(@remaining.shift!)
      when /^--top=/
        @top = parse_top(argument.delete_prefix("--top="))
      when /^-/
        raise UsageError.new("unknown option: '#{argument}'")
      else
        add_source!(argument)
      end
    end

    CommandLine.new(
      top?: @top,
      files: @files,
      stdin: stdin? || @files.empty?
    )
  end

  private def add_source!(argument : String)
    @files.add!(argument)
  end

  private def parse_top(text : String) : Int
    raise UsageError.new("--top may be specified only once") unless @top.nil?

    let value : Int? = Int.parse(text)

    raise UsageError.new("invalid value for --top: '#{text}'") if value.nil?
    raise UsageError.new("--top must be non-negative: '#{text}'") if value < 0

    value
  end
end

class Counter
  let @counts : Map[String, Int] = {}

  def counts : const Map[String, Int]
    @counts
  end

  def process!(input : InputStream)
    let decoder = UTF8.strict_decoder
    let segmenter = Unicode.default_word_segmenter

    decoder.on_decode do |text|
      segmenter.push!(text)
    end

    segmenter.on_segment do |segment|
      count_segment!(segment)
    end

    segmenter.process do
      decoder.process do
        input.each_chunk do |bytes|
          decoder.push!(bytes)
        end
      end
    end
  end

  private def counted_segment?(segment : String)
    segment.any? do |character|
      character.letter? || character.number?
    end
  end

  private def count_segment!(segment : String)
    if counted_segment?(segment)
      let word = segment.normalized_casefold
      @counts[word] = 0 unless @counts.has?(word)
      @counts[word] += 1
    end
  end
end

def sorted_counts(
  counts : const Map[String, Int]
)
  let rows = counts.entries

  rows.sort! do |left, right|
    if left.value > right.value
      -1
    elsif left.value < right.value
      1
    else
      left.key.compare_unicode_scalars(right.key)
    end
  end

  rows
end

def write_results!(
  counts : const Map[String, Int],
  limit : Int,
  output : OutputStream
)
  return if limit == 0

  let rows = sorted_counts(counts)
  var emitted = 0

  for row in rows
    break if emitted >= limit
    output.write("#{row.value}\t#{row.key}\n")
    emitted += 1
  end
end

def write_help!(output : OutputStream)
  output.write(<<~HELP)
    Usage: wordfreq [options] [file...]

    Count case-insensitive word segments using Unicode default boundaries.

    Options:
      -n N, --top N, --top=N  output at most N words (default: 20)
      -h, --help              show this help and exit

    Before '--', an argument named '-' reads standard input.
    After '--', every argument is a literal filename, including '-'.
    With no file arguments, standard input is read.
    Standard input is processed before named files.
    Named files may be processed in any order.
    Repeated identical filename arguments are processed once.
    Repeated '-' arguments before '--' select standard input once.
    Input must be valid UTF-8.
    Tied counts are ordered by normalized Unicode scalar sequence.
  HELP
end

def process_standard_input!(
  counter : Counter,
  input : InputStream
)
  begin
    counter.process!(input)
  rescue IOError | UnicodeError
    raise InputError.new("cannot process standard input: #{error.message}")
  end
end

def process_file!(
  counter : Counter,
  filename : String
)
  begin
    File.open(Path.new(filename)) do |file|
      counter.process!(file)
    end
  rescue PathError | IOError | UnicodeError
    raise InputError.new("cannot process '#{filename}': #{error.message}")
  end
end

def write_usage_error!(
  name : String,
  usage_error : UsageError,
  output : OutputStream
)
  output.puts("#{name}: #{usage_error.message}")
  output.puts("Try '#{name} --help' for more information.")
end

def write_processing_error!(
  name : String,
  processing_error : InputError | IOError,
  output : OutputStream
)
  output.puts("#{name}: #{processing_error.message}")
end

begin
  let command_line = CommandLineParser.new(arguments).parse_arguments

  if command_line.help?
    write_help!(stdout)
    return 0
  end

  let counter = Counter.new

  if command_line.stdin?
    process_standard_input!(
      counter: counter,
      input: stdin
    )
  end

  for filename in command_line.files
    process_file!(
      counter: counter,
      filename: filename
    )
  end

  write_results!(
    counts: counter.counts,
    limit: command_line.top,
    output: stdout
  )
  return 0
rescue usage_error : UsageError
  write_usage_error!(program_name, usage_error, stderr)
  return 2
rescue BrokenPipeError
  raise
rescue processing_error : InputError | IOError
  write_processing_error!(program_name, processing_error, stderr)
  return 1
end
```

## Behavior represented by the source

- Before `--`, one or more explicit `-` arguments select the same borrowed
  `stdin` once and are not retained in `CommandLine.files`. If the resulting
  file Set is empty, stdin is also selected by default.
- After `--`, every token is a literal filename, including `-`; a literal `-`
  is retained in `CommandLine.files`.
- Repeated identical filename argument Strings collapse to one Set member;
  lexical alternatives and aliases to the same filesystem object do not.
  Repeated pre-terminator `-` arguments collapse to one stdin selection.
- Stdin is processed before every named file. Named files may be processed in
  any order, so the first reported failure among several bad named files is
  unspecified.
- Named files are opened and closed by the orchestration layer's scoped
  `File.open` block.
- One `Counter` owns the aggregate map; each `process!(input)` call consumes one
  `InputStream`, whether stdin or an opened file, and adds its words to that
  shared result.
- Options are recognized anywhere before `--`.
- `--top`, `--top=`, and `-n` share one non-negative integer limit and reject
  duplicates.
- The nullable parsed limit is forwarded through the confirmed `top?: top`
  conditional-keyword syntax, so `nil` selects the initializer's declared
  default while `0` remains an explicitly supplied limit.
- `--help` and `-h` return immediately without opening input or constructing
  the Unicode decoder and segmenter.
- All files contribute to one `Map[String, Int]`.
- Input is decoded and segmented incrementally, including across stream chunk
  boundaries.
- Expected path, I/O, and Unicode input failures are reported with either the
  filename or `standard input` as context. Unexpected `Error` subclasses are
  not converted into ordinary processing failures.
- A broken output pipe is rethrown to the CLI boundary, which terminates
  silently with native `SIGPIPE` behavior on POSIX.
- No output rows are written until every input has been consumed successfully.
- Rows use descending count and ascending Unicode-scalar key order.
- A zero output limit returns before materializing or sorting count entries.
- Usage failures return `2`; input and processing failures return `1`; success
  returns `0`.

These behaviors are the accepted target for this specimen, not a statement
that the source, APIs, or error wording are already implemented.

## Provisional APIs exposed by the program

The program makes the following design proposals visible:

| Surface | Provisional contract used here |
| --- | --- |
| Integer parsing | `Int.parse(text, base: 10) : Int?` and strict `Int.parse!(text, base: 10) : Int`; omitting `base` selects decimal |
| String prefixes | `start_with?` and immutable `delete_prefix` |
| String Unicode | default Character iteration, canonical `normalized_casefold`, explicit low-level `unicode_scalars`, and `compare_unicode_scalars` |
| Character | one extended grapheme cluster; `letter?` and `number?` inspect its constituent Unicode properties |
| Map | `has?`, indexed `map[key]` access and assignment, compound indexed assignment, and `entries` returning a fresh mutable snapshot Array whose immutable elements expose `key` and `value` |
| Array | `shallow_copy`, `shift!`, `empty?`, `any?`, and comparator-based `sort!` |
| Set | the empty literal `{,}`, `add!`, `empty?`, and iteration over unique values |
| Input stream | `each_chunk`, yielding byte buffers in source order |
| UTF-8 decoder | `UTF8.strict_decoder` returns a stateful decoder; `on_decode` receives decoded String chunks, `push!` accepts bytes, and `process do ... end` validates and flushes the final chunk |
| Word segmentation | `Unicode.default_word_segmenter`; `on_segment` receives complete segments, `push!` accepts decoded text, and `process do ... end` flushes the final segment |
| Errors | `PathError`, `IOError`, `BrokenPipeError < IOError`, and `UnicodeError`; `InputError` adds source context while preserving the original error as its automatic cause, while a broken output pipe escapes silently to the CLI boundary |
| Files | scoped, read-only `File.open(Path) do ... end` |
| Output stream | `write` and `puts`, both raising on output failure |

The comparator passed to `sort!` follows the familiar negative/zero/positive
contract. `compare_unicode_scalars` is locale-independent and compares the NFC
keys by Unicode scalar value.

`shallow_copy` creates a new mutable Array while preserving references to the
same elements. That is sufficient here because String is immutable and the
parser mutates only the outer Array. Dab does not provide an ambiguous bare
`copy` alias. `deep_copy` is a distinct future graph-copy contract rather than
an alternate interpretation selected by context.

`UTF8.strict_decoder` returns the incremental decoder object itself. It does
not return or yield one Unicode code point at a time. Its registered `on_decode`
block receives decoded String chunks. Ordinary text iteration begins later
through the String itself; `string.unicode_scalars` is an explicit lower-level
view.

Both pipeline stages use `process do ... end` as a lifecycle boundary. Each
stage accepts pushes while its block runs, then validates and flushes exactly
once before returning. The downstream segmenter must therefore wrap the
upstream decoder: the decoder flushes its final text into a still-active
segmenter, and only then may the segmenter flush its final segment.

If a `process` body raises, the stage discards its unfinished state and
propagates that original error without attempting a normal final flush.
Cleanup must not replace the primary failure with a secondary decoder or
segmenter error.

`for value in collection` and `collection.each do |value|` consume the same
iteration protocol, but they are not syntactic synonyms. A `for` body is a
lexical loop body, so its `break` and `next` target that loop and `return`
returns from the enclosing callable. An `each` body is a closure under Dab's
confirmed closure rules; its `return` returns only from that closure, and it
cannot use `break` or `next` to control the iterator. The Character predicate
uses `any?` because that directly expresses the required Boolean reduction.

## Deliberately provisional choices

This specimen makes several concrete choices solely so it can be complete:

- encountering `--help` returns immediately and ignores every later argument;
- an attached short form such as `-n10` is rejected as an unknown option;
- before `--`, one or more `-` arguments select a single stdin pass before the
  named files; after `--`, `-` is a literal filename;
- `File.open(Path)` means read-only binary input and its block argument
  conforms to `InputStream`;
- exact diagnostic text is shown but is not yet a confirmed stable interface;
- decimal is the default for `Int.parse` and `Int.parse!`; whether they accept
  leading `+`, non-ASCII digits, or surrounding whitespace still needs a
  decision;
- the decoder and segmenter callback-registration APIs are proposals,
  including callback replacement rules; and
- `File.open` still exposes the known no-overloading question between scoped
  and escaping resource forms.

These are now reviewable lines of code rather than abstract questions. The
[planned Dab 0.1 acceptance contract](/dab-0.1.html) gives the governing public
design context.
