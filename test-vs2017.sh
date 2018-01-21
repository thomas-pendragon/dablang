#!/bin/bash

PATH=$PATH:"/c/Program Files (x86)/Microsoft Visual Studio/2017/Community/MSBuild/15.0/Bin/" TOOLSET=vs2017 PREMAKE=../premake5.exe rake "$@"
