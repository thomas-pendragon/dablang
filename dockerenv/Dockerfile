# docker build -t dablang/dablangenv:0.8 .
# docker push dablang/dablangenv:0.8

#FROM ubuntu:16.10
FROM ubuntu:16.04
RUN apt-get update 
RUN apt-get install -y wget git ruby2.3 ruby2.3-dev make gcc
RUN echo 'gem: --no-document' >> ~/.gemrc
RUN gem install bundler
RUN cd /usr/bin/ ; wget https://github.com/premake/premake-core/releases/download/v5.0.0-alpha11/premake-5.0.0-alpha11-linux.tar.gz ; tar xf premake-5.0.0-alpha11-linux.tar.gz
RUN apt-get install -y clang-format-4.0

RUN apt-get install -y clang-3.5
#RUN apt-get install -y clang-3.6
#RUN apt-get install -y clang-3.7
#RUN apt-get install -y clang-3.8
#RUN apt-get install -y clang-3.9

#RUN apt-get install -y g++-4.7
RUN apt-get install -y g++-4.8
#RUN apt-get install -y g++-4.9
#RUN apt-get install -y g++-5
#RUN apt-get install -y g++-6
