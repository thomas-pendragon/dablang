workspace "Dab"
  location "build"
  configurations { "Debug", "Release" }

function dab_common_setup(name)
  project(name)
    kind "ConsoleApp"
    language "C++"
    targetdir "bin/"
    buildoptions "-std=c++11"

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
end

dab_common_setup("cvm")
dab_common_setup("cdisasm")
