FROM archlinux:base-devel AS base

# NOTE: Make sure secret id=xerpi_gist,src=secret/xerpi_gist.txt is defined

ARG MAKE_JOBS=1

# prepare devkitpro env
ENV DEVKITPRO=/opt/devkitpro
ENV DEVKITARM=/opt/devkitpro/devkitARM
ENV DEVKITPPC=/opt/devkitpro/devkitPPC
ENV PATH=${DEVKITPRO}/tools/bin:${DEVKITARM}/bin:${PATH}

# prepare vitasdk env
ENV VITASDK=/usr/local/vitasdk
ENV PATH=${VITASDK}/bin:${PATH}

ARG GCC_VER=13.2.0
ARG BINUTILS_VER=2.41
ARG NEWLIB_VER=4.3.0.20230120

ARG SPIRV_CROSS_VER=sdk-1.3.261.1
ARG FMTLIB_VER=10.1.1
ARG GLSLANG_VER=sdk-1.3.261.1
ARG MINIZ_VER=3.0.2

ARG TARGET=arm-none-eabi

# Use labels to make images easier to organize
LABEL gcc.version="${GCC_VER}"
LABEL binutils.version="${BINUTILS_VER}"
LABEL newlib.version="${NEWLIB_VER}"

ARG DEBIAN_FRONTEND=noninteractive

# add env vars for all users
RUN echo "export VITASDK=/usr/local/vitasdk" > /etc/profile.d/10-vitasdk-env.sh \
    && echo "export PATH=$VITASDK/bin:$PATH" >> /etc/profile.d/10-vitasdk-env.sh

# add a new user vita2hos
RUN useradd -s /bin/bash -m vita2hos

# copy latest dkp arm packages from DKP image
COPY --from=devkitpro/devkitarm --chown=vita2hos:vita2hos ${DEVKITPRO} ${DEVKITPRO}

# copy latest dkp aarch64 packages from DKP image
COPY --from=devkitpro/devkita64 --chown=vita2hos:vita2hos ${DEVKITPRO} ${DEVKITPRO}

# and add env vars for all users
RUN echo "export DEVKITPRO=${DEVKITPRO}" > /etc/profile.d/devkit-env.sh \
    && echo "export DEVKITARM=${DEVKITPRO}/devkitARM" >> /etc/profile.d/devkit-env.sh \
    && echo "export DEVKITPPC=${DEVKITPRO}/devkitPPC" >> /etc/profile.d/devkit-env.sh \
    && echo "export PATH=${DEVKITPRO}/tools/bin:$PATH" >> /etc/profile.d/devkit-env.sh

# install all globally required packages
RUN pacman -Syu --noconfirm \
    git curl base-devel openbsd-netcat python \
    && pacman -Scc --noconfirm

FROM base AS prepare

# ------- Information about apt packages --------
# Mako:                 (python3, python3-pip, python3-setuptools)
# // https://github.com/devkitPro/docker/blob/master/toolchain-base/Dockerfile doesn't look optimized
# DKP-Pacman:           wget, pkg-config, git, make, cmake, xz-utils, gpg, bzip2
# VPDM:                 cmake, patch, tar, curl, git, python
# binutils:             (wget, tar, gzip), build-essential
# // http://gcc.gnu.org/install/prerequisites.html
# gcc:                  (wget), tar, gzip, patch, build-essential, libgmp-dev libmpfr-dev libmpc-dev
# newlib:               (wget, tar, gzip, patch), build-essential
# dkp_general-tools:    (git), autotools-dev, automake, autoconf, build-essential
# dkARM_rules:          (wget, tar, gzip), build-essential
# dkARM_crt0:           (wget, tar, gzip), build-essential
# dkARM_gdb (py3):      (git), python3-dev, build-essential, texinfo
# libnx (xerpi):        (git), devkitARM, build-essential
# switch-tools (xerpi): (git), libnx, autotools-dev, automake, autoconf, build-essential, liblz4-dev, libelf-dev
# dekotools:            (git), meson, ninja-build
# deko3d (xerpi):       (git), dekotools, build-essential
# SPIRV-Cross:          (git), cmake, build-essential
# fmt:                  (git), cmake, build-essential
# glslang:              (git), cmake, python3, (bison)
# UAM (xerpi):          (git), meson, ninja-build, Mako[python3]

