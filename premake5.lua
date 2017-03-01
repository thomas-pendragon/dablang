workspace "Dab"
  location "build"
  configurations { "Debug", "Release" }

project "cvm"
  kind "ConsoleApp"
  language "C++"
  targetdir "bin/"
  buildoptions "-std=c++11 -stdlib=libc++"
  linkoptions "-stdlib=libc++"

  files { "src/cvm/**.h", "src/cvm/**.cpp" }

  filter "configurations:Debug"
    defines { "DEBUG" } 
    symbols "On"

  filter "configurations:Release"
    optimize "On"
