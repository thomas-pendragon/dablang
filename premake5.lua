workspace "Dab"
  location "build"
  configurations { "Debug", "Release" }

function dab_common_setup(name)
  project(name)
    kind "ConsoleApp"
    language "C++"
    targetdir "bin/"
    cppdialect "C++11"

    warnings "Extra"
    flags "FatalCompileWarnings"

    files { "src/cshared/**.h", "src/cshared/**.cpp" }
    files { "src/"..name.."/**.h", "src/"..name.."/**.cpp" }

    filter "configurations:Debug"
      defines { "DEBUG" } 
      symbols "On"

    filter "configurations:Release"
      optimize "On"

    filter "action:xcode4"
      buildoptions "-stdlib=libc++"
      linkoptions "-stdlib=libc++"

    filter "action:xcode4"
      buildoptions "-std=c++11"

    filter "system:not windows"
      links "dl"
      linkoptions "-rdynamic"
end

dab_common_setup("cvm")
dab_common_setup("cdisasm")
dab_common_setup("cdumpcov")
