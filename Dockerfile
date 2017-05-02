FROM ubuntu:16.04

ARG binary
ENV entrypoint $binary

ARG version
ARG sha256
ARG buildhost
ARG arch
ARG os

MAINTAINER Infoblox <saasdev@infoblox.com>

LABEL com.infoblox.app.binary=${binary}
LABEL com.infoblox.app.version=${version}
LABEL com.infoblox.app.sha256=${sha256}
LABEL com.infoblox.app.buildhost=${buildhost}
LABEL com.infoblox.app.os=${os}
LABEL com.infoblox.app.arch=${arch}


COPY bin/${binary} /usr/local/bin

ENTRYPOINT /usr/local/bin/$entrypoint version
