newoption {
  trigger = "address-sanitizer",
  description = "Generate the dedicated Linux x86_64 AddressSanitizer build",
}

newoption {
  trigger = "undefined-behavior-sanitizer",
  description = "Generate the dedicated Linux x86_64 UndefinedBehaviorSanitizer build",
}

local address_sanitizer = _OPTIONS["address-sanitizer"] ~= nil
local undefined_behavior_sanitizer = _OPTIONS["undefined-behavior-sanitizer"] ~= nil

if address_sanitizer and undefined_behavior_sanitizer then
  error("AddressSanitizer and UndefinedBehaviorSanitizer builds must be generated separately")
end

if address_sanitizer and os.target() ~= "linux" then
  error("the AddressSanitizer Premake configuration supports Linux only; the validation gate requires x86_64")
end

if undefined_behavior_sanitizer and os.target() ~= "linux" then
  error("the UndefinedBehaviorSanitizer Premake configuration supports Linux only; the validation gate checks x86_64 separately")
end

workspace "Dab"
  location(address_sanitizer and "build/address-sanitizer" or
           undefined_behavior_sanitizer and "build/undefined-behavior-sanitizer" or "build")
  configurations(address_sanitizer and { "ASan" } or
                 undefined_behavior_sanitizer and { "UBSan" } or { "Debug", "Release" })

local version_file = assert(io.open("VERSION", "r"))
local dab_version = assert(version_file:read("*l"))
version_file:close()
dab_version = dab_version:match("^%s*(.-)%s*$")

function dab_common_setup(name, kindt, skip_shared)
  kindt = kindt or "ConsoleApp"

  project(name)
    kind(kindt)
    language "C++"
    targetdir(address_sanitizer and "bin/address-sanitizer/" or
              undefined_behavior_sanitizer and "bin/undefined-behavior-sanitizer/" or "bin/")
    cppdialect "C++11"    

    warnings "Extra"
    fatalwarnings "All"
    defines { 'DAB_VERSION="'..dab_version..'"' }

    if not skip_shared then
      files { "src/cshared/**.h", "src/cshared/**.cpp" }
    end
    files { "src/"..name.."/**.h", "src/"..name.."/**.cpp" }

    filter "configurations:Debug"
      defines { "DEBUG" } 
      symbols "On"

    filter "configurations:Release"
      optimize "On"

    filter "configurations:ASan"
      symbols "On"
      optimize "Debug"
      objdir "build/address-sanitizer/obj/%{cfg.buildcfg}/%{prj.name}"
      buildoptions {
        "-fsanitize=address",
        "-fsanitize-address-use-after-scope",
        "-fno-omit-frame-pointer",
        "-fno-optimize-sibling-calls",
      }
      linkoptions { "-fsanitize=address" }

    filter "configurations:UBSan"
      symbols "On"
      optimize "Debug"
      objdir "build/undefined-behavior-sanitizer/obj/%{cfg.buildcfg}/%{prj.name}"
      buildoptions {
        "-fsanitize=undefined",
        "-fno-sanitize-recover=all",
        "-fno-omit-frame-pointer",
        "-fno-optimize-sibling-calls",
      }
      linkoptions { "-fsanitize=undefined" }

    filter "action:xcode4"
      buildoptions "-stdlib=libc++"
      linkoptions "-stdlib=libc++"

    filter "action:xcode4"
      buildoptions "-std=c++11"

    filter "system:macosx"
      buildoptions "-arch x86_64"
      linkoptions "-arch x86_64"

    filter "system:linux"
      links "dl"
      linkoptions "-rdynamic"
end

