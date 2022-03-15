FROM ubuntu:rolling AS base

# NOTE: Make sure secret id=xerpi_gist,src=secret/xerpi_gist.txt is defined

ARG MAKE_JOBS=1
ARG INSTALL_DKP_PACKAGES=1

# prepare devkitpro env
ENV DEVKITPRO=/opt/devkitpro
ENV DEVKITARM=/opt/devkitpro/devkitARM
ENV DEVKITPPC=/opt/devkitpro/devkitPPC
ENV PATH=${DEVKITPRO}/tools/bin:${DEVKITARM}/bin:${PATH}

# prepare vitasdk env
ENV VITASDK=/usr/local/vitasdk
ENV PATH=${VITASDK}/bin:${PATH}

ARG DKARM_RULES_VER=1.2.1
ARG DKARM_CRTLS_VER=1.1.1
ARG GCC_VER=11.2.0
ARG BINUTILS_VER=2.37
ARG NEWLIB_VER=4.2.0.20211231

ARG TARGET=arm-none-eabi

ARG DEBIAN_FRONTEND=noninteractive

# get all the required packages
RUN apt update && apt upgrade -y
RUN apt install -y \
    make git-core cmake python3-dev build-essential bison flex \
    libncurses5-dev libreadline-dev texinfo pkg-config \
    libssl-dev gpg wget curl \
    python3-pip python3-setuptools libglib2.0-dev libc6-dbg \
    autotools-dev automake autoconf liblz4-dev libelf-dev \
    python2-dev libtinfo5 \
    libgmp-dev libmpfr-dev libmpc-dev mesa-common-dev libfreeimage-dev \
    zlib1g-dev libusb-dev libudev-dev libexpat1-dev \
    xz-utils bzip2 python \
    meson ninja-build

# install Mako for UAM
RUN python3 -m pip install Mako

# add env vars for all users
RUN echo "export VITASDK=/usr/local/vitasdk" > /etc/profile.d/10-vitasdk-env.sh \
    && echo "export PATH=$VITASDK/bin:$PATH" >> /etc/profile.d/10-vitasdk-env.sh

# add a new user vita2hos
RUN useradd -s /bin/bash -m vita2hos

# install dkp-pacman and some packages (only if building locally since dkp blocks github -.-)
RUN if [ "$INSTALL_DKP_PACKAGES" -eq "1" ]; then \
        wget https://github.com/devkitPro/pacman/releases/latest/download/devkitpro-pacman.amd64.deb \
        && apt install -y ./devkitpro-pacman.amd64.deb \
        && rm ./devkitpro-pacman.amd64.deb \
        && ln -s /proc/self/mounts /etc/mtab \
        && dkp-pacman -Syu --noconfirm \
            general-tools devkitarm-rules \
            switch-dev switch-portlibs \
            3ds-dev 3ds-portlibs ; \
    fi

# create $DEVKITPRO and $DEVKITARM if not building locally
# and add env vars for all users
RUN if [ "$INSTALL_DKP_PACKAGES" -ne "1" ] ; then \
        mkdir -p $DEVKITARM \
        && echo "export DEVKITPRO=${DEVKITPRO}" > /etc/profile.d/devkit-env.sh \
        && echo "export DEVKITARM=${DEVKITPRO}/devkitARM" >> /etc/profile.d/devkit-env.sh \
        && echo "export DEVKITPPC=${DEVKITPRO}/devkitPPC" >> /etc/profile.d/devkit-env.sh \
        && echo "export PATH=${DEVKITPRO}/tools/bin:$PATH" >> /etc/profile.d/devkit-env.sh ; \
    fi

# give vita2hos ownership of $DEVKITPRO
RUN chown vita2hos:vita2hos -R $DEVKITPRO

FROM base AS builder

# Install sudo for vitasdk
RUN apt install -y sudo

# Download public key for github.com
RUN mkdir -p -m 0700 ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts

# add a build structure and fix permissions
RUN mkdir -p /home/vita2hos/tools/vitasdk && mkdir -p /home/vita2hos/tools/toolchain \
    && chown vita2hos:vita2hos -R /home/vita2hos

# install vitasdk package manager
WORKDIR /home/vita2hos/tools/vitasdk
RUN git clone https://github.com/vitasdk/vdpm \
    && cd vdpm && ./bootstrap-vitasdk.sh \
    && ./install-all.sh

# download and build samples from vitasdk
USER vita2hos
WORKDIR /home/vita2hos/tools/vitasdk
RUN git clone https://github.com/vitasdk/samples \
    && cd samples && mkdir build && cd build \
    && cmake .. && make -j $MAKE_JOBS

USER root
WORKDIR /home/vita2hos/tools
RUN --mount=type=secret,id=xerpi_gist git clone $(cat /run/secrets/xerpi_gist) xerpi_gist \
    && chown vita2hos:vita2hos -R xerpi_gist