# install all the required packages
RUN pacman -S --noconfirm \
        openssh \
        python-pip python-setuptools \
        cmake bison flex \
        pkgconf wget curl \
        sudo binutils \
        libmpc \
        texinfo \
        libtool automake autoconf lz4 libelf \
        xz bzip2 \
        meson ninja \
        python-mako \
    && pacman -Scc --noconfirm

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

# # download and build samples from vitasdk
# USER vita2hos
# WORKDIR /home/vita2hos/tools/vitasdk
# RUN git clone https://github.com/vitasdk/samples \
#     && cd samples && mkdir build && cd build \
#     && cmake .. && make -j $MAKE_JOBS

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

FROM prepare AS binutils-build

# build and install binutils
RUN mkdir binutils-build && cd binutils-build \
    && ../binutils-$BINUTILS_VER/configure \
        --prefix=$DEVKITARM \
        --target=$TARGET \
        --disable-nls --disable-werror \
        --enable-lto --enable-plugins --enable-poison-system-directories \
    && make -j $MAKE_JOBS all 2>&1 | tee ./binutils-build-logs.log

FROM binutils-build AS binutils-install

RUN cd binutils-build && make install

FROM binutils-install AS gcc-build

# patch, build and install gcc
USER vita2hos
RUN cd gcc-$GCC_VER \
    && patch -p1 < ../../xerpi_gist/gcc-${GCC_VER}.patch \
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
       --with-bugurl="http://wiki.devkitpro.org/index.php/Bug_Reports" --with-pkgversion="devkitARM release 61 (mod for Switch aarch32)" \
    && make -j $MAKE_JOBS all-gcc 2>&1 | tee ./gcc-build-withoutnewlib-logs.log

FROM gcc-build AS gcc-install

RUN cd gcc-build && make install-gcc

FROM gcc-install AS newlib-build

# patch, build and install newlib
USER vita2hos
RUN git clone https://github.com/devkitPro/buildscripts \
    && cd newlib-$NEWLIB_VER \
    && patch -p1 < ../buildscripts/dkarm-eabi/patches/newlib-${NEWLIB_VER}.patch \
    && cd .. && mkdir newlib-build && cd newlib-build \
    && CFLAGS_FOR_TARGET="-O2 -ffunction-sections -fdata-sections -fPIC" \
       ../newlib-$NEWLIB_VER/configure \
       --target=$TARGET \
       --prefix=$DEVKITARM \
       --disable-newlib-supplied-syscalls \
       --enable-newlib-mb \
       --disable-newlib-wide-orient \
    && make -j $MAKE_JOBS all 2>&1 | tee ./newlib-build-logs.log

FROM newlib-build AS newlib-install

RUN cd newlib-build && make install

# remove sys-include dir in devkitARM/arm-none-eabi
RUN rm -rf $DEVKITARM/$TARGET/sys-include

FROM newlib-install AS gcc-stage2-build

# build and install gcc stage 2 (with newlib)
USER vita2hos
RUN cd gcc-build \
    && make -j $MAKE_JOBS all 2>&1 | tee ./gcc-build-withnewlib-logs.log

FROM gcc-stage2-build AS gcc-stage2-install

RUN cd gcc-build && make install

FROM gcc-stage2-install AS dkp-gdb

# Clone and install devkitARM gdb with python3 support
RUN git clone https://github.com/devkitPro/binutils-gdb -b devkitARM-gdb \
    && cd binutils-gdb \
    && ./configure --with-python=/usr/bin/python3 --prefix=$DEVKITARM --target=arm-none-eabi \
    && make -j $MAKE_JOBS && make install

FROM dkp-gdb AS libnx

