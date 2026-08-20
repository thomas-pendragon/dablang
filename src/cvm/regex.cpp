#include "regex.h"

#include <pcre2.h>

#include <cstdlib>
#include <cstring>
#include <memory>
#include <new>
#include <sstream>
#include <utility>

namespace
{
const size_t MAX_REGEX_PATTERN_BYTES = 65535;

bool test_mode(const char *name);

struct Pcre2CodeDeleter
{
    void operator()(pcre2_code *code) const
    {
        pcre2_code_free(code);
        if (code && test_mode("DAB_REGEX_TEST_TRACE_LIFETIME"))
        {
            fprintf(stderr, "regex-test: compiled handle freed\n");
        }
    }
};

struct Pcre2CompileContextDeleter
{
    void operator()(pcre2_compile_context *context) const
    {
        pcre2_compile_context_free(context);
    }
};

struct Pcre2MatchContextDeleter
{
    void operator()(pcre2_match_context *context) const
    {
        pcre2_match_context_free(context);
    }
};

struct Pcre2MatchDataDeleter
{
    void operator()(pcre2_match_data *data) const
    {
        pcre2_match_data_free(data);
    }
};

typedef std::unique_ptr<pcre2_code, Pcre2CodeDeleter>                      Pcre2Code;
typedef std::unique_ptr<pcre2_compile_context, Pcre2CompileContextDeleter> Pcre2CompileContext;
typedef std::unique_ptr<pcre2_match_context, Pcre2MatchContextDeleter>     Pcre2MatchContext;
typedef std::unique_ptr<pcre2_match_data, Pcre2MatchDataDeleter>           Pcre2MatchData;

bool test_mode(const char *name)
{
    const char *value = std::getenv(name);
    return value && std::strcmp(value, "1") == 0;
}

bool allocation_failure(const char *stage)
{
    const char *value = std::getenv("DAB_REGEX_TEST_FAIL_ALLOCATION");
    return value && std::strcmp(value, stage) == 0;
}

const char *test_value(const char *name)
{
    return std::getenv(name);
}

[[noreturn]] void throw_out_of_memory()
{
    throw DabRuntimeError("Regex construction failed: out of memory");
}

template <typename T>
bool read_configuration(uint32_t selector, T *value)
{
    return pcre2_config(selector, value) >= 0;
}

std::string error_message(int error_code)
{
    PCRE2_UCHAR buffer[256] = {};
    int         length      = pcre2_get_error_message(error_code, buffer, sizeof(buffer));
    if (length < 0)
    {
        return "unknown PCRE2 error";
    }
    return std::string(reinterpret_cast<const char *>(buffer), static_cast<size_t>(length));
}

void throw_compile_error(int error_code, PCRE2_SIZE error_offset)
{
    if (error_code == PCRE2_ERROR_HEAP_FAILED)
    {
        throw_out_of_memory();
    }

    std::ostringstream message;
    if (error_code <= PCRE2_ERROR_UTF8_ERR1 && error_code >= PCRE2_ERROR_UTF8_ERR21)
    {
        message << "invalid UTF-8 Regex pattern at byte ";
    }
    else
    {
        message << "invalid Regex pattern at byte ";
    }
    message << static_cast<size_t>(error_offset) << " (PCRE2 error " << error_code
            << "): " << error_message(error_code);
    throw DabRuntimeError(message.str());
}

bool utf8_error(int error_code)
{
    return error_code <= PCRE2_ERROR_UTF8_ERR1 && error_code >= PCRE2_ERROR_UTF8_ERR21;
}

int injected_match_error(int result)
{
    const char *value = test_value("DAB_REGEX_TEST_MATCH_ERROR");
    if (!value)
    {
        return result;
    }
    if (std::strcmp(value, "match_limit") == 0)
    {
        return PCRE2_ERROR_MATCHLIMIT;
    }
    if (std::strcmp(value, "depth_limit") == 0)
    {
        return PCRE2_ERROR_DEPTHLIMIT;
    }
    if (std::strcmp(value, "heap_limit") == 0)
    {
        return PCRE2_ERROR_HEAPLIMIT;
    }
    if (std::strcmp(value, "out_of_memory") == 0)
    {
        return PCRE2_ERROR_NOMEMORY;
    }
    return result;
}

[[noreturn]] void throw_match_error(int error_code, pcre2_match_data *match_data)
{
    if (error_code == PCRE2_ERROR_MATCHLIMIT)
    {
        throw DabRuntimeError("Regex match limit exceeded");
    }
    if (error_code == PCRE2_ERROR_DEPTHLIMIT)
    {
        throw DabRuntimeError("Regex match depth limit exceeded");
    }
    if (error_code == PCRE2_ERROR_HEAPLIMIT)
    {
        throw DabRuntimeError("Regex match heap limit exceeded");
    }
    if (error_code == PCRE2_ERROR_NOMEMORY)
    {
        throw DabRuntimeError("Regex match failed: out of memory");
    }

    std::ostringstream message;
    if (utf8_error(error_code))
    {
        message << "invalid UTF-8 Regex match subject at byte "
                << static_cast<size_t>(pcre2_get_startchar(match_data));
    }
    else
    {
        message << "Regex match failed";
    }
    message << " (PCRE2 error " << error_code << "): " << error_message(error_code);
    throw DabRuntimeError(message.str());
}

bool default_max_varlookbehind_is_255()
{
    static const char accepted[] = "(?<=a{1,255})b";
    static const char rejected[] = "(?<=a{1,256})b";
    int               error_code;
    PCRE2_SIZE        error_offset;

    pcre2_code *code = pcre2_compile(reinterpret_cast<PCRE2_SPTR>(accepted), sizeof(accepted) - 1,
                                     PCRE2_UTF | PCRE2_UCP | PCRE2_NEVER_BACKSLASH_C, &error_code,
                                     &error_offset, nullptr);
    if (!code)
    {
        return false;
    }
    pcre2_code_free(code);

    code = pcre2_compile(reinterpret_cast<PCRE2_SPTR>(rejected), sizeof(rejected) - 1,
                         PCRE2_UTF | PCRE2_UCP | PCRE2_NEVER_BACKSLASH_C, &error_code,
                         &error_offset, nullptr);
    if (code)
    {
        pcre2_code_free(code);
        return false;
    }
    return error_code == PCRE2_ERROR_MAX_VAR_LOOKBEHIND_EXCEEDED;
}
} // namespace