# prepare binutils, gcc and newlib
USER vita2hos
WORKDIR /home/vita2hos/tools/toolchain
RUN wget https://ftp.gnu.org/gnu/gcc/gcc-$GCC_VER/gcc-$GCC_VER.tar.gz \
    && wget https://ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VER.tar.gz \
    && wget ftp://sourceware.org/pub/newlib/newlib-$NEWLIB_VER.tar.gz \
    && tar -zxvf gcc-$GCC_VER.tar.gz \
    && tar -zxvf binutils-$BINUTILS_VER.tar.gz \
    && tar -zxvf newlib-$NEWLIB_VER.tar.gz

# build and install binutils
RUN mkdir binutils-build && cd binutils-build \
    && ../binutils-$BINUTILS_VER/configure \
        --prefix=$DEVKITARM \
        --target=$TARGET \
        --disable-nls --disable-werror \
        --enable-lto --enable-plugins --enable-poison-system-directories \
    && make -j $MAKE_JOBS all 2>&1 | tee ./binutils-build-logs.log
RUN cd binutils-build && make install

# patch, build and install gcc
USER vita2hos
RUN cd gcc-$GCC_VER \
    && patch -p1 < ../../xerpi_gist/gcc-11.2.0.patch \
    && cd .. && mkdir gcc-build && cd gcc-build \
    && CFLAGS_FOR_TARGET="-O2 -ffunction-sections -fdata-sections -fPIC" \
       CXXFLAGS_FOR_TARGET="-O2 -ffunction-sections -fdata-sections -fPIC" \
       LDFLAGS_FOR_TARGET="" \
       ../gcc-$GCC_VER/configure \
       --target=$TARGET \
       --prefix=$DEVKITARM \
       --enable-languages=c,c++,objc,lto \
       --with-gnu-as --with-gnu-ld --with-gcc \
       --enable-cxx-flags='-ffunction-sections' \
       --disable-libstdcxx-verbose \
       --enable-poison-system-directories \
       --enable-interwork --enable-multilib \
       --enable-threads --disable-win32-registry --disable-nls --disable-debug \
       --disable-libmudflap --disable-libssp --disable-libgomp \
       --disable-libstdcxx-pch \
       --enable-libstdcxx-time=yes \
       --enable-libstdcxx-filesystem-ts \
       --with-newlib \
       --with-headers=../newlib-$NEWLIB_VER/newlib/libc/include \
       --enable-lto \
       --with-system-zlib \
       --disable-tm-clone-registry \
       --disable-__cxa_atexit \
       --with-bugurl="http://wiki.devkitpro.org/index.php/Bug_Reports" --with-pkgversion="devkitARM release 57 (mod for Switch aarch32)" \
    && make -j $MAKE_JOBS all-gcc 2>&1 | tee ./gcc-build-withoutnewlib-logs.log
RUN cd gcc-build && make install-gcc

# patch, build and install newlib
USER vita2hos
RUN cd newlib-$NEWLIB_VER \
    && patch -p1 < ../../xerpi_gist/newlib-4.2.0.20211231.patch \
    && cd .. && mkdir newlib-build && cd newlib-build \
    && CFLAGS_FOR_TARGET="-O2 -ffunction-sections -fdata-sections -fPIC" \
       ../newlib-$NEWLIB_VER/configure \
       --target=$TARGET \
       --prefix=$DEVKITARM \
       --disable-newlib-supplied-syscalls \
       --enable-newlib-mb \
       --disable-newlib-wide-orient \
    && make -j $MAKE_JOBS all 2>&1 | tee ./newlib-build-logs.log
RUN cd newlib-build && make install

# build and install gcc stage 2 (with newlib)
USER vita2hos
RUN cd gcc-build \
    && make -j $MAKE_JOBS all 2>&1 | tee ./gcc-build-withnewlib-logs.log
RUN cd gcc-build && make install

# remove sys-include dir in devkitARM/arm-none-eabi
RUN rm -rf $DEVKITARM/$TARGET/sys-include

# build and install dkp general-tools if not building locally
RUN if [ "$INSTALL_DKP_PACKAGES" -ne "1" ] ; then \
        git clone https://github.com/devkitPro/general-tools \
        && cd general-tools && ./autogen.sh \
        && ./configure --prefix=${DEVKITPRO}/tools && make -j $MAKE_JOBS \
        && make install ; \
    fi