# Clone private libnx fork and install it
USER root
WORKDIR /home/vita2hos/tools
RUN --mount=type=ssh git clone git@github.com:xerpi/libnx && chown vita2hos:vita2hos -R libnx
USER vita2hos
RUN cd libnx && make -j $MAKE_JOBS -C nx/ -f Makefile.32
RUN cd libnx && make -C nx/ -f Makefile.32 install

FROM libnx AS switch-tools

# Clone switch-tools fork and install it
USER root
RUN --mount=type=ssh git clone git@github.com:xerpi/switch-tools --branch arm-32-bit-support && chown vita2hos:vita2hos -R switch-tools
USER vita2hos
RUN cd switch-tools && ./autogen.sh \
    && ./configure --prefix=${DEVKITPRO}/tools/ \
    && make -j $MAKE_JOBS
RUN cd switch-tools && make install

FROM switch-tools AS dekotools

# Clone and install dekotools
USER vita2hos
RUN git clone https://github.com/fincs/dekotools
RUN cd dekotools \
    && meson build
USER root
RUN cd dekotools/build && ninja install -j $MAKE_JOBS

FROM dekotools AS deko3d

# Clone private deko3d fork and install it
USER root
RUN --mount=type=ssh git clone git@github.com:xerpi/deko3d && chown vita2hos:vita2hos -R deko3d
USER vita2hos
RUN cd deko3d && make -f Makefile.32 -j $MAKE_JOBS
RUN cd deko3d && make -f Makefile.32 install

FROM deko3d AS portlibs-prepare

# prepare portlibs
USER vita2hos
WORKDIR /home/vita2hos/tools/portlibs
RUN git clone https://github.com/KhronosGroup/SPIRV-Cross \
    && cd SPIRV-Cross && git checkout tags/${SPIRV_CROSS_VER} -b ${SPIRV_CROSS_VER} && cd .. \
    && git clone https://github.com/fmtlib/fmt \
    && cd fmt && git checkout tags/${FMTLIB_VER} -b ${FMTLIB_VER} && cd .. \
    && git clone https://github.com/KhronosGroup/glslang \
    && cd glslang && git checkout tags/${GLSLANG_VER} -b ${GLSLANG_VER} && cd .. \
    && git clone https://github.com/xerpi/uam --branch switch-32 \
    && git clone https://github.com/richgel999/miniz.git --branch ${MINIZ_VER}

FROM portlibs-prepare AS spirv

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

FROM spirv AS fmt

# build and install fmt
USER vita2hos
RUN cd fmt \
    && mkdir build && cd build \
    && cmake .. \
       -DCMAKE_TOOLCHAIN_FILE=../../../xerpi_gist/libnx32.toolchain.cmake \
       -DFMT_TEST:BOOL=OFF \
    && make -j $MAKE_JOBS
RUN cd fmt/build && make install

FROM fmt as glslang

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

FROM glslang AS uam

# build and install uam as a host executable
USER vita2hos
RUN cd uam \
    && meson \
       --prefix $DEVKITPRO/tools \
       build_host
RUN cd uam/build_host && ninja -j $MAKE_JOBS install

# build and install uam
USER vita2hos
RUN cd uam \
    && meson \
       --cross-file ../../xerpi_gist/cross_file_switch32.txt \
       --prefix $DEVKITPRO/libnx32 \
       build
RUN cd uam/build && ninja -j $MAKE_JOBS install

FROM uam as miniz

# build and install glslang
USER vita2hos
RUN cd miniz \
    && mkdir build && cd build \
    && cmake .. \
       -DCMAKE_TOOLCHAIN_FILE=../../../xerpi_gist/libnx32.toolchain.cmake \
    && make -j $MAKE_JOBS
RUN cd miniz/build && make install

FROM base AS final

COPY --from=prepare --chown=vita2hos:vita2hos $VITASDK $VITASDK

COPY --from=binutils-install --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=newlib-install --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=gcc-stage2-install --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=dkp-gdb --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO

COPY --from=libnx --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=switch-tools --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO

COPY --from=dekotools --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=deko3d --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO

COPY --from=spirv --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=fmt --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=glslang --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO

COPY --from=uam --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=miniz --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO

USER vita2hos
WORKDIR /home/vita2hos
