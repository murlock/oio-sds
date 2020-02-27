FROM ubuntu:18.04

RUN apt update && \
    apt upgrade -y && \
    apt install -y \
        git build-essential cmake \
        libjson-c-dev pkg-config libhiredis-dev apache2-dev \
        libglib2.0-dev libcurl4-gnutls-dev libapr1-dev \
        libsqlite3-dev libzmq3-dev golang-go=2:1.10~4ubuntu1 \
        flex bison libattr1-dev libzookeeper-mt-dev libleveldb-dev \
        asn1c && \
    apt install -y python-pip liberasurecode-dev python-virtualenv && \
    go get gopkg.in/ini.v1 gopkg.in/tylerb/graceful.v1 \
           golang.org/x/sys/unix

RUN mkdir -p /oio/src /oio/build /oio/venv/

COPY ./ /oio/src

# VOLUME /oio/src

# TODO use a multistage docker ?


WORKDIR /oio/build/
RUN cmake /oio/src -DCMAKE_BUILD_TYPE="Debug" -DENABLE_CODECOVERAGE=on && \
    make install

WORKDIR /oio/src/
RUN virtualenv /oio/venv/ && \
    . /oio/venv/bin/activate && \
    pip install -r all-requirements.txt && \
    pip install -r test-requirements.txt && \
    pip install tox && \
    python setup.py develop

# run test

RUN apt install -y rsyslog
RUN export LD_LIBRARY_PATH=/usr/local/lib64  && \
    . /oio/venv/bin/activate && \
    ./tools/oio-test-unit.sh /oio/src/ /oio/build/


# run docker run -it --rm -v $(readlink -e ..):/oio/src/:ro oio-build /bin/bash
# (docker) $ cd /oio/build
# (docker) $ cmake /oio/src -DCMAKE_BUILD_TYPE="Debug" -DENABLE_CODECOVERAGE=on
# (docker) $ make install
# (docker) $ cd /oio/src
# (docker) $ pip install -r all-requirements.txt
# (docker) $ pip install -r test-requirements.txt

# TEST
# (docker) $ ./tools/oio-test-unit.sh  /oio/src/ /oio/build/

####
# => beanstalkd is required for ?
