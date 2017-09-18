---
layout: page
title: Building
---

To build Dab now you need following tools and libraries:

 - Ruby 2.3+
 - bundler Ruby gem (`gem install bundler`)
 - required bundled Ruby libraries (`bundle install`)
 - Premake 5
 - GCC or Clang to compile C++ code
 - optional: SDL2 to build some examples

To build all binaries and run the test suite, simply execute `rake` after installing all dependencies.

Complete install steps for different OSes:

## Mac OS

(TODO: test on a fresh system)

```
/usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
brew install premake --devel
brew install git gcc
git clone https://github.com/thomas-pendragon/dablang
cd dablang
gem install bundler
bundle install
bundle exec rake
```

## GNU/Linux

```
sudo apt-get update
sudo apt-get install -y git ruby2.3 ruby2.3-dev ruby-bundler build-essential gcc wget
git clone https://github.com/thomas-pendragon/dablang
cd dablang
bundle install
wget https://github.com/premake/premake-core/releases/download/v5.0.0-alpha11/premake-5.0.0-alpha11-linux.tar.gz
tar xf premake-5.0.0-alpha11-linux.tar.gz
PREMAKE='./premake5' bundle exec rake
```
