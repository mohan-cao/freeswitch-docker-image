# Build FS dependencies into its own layer
FROM debian:bookworm AS dependency-builder

# Set bash as the default shell
SHELL ["/bin/bash", "-c"]

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV OUTPUT_DIR="/var/local/deb"

# Define build arguments with default
ARG BUILD_NUMBER=42

# Define tag arguments with defaults to HEAD
ARG LIBBROADVOICE_REF=HEAD
ARG LIBILBC_REF=HEAD
ARG LIBSILK_REF=HEAD
ARG SPANDSP_REF=HEAD
ARG SOFIASIP_REF=HEAD
ARG LIBKS_REF=HEAD
ARG SIGNALWIRE_C_REF=HEAD

# Install minimal requirements
RUN apt-get update && apt-get install -y \
    git \
    lsb-release

# Configure git to trust all directories
RUN git config --global --add safe.directory '*'

# Set base dir for cloned repositories
WORKDIR /usr/src

RUN mkdir -p /usr/src/freeswitch \
    && git clone https://github.com/signalwire/freeswitch.git /usr/src/freeswitch

# Create directories
RUN mkdir -p "${OUTPUT_DIR}" /usr/src/freeswitch

# Build the dependency packages
RUN cd /usr/src/freeswitch/scripts/packaging/build/dependencies \
    && ./build-dependencies.sh -b "$BUILD_NUMBER" -o "$OUTPUT_DIR" -p "/usr/src" --setup --repo --clone --git-https \
    libbroadvoice \
    libilbc \
    libsilk \
    spandsp \
    sofia-sip \
    libks \
    signalwire-c

# Stage 2: Install packages layer
FROM debian:bookworm AS installer

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /root

# Copy only the DEB files from builder stage
COPY --from=dependency-builder /var/local/deb/*.deb /tmp/debs/

# Install required tools for setting up local repo
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    apt-utils \
    dpkg-dev \
    gnupg \
    ca-certificates \
    lsb-release \
    procps \
    locales

# Create local repository directory
RUN mkdir -p /var/local/repo && \
    cp /tmp/debs/*.deb /var/local/repo/

# Generate package index
RUN cd /var/local/repo && \
    dpkg-scanpackages . > Packages && \
    gzip -9c Packages > Packages.gz

# Configure local repository
RUN echo "deb [trusted=yes] file:/var/local/repo ./" > /etc/apt/sources.list.d/local.list && \
    apt-get update

# Install all available packages from local repo
RUN ls -1 /var/local/repo/*.deb | sed -e 's|.*/||' -e 's|_.*||' | grep -Pv "\-dbgsym$" | xargs apt-get install -y --allow-downgrades -f

# Clean up
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/debs && \
    rm -rf /var/local/repo && \
    rm -f /etc/apt/sources.list.d/local.list

# Set locale
RUN sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

FROM debian:bookworm AS final-image
COPY --from=installer / /

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -yq install git \
# build
    build-essential cmake automake make autoconf pkg-config 'libtool-bin|libtool' gdb gcc g++ \
# general
    libssl-dev zlib1g-dev libdb-dev unixodbc-dev libncurses5-dev libexpat1-dev libgdbm-dev bison erlang-dev libtpl-dev libtiff5-dev uuid-dev libjpeg-dev screen \
# core
    libpcre3-dev libedit-dev libsqlite3-dev libcurl4-openssl-dev nasm \
# core codecs
    libogg-dev libspeex-dev libspeexdsp-dev \
# mod_enum
    libldns-dev \
# mod_av
    libavformat-dev libswscale-dev libswresample-dev \
# mod_lua
    liblua5.2-dev \
# mod_python3 (have to have it for debian default build)
    python3-dev python3-setuptools \
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
# ca-certs (for runtime)
    ca-certificates

RUN mkdir -p /usr/src/freeswitch \
    && git clone https://github.com/signalwire/freeswitch.git /usr/src/freeswitch

RUN git clone https://github.com/xadhoom/mod_bcg729 /usr/src/libs/mod_bcg729 \
    && echo "codecs/mod_bcg729" >> /usr/src/freeswitch/build/modules.conf.in

# Disable logfile since docker should have its own logdriver based on console output
RUN sed -i 's|loggers/mod_logfile|#loggers/mod_logfile|' /usr/src/freeswitch/build/modules.conf.in

# Copy the modules configuration file to modules.conf
RUN cp /usr/src/freeswitch/build/modules.conf.in /usr/src/freeswitch/modules.conf

RUN cd /usr/src/freeswitch && ./bootstrap.sh -j
RUN cd /usr/src/freeswitch && ./configure -C --enable-portable-binary --disable-dependency-tracking \
        --prefix=/usr --localstatedir=/var --sysconfdir=/etc \
        --with-gnu-ld --with-erlang --with-openssl \
        --enable-core-odbc-support
RUN cd /usr/src/freeswitch && make -j`nproc` && make install

RUN cd /usr/src/libs/mod_bcg729 \
    && make && make install

# make the "en_US.UTF-8" locale so freeswitch will be utf-8 enabled by default
RUN apt-get update && apt-get install -y locales && rm -rf /var/lib/apt/lists/* \
&& localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG en_US.utf

# Cleanup the image
RUN apt-get purge -y --auto-remove git
RUN apt-get --purge autoremove
RUN rm -rf /usr/src/*
RUN rm -rf /usr/share/doc/*

# Create PID folder
RUN mkdir -p /var/run/freeswitch

# Copy entrypoint into image
COPY docker-entrypoint.sh /
RUN chmod +x docker-entrypoint.sh

# Limits Configuration
COPY freeswitch.limits.conf /etc/security/limits.d/

FROM scratch
MAINTAINER Mohan Cao <mohancao@yahoo.com.au>
COPY --from=final-image / /

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

SHELL ["/bin/bash"]

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["freeswitch"]
