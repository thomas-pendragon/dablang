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
  error("the UndefinedBehaviorSanitizer Premake configuration supports Linux only; the validation gate requires x86_64")
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

dab_common_setup("cvm")
dab_common_setup("cdisasm")
dab_common_setup("cdumpcov")
dab_common_setup("cffitest", 'SharedLib', true)
