workspace "Dab"
  location "build"
  configurations { "Debug", "Release" }

function dab_common_setup(name, kindt, skip_shared)
  kindt = kindt or "ConsoleApp"

  project(name)
    kind(kindt)
    language "C++"
    targetdir "bin/"
    cppdialect "C++11"

    warnings "Extra"
    flags "FatalCompileWarnings"

    if not skip_shared then
      files { "src/cshared/**.h", "src/cshared/**.cpp" }
    end
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
dab_common_setup("cffitest", 'SharedLib', true)