DabRegex::DabRegex()
{
}

DabRegex::DabRegex(std::string source, void *compiled)
    : source(std::move(source)), compiled(compiled)
{
}

DabRegex::~DabRegex()
{
    if (compiled)
    {
        pcre2_code_free(static_cast<pcre2_code *>(compiled));
        compiled = nullptr;
        if (test_mode("DAB_REGEX_TEST_TRACE_LIFETIME"))
        {
            fprintf(stderr, "regex-test: compiled handle freed\n");
        }
    }
}

void dab_regex_verify_engine()
{
    char     version[64]         = {};
    char     unicode_version[64] = {};
    uint32_t unicode             = 0;
    uint32_t jit                 = 0;
    uint32_t widths              = 0;
    uint32_t link_size           = 0;
    uint32_t effective_link_size = 0;
    uint32_t newline             = 0;
    uint32_t bsr                 = 0;
    uint32_t parens_limit        = 0;
    uint32_t never_backslash_c   = 0;
    uint32_t tables_length       = 0;

    bool valid = read_configuration(PCRE2_CONFIG_VERSION, version) &&
                 read_configuration(PCRE2_CONFIG_UNICODE_VERSION, unicode_version) &&
                 read_configuration(PCRE2_CONFIG_UNICODE, &unicode) &&
                 read_configuration(PCRE2_CONFIG_JIT, &jit) &&
                 read_configuration(PCRE2_CONFIG_COMPILED_WIDTHS, &widths) &&
                 read_configuration(PCRE2_CONFIG_LINKSIZE, &link_size) &&
                 read_configuration(PCRE2_CONFIG_EFFECTIVE_LINKSIZE, &effective_link_size) &&
                 read_configuration(PCRE2_CONFIG_NEWLINE, &newline) &&
                 read_configuration(PCRE2_CONFIG_BSR, &bsr) &&
                 read_configuration(PCRE2_CONFIG_PARENSLIMIT, &parens_limit) &&
                 read_configuration(PCRE2_CONFIG_NEVER_BACKSLASH_C, &never_backslash_c) &&
                 read_configuration(PCRE2_CONFIG_TABLES_LENGTH, &tables_length);

    valid = valid && std::strcmp(version, "10.47 2025-10-21") == 0 &&
            std::strcmp(unicode_version, "16.0.0") == 0 && unicode == 1 && jit == 0 &&
            widths == 0x1 && link_size == 2 && effective_link_size == 2 &&
            newline == PCRE2_NEWLINE_LF && bsr == PCRE2_BSR_UNICODE && parens_limit == 250 &&
            never_backslash_c == 1 && tables_length == 1088 && default_max_varlookbehind_is_255();

    if (test_mode("DAB_REGEX_TEST_ENGINE_MISMATCH"))
    {
        valid = false;
    }
    if (!valid)
    {
        throw DabRuntimeError("incompatible Regex engine configuration: expected PCRE2 10.47 with "
                              "Unicode 16.0.0 strict UTF-8 profile");
    }
}

