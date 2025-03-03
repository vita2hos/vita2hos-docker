FROM archlinux:base-devel AS base

ARG MAKE_JOBS=1

# prepare devkitpro env
ENV DEVKITPRO=/opt/devkitpro
ENV DEVKITARM=/opt/devkitpro/devkitARM
ENV DEVKITPPC=/opt/devkitpro/devkitPPC
ENV PATH=${DEVKITPRO}/tools/bin:${DEVKITARM}/bin:${PATH}

# prepare vitasdk env
ENV VITASDK=/opt/vitasdk
ENV PATH=${VITASDK}/bin:${PATH}

# perl pod2man
ENV PATH=/usr/bin/core_perl:${PATH}

ARG BUILDSCRIPTS_HASH=1776e27341664059aa28ce1b148a1fd6c855e121
ARG SPIRV_CROSS_VER=sdk-1.3.261.1
ARG FMTLIB_VER=10.1.1
ARG GLSLANG_VER=sdk-1.3.261.1
ARG MINIZ_VER=3.0.2

# Use labels to make images easier to organize
LABEL buildscripts.version="${BUILDSCRIPTS_HASH}"

ARG DEBIAN_FRONTEND=noninteractive

# add env vars for all users
RUN echo "export VITASDK=$VITASDK" > /etc/profile.d/10-vitasdk-env.sh \
    && echo "export PATH=$VITASDK/bin:$PATH" >> /etc/profile.d/10-vitasdk-env.sh

# add a new user vita2hos
RUN useradd -s /bin/bash -m vita2hos

# and add env vars for all users
RUN echo "export DEVKITPRO=${DEVKITPRO}" > /etc/profile.d/devkit-env.sh \
    && echo "export DEVKITARM=${DEVKITPRO}/devkitARM" >> /etc/profile.d/devkit-env.sh \
    && echo "export DEVKITPPC=${DEVKITPRO}/devkitPPC" >> /etc/profile.d/devkit-env.sh \
    && echo "export PATH=${DEVKITPRO}/tools/bin:$PATH" >> /etc/profile.d/devkit-env.sh

# install all globally required packages
RUN pacman -Syu --noconfirm \
    git curl base-devel openbsd-netcat python cmake \
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
RUN pacman -Syu --noconfirm \
    openssh \
    python-pip python-setuptools \
    bison flex \
    pkgconf wget curl \
    sudo binutils \
    libmpc \
    texinfo \
    libtool automake autoconf lz4 libelf \
    xz bzip2 \
    meson ninja \
    python-mako \
    perl \
    && pacman -Scc --noconfirm

# Download public key for github.com
RUN mkdir -p -m 0700 ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts

# add a build structure and fix permissions
RUN mkdir -p /home/vita2hos/tools/vitasdk && mkdir -p /home/vita2hos/tools/toolchain \
    && chown vita2hos:vita2hos -R /home/vita2hos

# Create devkitpro dir
USER root
RUN mkdir -p -m 0755 ${DEVKITPRO}

# Create vitasdk dir
USER root
RUN mkdir -p -m 0755 ${VITASDK}

USER root
WORKDIR /home/vita2hos/tools
RUN git clone https://gist.github.com/82c7ca88861297d7fa57dc73a3ea576c.git xerpi_gist \
    && chown vita2hos:vita2hos -R xerpi_gist

# download buildscripts
USER vita2hos
WORKDIR /home/vita2hos/tools/toolchain
RUN git clone https://github.com/xerpi/buildscripts.git \
    && cd buildscripts && git checkout ${BUILDSCRIPTS_HASH}

# download vitasdk package manager
WORKDIR /home/vita2hos/tools/vitasdk
RUN git clone https://github.com/vitasdk/vdpm

# # download and build samples from vitasdk
# USER vita2hos
# WORKDIR /home/vita2hos/tools/vitasdk
# RUN git clone https://github.com/vitasdk/samples \
#     && cd samples && mkdir build && cd build \
#     && cmake .. && make -j $MAKE_JOBS

FROM prepare AS buildscripts-run

# run devkitPro's buildscripts to install GCC, binutils and newlib (1 = devkitARM)
RUN cd buildscripts \
    && MAKEFLAGS='-j ${MAKE_JOBS}' BUILD_DKPRO_AUTOMATED=1 BUILD_DKPRO_PACKAGE=1 ./build-devkit.sh

FROM buildscripts-run AS libnx

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

FROM fmt AS glslang

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

FROM uam AS miniz

# build and install glslang
USER vita2hos
RUN cd miniz \
    && mkdir build && cd build \
    && cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=../../../xerpi_gist/libnx32.toolchain.cmake \
    && make -j $MAKE_JOBS
RUN cd miniz/build && make install

FROM miniz AS vitasdk

# install vitasdk
RUN cd vdpm && ./bootstrap-vitasdk.sh && ./install-all.sh

FROM base AS final

COPY --from=buildscripts-run --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO

COPY --from=libnx --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=switch-tools --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO

COPY --from=dekotools --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=deko3d --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO

COPY --from=spirv --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=fmt --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=glslang --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO

COPY --from=uam --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO
COPY --from=miniz --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO

COPY --from=vitasdk --chown=vita2hos:vita2hos $VITASDK $VITASDK

USER vita2hos
WORKDIR /home/vita2hos
