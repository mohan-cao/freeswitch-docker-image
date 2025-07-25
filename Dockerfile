FROM debian:bookworm
MAINTAINER Mohan Cao <mohancao@yahoo.com.au>

# Heavily adapted from https://articles.surfin.sg/2024/05/17/20240517/

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -yq install git
RUN cd /usr/src/ \
    && git clone https://github.com/signalwire/freeswitch.git -bv1.10 freeswitch \
    && cd freeswitch \
    && git config pull.rebase true

RUN cd /usr/src/
RUN git clone https://github.com/signalwire/libks /usr/src/libs/libks
RUN git clone https://github.com/freeswitch/sofia-sip /usr/src/libs/sofia-sip
RUN git clone https://github.com/freeswitch/spandsp /usr/src/libs/spandsp
RUN git clone https://github.com/signalwire/signalwire-c /usr/src/libs/signalwire-c
RUN git clone https://github.com/xadhoom/mod_bcg729 /usr/src/libs/mod_bcg729
RUN DEBIAN_FRONTEND=noninteractive apt-get -yq install \
# build
    build-essential cmake automake autoconf 'libtool-bin|libtool' pkg-config \

# general
    libssl-dev zlib1g-dev libdb-dev unixodbc-dev libncurses5-dev libexpat1-dev libgdbm-dev bison erlang-dev libtpl-dev libtiff5-dev uuid-dev \

# core
    libpcre3-dev libedit-dev libsqlite3-dev libcurl4-openssl-dev nasm \

# core codecs
    libogg-dev libspeex-dev libspeexdsp-dev \

# mod_enum
    libldns-dev \

# mod_python3
    python3-dev \

# mod_av
    libavformat-dev libswscale-dev libswresample-dev \

# mod_lua
    liblua5.2-dev \

# mod_opus
    libopus-dev \

# mod_pgsql
    libpq-dev \

# mod_sndfile
    libsndfile1-dev libflac-dev libogg-dev libvorbis-dev \

# mod_shout
    libshout3-dev libmpg123-dev libmp3lame-dev \

# Other software
    vim sngrep htop \

# TLS/SSL
    libssl-dev

RUN cd /usr/src/libs/libks && cmake . -DCMAKE_INSTALL_PREFIX=/usr -DWITH_LIBBACKTRACE=1 && make install
RUN cd /usr/src/libs/sofia-sip && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --with-glib=no --without-doxygen --disable-stun --prefix=/usr && make -j`nproc --all` && make install
RUN cd /usr/src/libs/spandsp  && git checkout 0d2e6ac  && ./bootstrap.sh && ./configure CFLAGS="-g -ggdb" --with-pic --prefix=/usr && make -j`nproc --all` && make install
RUN cd /usr/src/libs/signalwire-c && PKG_CONFIG_PATH=/usr/lib/pkgconfig cmake . -DCMAKE_INSTALL_PREFIX=/usr && make install

# Enable modules

RUN sed -i 's|#formats/mod_shout|formats/mod_shout|' /usr/src/freeswitch/build/modules.conf.in
RUN echo "codecs/mod_bcg729" >> /usr/src/freeswitch/build/modules.conf.in

RUN cd /usr/src/freeswitch && ./bootstrap.sh -j
RUN cd /usr/src/freeswitch && ./configure
RUN cd /usr/src/freeswitch && make -j`nproc` && make install

RUN cd /usr/src/libs/mod_bcg729 && sed 's\^FS_INCLUDES.*\FS_INCLUDES=/usr/local/freeswitch/include/freeswitch\' Makefile -i && sed 's\^FS_MODULES.*\FS_MODULES=/usr/local/freeswitch/mod\' Makefile -i && make && make install

RUN ln -sf /usr/local/freeswitch/bin/freeswitch /usr/bin/
RUN ln -sf /usr/local/freeswitch/bin/fs_cli /usr/bin/

# make the "en_US.UTF-8" locale so freeswitch will be utf-8 enabled by default
RUN apt-get update && apt-get install -y locales && rm -rf /var/lib/apt/lists/* \
&& localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.utf

# grab gosu for easy step-down from root8
RUN gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates wget && rm -rf /var/lib/apt/lists/* \
    && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/1.2/gosu-$(dpkg --print-architecture)" \
    && wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/1.2/gosu-$(dpkg --print-architecture).asc" \
    && gpg --verify /usr/local/bin/gosu.asc \
    && rm /usr/local/bin/gosu.asc \
    && chmod +x /usr/local/bin/gosu \
    && apt-get purge -y --auto-remove ca-certificates wget

# Set up permissions
RUN groupadd -r freeswitch --gid=999 && useradd -r -g freeswitch --uid=999 freeswitch

# Create PID folder
RUN mkdir -p /var/run/freeswitch

# Copy entrypoint into image
COPY docker-entrypoint.sh /
RUN chmod +x docker-entrypoint.sh

# Limits Configuration
COPY freeswitch.limits.conf /etc/security/limits.d/

# Cleanup the image
RUN apt-get autoremove
RUN rm -rf /usr/src/*

FROM scratch
COPY --from=0 / /

EXPOSE 8021/tcp
EXPOSE 5060/tcp 5060/udp 5080/tcp 5080/udp
EXPOSE 5061/tcp 5061/udp 5081/tcp 5081/udp
EXPOSE 7443/tcp
EXPOSE 5070/udp 5070/tcp
EXPOSE 64535-65535/udp
EXPOSE 16384-32768/udp

SHELL ["/bin/bash"]
HEALTHCHECK --interval=15s --timeout=5s \
    CMD fs_cli -x status | grep -q ^UP

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["freeswitch"]