DabValue dab_regex_create(const std::vector<DabValue> &arguments)
{
    if (arguments.size() != 1)
    {
        throw DabRuntimeError("Regex.new expects exactly one argument");
    }
    if (arguments[0].data.type != TYPE_LITERALSTRING &&
        arguments[0].data.type != TYPE_DYNAMICSTRING)
    {
        throw DabRuntimeError("Regex.new expects a String pattern");
    }

    const char *pattern_data;
    size_t      pattern_size;
    if (arguments[0].data.type == TYPE_LITERALSTRING)
    {
        auto *pattern = (DabLiteralString *)arguments[0].data.object->object;
        pattern_data  = pattern->pointer;
        pattern_size  = static_cast<size_t>(pattern->length);
    }
    else
    {
        auto *pattern = (DabDynamicString *)arguments[0].data.object->object;
        pattern_data  = pattern->value.data();
        pattern_size  = pattern->value.size();
    }
    if (pattern_size > MAX_REGEX_PATTERN_BYTES)
    {
        throw DabRuntimeError("Regex pattern is too long: maximum is 65535 bytes");
    }

    try
    {
        if (allocation_failure("source"))
        {
            throw std::bad_alloc();
        }
        std::string source;
        if (pattern_size != 0)
        {
            source.assign(pattern_data, pattern_size);
        }

        Pcre2CompileContext context(pcre2_compile_context_create(nullptr));
        if (!context)
        {
            throw_out_of_memory();
        }
        if (pcre2_set_max_pattern_length(context.get(), MAX_REGEX_PATTERN_BYTES) != 0 ||
            pcre2_set_parens_nest_limit(context.get(), 250) != 0 ||
            pcre2_set_max_varlookbehind(context.get(), 255) != 0 ||
            pcre2_set_newline(context.get(), PCRE2_NEWLINE_LF) != 0 ||
            pcre2_set_bsr(context.get(), PCRE2_BSR_UNICODE) != 0)
        {
            throw DabRuntimeError("incompatible Regex engine configuration: expected PCRE2 10.47 "
                                  "with Unicode 16.0.0 strict UTF-8 profile");
        }

        int        error_code   = 0;
        PCRE2_SIZE error_offset = 0;
        Pcre2Code  code(pcre2_compile(reinterpret_cast<PCRE2_SPTR>(source.data()), source.size(),
                                      PCRE2_UTF | PCRE2_UCP | PCRE2_NEVER_BACKSLASH_C, &error_code,
                                      &error_offset, context.get()));
        if (!code)
        {
            throw_compile_error(error_code, error_offset);
        }

        if (allocation_failure("payload"))
        {
            throw std::bad_alloc();
        }
        std::unique_ptr<DabRegex> payload(new DabRegex(std::move(source), code.release()));
        payload->klass = CLASS_REGEX;

        if (allocation_failure("proxy"))
        {
            throw std::bad_alloc();
        }
        std::unique_ptr<DabObjectProxy> proxy(new DabObjectProxy);
        proxy->object       = payload.release();
        proxy->count_strong = 1;

        DabValue result;
        result.data.type   = TYPE_OBJECT;
        result.data.object = proxy.release();
        return result;
    }
    catch (const std::bad_alloc &)
    {
        throw_out_of_memory();
    }
}