# install devkitARM rules and crt0 files if not building locally
RUN if [ "$INSTALL_DKP_PACKAGES" -ne "1" ] ; then \
        wget https://github.com/devkitPro/devkitarm-rules/archive/refs/tags/v${DKARM_RULES_VER}.tar.gz -O devkitarm-rules-${DKARM_RULES_VER}.tar.gz \
        && wget https://github.com/devkitPro/devkitarm-crtls/archive/refs/tags/v${DKARM_CRTLS_VER}.tar.gz -O devkitarm-crtls-${DKARM_CRTLS_VER}.tar.gz \
        && tar -xvf ./devkitarm-rules-${DKARM_RULES_VER}.tar.gz \
        && cd devkitarm-rules-${DKARM_RULES_VER} && make install && cd .. \
        && tar -xvf ./devkitarm-crtls-${DKARM_CRTLS_VER}.tar.gz \
        && cd devkitarm-crtls-${DKARM_CRTLS_VER} && make install ; \
    fi

# Clone and install devkitARM gdb with python3 support
RUN git clone https://github.com/devkitPro/binutils-gdb -b devkitARM-gdb \
    && cd binutils-gdb \
    && ./configure --with-python=/usr/bin/python3 --prefix=/opt/devkitpro/devkitARM --target=arm-none-eabi \
    && make && make install

# Clone private libnx fork and install it
USER root
WORKDIR /home/vita2hos/tools
RUN --mount=type=ssh git clone git@github.com:xerpi/libnx && chown vita2hos:vita2hos -R libnx
USER vita2hos
RUN cd libnx && make -j $MAKE_JOBS -C nx/ -f Makefile.32
RUN cd libnx && make -C nx/ -f Makefile.32 install

# Clone switch-tools fork and install it
USER root
RUN --mount=type=ssh git clone git@github.com:xerpi/switch-tools --branch arm-32-bit-support && chown vita2hos:vita2hos -R switch-tools
USER vita2hos
RUN cd switch-tools && ./autogen.sh \
    && ./configure --prefix=${DEVKITPRO}/tools/ \
    && make -j $MAKE_JOBS
RUN cd switch-tools && make install

# Clone and install dekotools
USER vita2hos
RUN git clone https://github.com/fincs/dekotools
RUN cd dekotools \
    && meson build
USER root
RUN cd dekotools/build && ninja install -j $MAKE_JOBS

# Clone private deko3d fork and install it
USER root
RUN --mount=type=ssh git clone git@github.com:xerpi/deko3d && chown vita2hos:vita2hos -R deko3d
USER vita2hos
RUN cd deko3d && make -f Makefile.32 -j $MAKE_JOBS
RUN cd deko3d && make -f Makefile.32 install

# prepare portlibs
USER vita2hos
WORKDIR /home/vita2hos/tools/portlibs
RUN git clone https://github.com/KhronosGroup/SPIRV-Cross \
    && git clone https://github.com/fmtlib/fmt \
    && git clone https://github.com/KhronosGroup/glslang \
    && git clone https://github.com/xerpi/uam --branch switch-32

# build and install SPIRV-Cross
RUN cd SPIRV-Cross \
    && mkdir build && cd build \
    && cmake .. \
       -DCMAKE_TOOLCHAIN_FILE=../../../xerpi_gist/libnx32.toolchain.cmake \
       -DSPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS:BOOL=ON \
       -DSPIRV_CROSS_ENABLE_HLSL:BOOL=OFF \
       -DSPIRV_CROSS_ENABLE_MSL:BOOL=OFF \
       -DSPIRV_CROSS_FORCE_PIC:BOOL=ON \
       -DSPIRV_CROSS_CLI:BOOL=OFF \
    && make -j $MAKE_JOBS
RUN cd SPIRV-Cross/build && make install

# build and install fmt
USER vita2hos
RUN cd fmt \
    && mkdir build && cd build \
    && cmake .. \
       -DCMAKE_TOOLCHAIN_FILE=../../../xerpi_gist/libnx32.toolchain.cmake \
       -DFMT_TEST:BOOL=OFF \
    && make -j $MAKE_JOBS
RUN cd fmt/build && make install

# build and install glslang
USER vita2hos
RUN cd glslang \
    && mkdir build && cd build \
    && cmake .. \
       -DCMAKE_TOOLCHAIN_FILE=../../../xerpi_gist/libnx32.toolchain.cmake \
       -DENABLE_HLSL:BOOL=OFF \
       -DENABLE_GLSLANG_BINARIES:BOOL=OFF \
       -DENABLE_CTEST:BOOL=OFF \
       -DENABLE_SPVREMAPPER:BOOL=OFF \
    && make -j $MAKE_JOBS
RUN cd glslang/build && make install

# build and install uam
USER vita2hos
RUN cd uam \
    && meson \
       --cross-file ../../xerpi_gist/cross_file_switch32.txt \
       --prefix /opt/devkitpro/libnx32 \
       build
RUN cd uam/build && ninja -j $MAKE_JOBS install

FROM base

COPY --from=builder --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=builder --chown=vita2hos:vita2hos $VITASDK $VITASDK

USER vita2hos
ENTRYPOINT [ "/bin/bash" ]