local pcre2_root = "build/dependencies/pcre2-10.47"
local pcre2_sources = {
  pcre2_root.."/src/pcre2_auto_possess.c",
  pcre2_root.."/src/pcre2_chartables.c",
  pcre2_root.."/src/pcre2_chkdint.c",
  pcre2_root.."/src/pcre2_compile.c",
  pcre2_root.."/src/pcre2_compile_cgroup.c",
  pcre2_root.."/src/pcre2_compile_class.c",
  pcre2_root.."/src/pcre2_config.c",
  pcre2_root.."/src/pcre2_context.c",
  pcre2_root.."/src/pcre2_convert.c",
  pcre2_root.."/src/pcre2_dfa_match.c",
  pcre2_root.."/src/pcre2_error.c",
  pcre2_root.."/src/pcre2_extuni.c",
  pcre2_root.."/src/pcre2_find_bracket.c",
  pcre2_root.."/src/pcre2_jit_compile.c",
  pcre2_root.."/src/pcre2_maketables.c",
  pcre2_root.."/src/pcre2_match.c",
  pcre2_root.."/src/pcre2_match_data.c",
  pcre2_root.."/src/pcre2_match_next.c",
  pcre2_root.."/src/pcre2_newline.c",
  pcre2_root.."/src/pcre2_ord2utf.c",
  pcre2_root.."/src/pcre2_pattern_info.c",
  pcre2_root.."/src/pcre2_script_run.c",
  pcre2_root.."/src/pcre2_serialize.c",
  pcre2_root.."/src/pcre2_string_utils.c",
  pcre2_root.."/src/pcre2_study.c",
  pcre2_root.."/src/pcre2_substitute.c",
  pcre2_root.."/src/pcre2_substring.c",
  pcre2_root.."/src/pcre2_tables.c",
  pcre2_root.."/src/pcre2_ucd.c",
  pcre2_root.."/src/pcre2_valid_utf.c",
  pcre2_root.."/src/pcre2_xclass.c",
}

project "pcre2"
  kind "StaticLib"
  language "C"
  cdialect "C11"
  warnings "Off"
  targetdir(address_sanitizer and "bin/address-sanitizer/" or
            undefined_behavior_sanitizer and "bin/undefined-behavior-sanitizer/" or "bin/")
  objdir(address_sanitizer and "build/address-sanitizer/obj/%{cfg.buildcfg}/%{prj.name}" or
         undefined_behavior_sanitizer and "build/undefined-behavior-sanitizer/obj/%{cfg.buildcfg}/%{prj.name}" or
         "build/obj/%{cfg.buildcfg}/%{prj.name}")
  files(pcre2_sources)
  includedirs { pcre2_root.."/src" }
  defines {
    "PCRE2_CODE_UNIT_WIDTH=8",
    "PCRE2_STATIC",
    "PCRE2_EXPORT=",
    "HAVE_CONFIG_H=1",
    "SUPPORT_PCRE2_8=1",
    "SUPPORT_UNICODE=1",
    "NEVER_BACKSLASH_C=1",
    "LINK_SIZE=2",
    "NEWLINE_DEFAULT=2",
    "PARENS_NEST_LIMIT=250",
    "MAX_VARLOOKBEHIND=255",
  }

  filter "configurations:Release"
    optimize "On"

  filter "configurations:ASan"
    symbols "On"
    optimize "Debug"
    buildoptions {
      "-fsanitize=address",
      "-fsanitize-address-use-after-scope",
      "-fno-omit-frame-pointer",
      "-fno-optimize-sibling-calls",
    }

  filter "configurations:UBSan"
    symbols "On"
    optimize "Debug"
    buildoptions {
      "-fsanitize=undefined",
      "-fno-sanitize-recover=all",
      "-fno-omit-frame-pointer",
      "-fno-optimize-sibling-calls",
    }

dab_common_setup("cvm")
project "cvm"
  includedirs { pcre2_root.."/src" }
  defines { "PCRE2_CODE_UNIT_WIDTH=8", "PCRE2_STATIC" }
  links { "pcre2" }
  dependson { "pcre2" }

dab_common_setup("cdisasm")
dab_common_setup("cdumpcov")
dab_common_setup("cffitest", 'SharedLib', true)
