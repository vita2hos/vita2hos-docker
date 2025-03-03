FROM archlinux:base-devel AS base

ARG MAKE_JOBS=1

# prepare devkitpro env
ENV DEVKITPRO=/opt/devkitpro
ENV DEVKITARM=/opt/devkitpro/devkitARM
ENV DEVKITPPC=/opt/devkitpro/devkitPPC
ENV PATH=${DEVKITPRO}/tools/bin:${DEVKITARM}/bin:${PATH}

# perl pod2man
ENV PATH=/usr/bin/core_perl:${PATH}

ARG BUILDSCRIPTS_HASH=d707f1e4f987c6fdb5af05c557e26c1cc868f734
ARG SPIRV_CROSS_VER=sdk-1.3.261.1
ARG FMTLIB_VER=10.1.1
ARG GLSLANG_VER=sdk-1.3.261.1
ARG MINIZ_VER=3.0.2

# Use labels to make images easier to organize
LABEL buildscripts.version="${BUILDSCRIPTS_HASH}"

ARG DEBIAN_FRONTEND=noninteractive

# Add a new user (and group) vita2hos
RUN useradd -s /bin/bash -m vita2hos

# Add environment variables
RUN echo "export DEVKITPRO=${DEVKITPRO}" > /etc/profile.d/devkit-env.sh \
    && echo "export DEVKITARM=${DEVKITPRO}/devkitARM" >> /etc/profile.d/devkit-env.sh \
    && echo "export DEVKITPPC=${DEVKITPRO}/devkitPPC" >> /etc/profile.d/devkit-env.sh \
    && echo "export PATH=${DEVKITPRO}/tools/bin:$PATH" >> /etc/profile.d/devkit-env.sh

# Create devkitpro dir
USER root
RUN mkdir -p -m 0775 ${DEVKITPRO} && chown -R vita2hos:vita2hos ${DEVKITPRO}

# Copy devkitPro cmake files from the official docker images
COPY --from=devkitpro/devkitarm --chown=vita2hos:vita2hos ${DEVKITPRO}/cmake ${DEVKITPRO}/cmake
COPY --from=devkitpro/devkita64 --chown=vita2hos:vita2hos ${DEVKITPRO}/cmake ${DEVKITPRO}/cmake

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
RUN pacman -Syu --needed --noconfirm \
    base-devel git cmake meson ninja \
    sudo binutils \
    openbsd-netcat openssh \
    pkgconf wget curl \
    python python-pip python-setuptools python-mako \
    perl \
    bison flex texinfo \
    libmpc libtool automake autoconf lz4 libelf xz bzip2 \
    && pacman -Scc --noconfirm

FROM base AS prepare

# Download public key for github.com
RUN mkdir -p -m 0700 ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts

RUN ls -la /home

# Switch to vita2hos user
USER vita2hos
WORKDIR /home/vita2hos

# Download devkitARM Switch 32-bits gist
RUN git clone https://gist.github.com/82c7ca88861297d7fa57dc73a3ea576c.git xerpi_gist

FROM prepare AS buildscripts

# Run devkitPro's buildscripts to install GCC, binutils and newlib (1 = devkitARM)
RUN git clone https://github.com/xerpi/buildscripts.git \
    && cd buildscripts && git checkout ${BUILDSCRIPTS_HASH} \
    && MAKEFLAGS="-j ${MAKE_JOBS}" BUILD_DKPRO_AUTOMATED=1 BUILD_DKPRO_PACKAGE=1 ./build-devkit.sh

FROM buildscripts AS general-tools

# Clone devkitPro's general-tools and install it
RUN git clone https://github.com/devkitPro/general-tools.git \
    && cd general-tools \
    && ./autogen.sh \
    && ./configure --prefix=${DEVKITPRO}/tools \
    && make -j $MAKE_JOBS install

FROM general-tools AS switch-tools

# Clone switch-tools fork and install it
RUN git clone https://github.com/xerpi/switch-tools.git --branch arm-32-bit-support
RUN cd switch-tools && ./autogen.sh \
    && ./configure --prefix=${DEVKITPRO}/tools/ \
    && make -j $MAKE_JOBS install

FROM switch-tools AS libnx

# Clone libnx fork and install it
RUN git clone https://github.com/xerpi/libnx.git
RUN cd libnx && make -j $MAKE_JOBS -C nx/ -f Makefile.32 install

FROM libnx AS dekotools

# Clone and install dekotools
RUN git clone https://github.com/fincs/dekotools
RUN cd dekotools && meson build --prefix $DEVKITPRO/tools
RUN cd dekotools/build && ninja install -j $MAKE_JOBS

FROM dekotools AS deko3d

# Clone deko3d fork and install it
RUN git clone https://github.com/xerpi/deko3d.git
RUN cd deko3d && make -f Makefile.32 -j $MAKE_JOBS install

FROM deko3d AS portlibs-prepare

# prepare portlibs
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
    -DCMAKE_TOOLCHAIN_FILE=../../xerpi_gist/libnx32.toolchain.cmake \
    -DSPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS:BOOL=ON \
    -DSPIRV_CROSS_ENABLE_HLSL:BOOL=OFF \
    -DSPIRV_CROSS_ENABLE_MSL:BOOL=OFF \
    -DSPIRV_CROSS_FORCE_PIC:BOOL=ON \
    -DSPIRV_CROSS_CLI:BOOL=OFF \
    && make -j $MAKE_JOBS
RUN cd SPIRV-Cross/build && make install

FROM spirv AS fmt

# build and install fmt
RUN cd fmt \
    && mkdir build && cd build \
    && cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=../../xerpi_gist/libnx32.toolchain.cmake \
    -DFMT_TEST:BOOL=OFF \
    && make -j $MAKE_JOBS
RUN cd fmt/build && make install

FROM fmt AS glslang

# build and install glslang
RUN cd glslang \
    && mkdir build && cd build \
    && cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=../../xerpi_gist/libnx32.toolchain.cmake \
    -DENABLE_HLSL:BOOL=OFF \
    -DENABLE_GLSLANG_BINARIES:BOOL=OFF \
    -DENABLE_CTEST:BOOL=OFF \
    -DENABLE_SPVREMAPPER:BOOL=OFF \
    && make -j $MAKE_JOBS
RUN cd glslang/build && make install

FROM glslang AS uam

# build and install uam as a host executable
RUN cd uam \
    && meson \
    --prefix $DEVKITPRO/tools \
    build_host
RUN cd uam/build_host && ninja -j $MAKE_JOBS install

# build and install uam
RUN cd uam \
    && meson \
    --cross-file ../xerpi_gist/cross_file_switch32.txt \
    --prefix $DEVKITPRO/libnx32 \
    build
RUN cd uam/build && ninja -j $MAKE_JOBS install

FROM uam AS miniz

# build and install glslang
RUN cd miniz \
    && mkdir build && cd build \
    && cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=../../xerpi_gist/libnx32.toolchain.cmake \
    && make -j $MAKE_JOBS
RUN cd miniz/build && make install

FROM base AS final

COPY --from=buildscripts --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO

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