DabValue dab_regex_match(DabValue self, const std::vector<DabValue> &arguments)
{
    if (arguments.size() != 1)
    {
        throw DabRuntimeError("internal Regex match expects exactly one argument");
    }
    if (self.data.type != TYPE_OBJECT || !self.data.object || !self.data.object->object)
    {
        throw DabRuntimeError("internal Regex match expects a Regex receiver");
    }

    DabBaseObject *receiver_storage = self.data.object->object;
    if (receiver_storage->klass != CLASS_REGEX)
    {
        throw DabRuntimeError("internal Regex match expects a Regex receiver");
    }
    DabRegex *regex = dynamic_cast<DabRegex *>(receiver_storage);
    if (!regex || !regex->compiled)
    {
        throw DabRuntimeError("internal Regex match received invalid Regex storage");
    }

    const DabValue &subject_value = arguments[0];
    if ((subject_value.data.type != TYPE_LITERALSTRING &&
         subject_value.data.type != TYPE_DYNAMICSTRING) ||
        !subject_value.data.object || !subject_value.data.object->object)
    {
        throw DabRuntimeError("internal Regex match expects a String subject");
    }

    PCRE2_SPTR subject;
    PCRE2_SIZE subject_size;
    if (subject_value.data.type == TYPE_LITERALSTRING)
    {
        DabBaseObject *storage = subject_value.data.object->object;
        if (storage->klass != CLASS_LITERALSTRING)
        {
            throw DabRuntimeError("internal Regex match received invalid String storage");
        }
        DabLiteralString *literal = dynamic_cast<DabLiteralString *>(storage);
        if (!literal || (!literal->pointer && literal->length != 0))
        {
            throw DabRuntimeError("internal Regex match received invalid String storage");
        }
        subject      = reinterpret_cast<PCRE2_SPTR>(literal->pointer ? literal->pointer : "");
        subject_size = static_cast<PCRE2_SIZE>(literal->length);
    }
    else
    {
        DabBaseObject *storage = subject_value.data.object->object;
        if (storage->klass != CLASS_DYNAMICSTRING)
        {
            throw DabRuntimeError("internal Regex match received invalid String storage");
        }
        DabDynamicString *dynamic = dynamic_cast<DabDynamicString *>(storage);
        if (!dynamic)
        {
            throw DabRuntimeError("internal Regex match received invalid String storage");
        }
        subject      = reinterpret_cast<PCRE2_SPTR>(dynamic->value.data());
        subject_size = static_cast<PCRE2_SIZE>(dynamic->value.size());
    }

    Pcre2MatchContext context(pcre2_match_context_create(nullptr));
    Pcre2MatchData    match_data(pcre2_match_data_create(1, nullptr));
    if (!context || !match_data)
    {
        throw DabRuntimeError("Regex match failed: out of memory");
    }
    if (pcre2_set_match_limit(context.get(), 100000) != 0 ||
        pcre2_set_depth_limit(context.get(), 1000) != 0 ||
        pcre2_set_heap_limit(context.get(), 8192) != 0)
    {
        throw DabRuntimeError("Regex match failed: out of memory");
    }

    pcre2_code *code = static_cast<pcre2_code *>(regex->compiled);
    int result = pcre2_match(code, subject, subject_size, 0, 0, match_data.get(), context.get());
    result     = injected_match_error(result);
    if (result >= 0)
    {
        return DabValue(true);
    }
    if (result == PCRE2_ERROR_NOMATCH)
    {
        return DabValue(false);
    }

    throw_match_error(result, match_data.get());
}
