FROM archlinux:base-devel AS base

ARG MAKE_JOBS=1

# Prepare devkitpro env
ENV DEVKITPRO=/opt/devkitpro
ENV DEVKITARM=/opt/devkitpro/devkitARM
ENV PATH=${DEVKITPRO}/tools/bin:${DEVKITARM}/bin:${PATH}

# Overwrite libnx location (used by ${DEVKITPRO}/cmake/Platform/NintendoSwitch.cmake)
ENV NX_ROOT=${DEVKITPRO}/libnx32

# Use Ninja as the default generator for CMake
ENV CMAKE_GENERATOR=Ninja

# Perl pod2man
ENV PATH=/usr/bin/core_perl:${PATH}

ARG DEBIAN_FRONTEND=noninteractive

# Add a new user (and group) vita2hos
RUN useradd -s /bin/bash -m vita2hos

# Set passwords and add user to wheel group
RUN echo 'root:root' | chpasswd \
    && echo 'vita2hos:vita2hos' | chpasswd \
    && usermod -aG wheel vita2hos \
    && echo '%wheel ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Add environment variables
RUN echo "export DEVKITPRO=${DEVKITPRO}" > /etc/profile.d/devkit-env.sh \
    && echo "export DEVKITARM=${DEVKITPRO}/devkitARM" >> /etc/profile.d/devkit-env.sh \
    && echo "export PATH=${DEVKITPRO}/tools/bin:$PATH" >> /etc/profile.d/devkit-env.sh

# Create devkitpro dir
RUN mkdir -p -m 0755 ${DEVKITPRO}

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

# Install all the required base packages
RUN pacman -Syu --needed --noconfirm \
    base-devel git cmake meson ninja \
    sudo binutils vim \
    openbsd-netcat openssh \
    pkgconf wget curl \
    python python-pip python-setuptools python-mako \
    perl \
    bison flex texinfo \
    libmpc libtool automake autoconf lz4 libelf xz bzip2 \
    && pacman -Scc --noconfirm

# Add devkitPro pacman repository
RUN echo "[dkp-libs]" >> /etc/pacman.conf && \
    echo "Server = https://pkg.devkitpro.org/packages" >> /etc/pacman.conf && \
    echo "[dkp-linux]" >> /etc/pacman.conf && \
    echo "Server = https://pkg.devkitpro.org/packages/linux/\$arch/" >> /etc/pacman.conf

# Import and sign the devkitPro GPG key, install devkitPro keyring package and populate the keyring
RUN pacman-key --init && \
    pacman-key --recv BC26F752D25B92CE272E0F44F7FD5492264BB9D0 --keyserver keyserver.ubuntu.com && \
    pacman-key --lsign BC26F752D25B92CE272E0F44F7FD5492264BB9D0 && \
    pacman -U --noconfirm https://pkg.devkitpro.org/devkitpro-keyring.pkg.tar.zst && \
    pacman-key --populate devkitpro && \
    pacman -Syu

# Install devkitPro's general-tools and switch-cmake
RUN pacman -Sy --noconfirm general-tools dkp-cmake-common-utils devkitarm-cmake switch-cmake

# Change ownership of the devkitPro directory
RUN chown -R vita2hos:vita2hos ${DEVKITPRO}

FROM base AS prepare

# Download public key for github.com
RUN mkdir -p -m 0700 ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts

RUN ls -la /home

# Switch to vita2hos user
USER vita2hos
WORKDIR /home/vita2hos

FROM prepare AS buildscripts

# Run devkitPro's buildscripts to install GCC, binutils and newlib (1 = devkitARM)
ARG BUILDSCRIPTS_HASH=d707f1e4f987c6fdb5af05c557e26c1cc868f734
RUN git clone https://github.com/xerpi/buildscripts.git \
    && cd buildscripts && git checkout ${BUILDSCRIPTS_HASH} \
    && MAKEFLAGS="-j ${MAKE_JOBS}" BUILD_DKPRO_AUTOMATED=1 BUILD_DKPRO_PACKAGE=1 ./build-devkit.sh

FROM buildscripts AS switch-tools

# Clone switch-tools fork and install it
RUN git clone https://github.com/xerpi/switch-tools.git --branch arm-32-bit-support
RUN cd switch-tools && ./autogen.sh \
    && ./configure --prefix=${DEVKITPRO}/tools/ \
    && make -j $MAKE_JOBS install

FROM switch-tools AS libnx

# Clone libnx fork and install it
ARG LIBNX32_HASH=be0f3aade5d3a6fd67c70a8e16a1f7dc8ab2cd30
RUN git clone https://github.com/xerpi/libnx.git
RUN cd libnx && git checkout ${LIBNX32_HASH} \
    && make -j $MAKE_JOBS -C nx/ -f Makefile.32 install

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

# Prepare portlibs
ARG SPIRV_CROSS_VER=sdk-1.3.261.1
ARG FMTLIB_VER=10.1.1
ARG GLSLANG_VER=sdk-1.3.261.1
ARG MINIZ_VER=3.0.2
RUN git clone https://github.com/KhronosGroup/SPIRV-Cross \
    && cd SPIRV-Cross && git checkout tags/${SPIRV_CROSS_VER} -b ${SPIRV_CROSS_VER} && cd .. \
    && git clone https://github.com/fmtlib/fmt \
    && cd fmt && git checkout tags/${FMTLIB_VER} -b ${FMTLIB_VER} && cd .. \
    && git clone https://github.com/KhronosGroup/glslang \
    && cd glslang && git checkout tags/${GLSLANG_VER} -b ${GLSLANG_VER} && cd .. \
    && git clone https://github.com/xerpi/uam --branch switch-32 \
    && git clone https://github.com/richgel999/miniz.git --branch ${MINIZ_VER}

FROM portlibs-prepare AS spirv

# Build and install SPIRV-Cross
RUN cd SPIRV-Cross \
    && mkdir build && cd build \
    && cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=${DEVKITPRO}/cmake/devkitARM.cmake \
    -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${DEVKITPRO}/cmake/Platform/NintendoSwitch.cmake \
    -DCMAKE_EXE_LINKER_FLAGS="-specs=${NX_ROOT}/switch32.specs" \
    -DCMAKE_INSTALL_PREFIX=${NX_ROOT} \
    -DCMAKE_BUILD_TYPE=Release \
    -DSPIRV_CROSS_EXCEPTIONS_TO_ASSERTIONS:BOOL=ON \
    -DSPIRV_CROSS_ENABLE_HLSL:BOOL=OFF \
    -DSPIRV_CROSS_ENABLE_MSL:BOOL=OFF \
    -DSPIRV_CROSS_FORCE_PIC:BOOL=ON \
    -DSPIRV_CROSS_CLI:BOOL=OFF \
    && cmake --build . --target install --parallel $MAKE_JOBS

FROM spirv AS fmt

# Build and install fmt
RUN cd fmt \
    && mkdir build && cd build \
    && cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=${DEVKITPRO}/cmake/devkitARM.cmake \
    -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${DEVKITPRO}/cmake/Platform/NintendoSwitch.cmake \
    -DCMAKE_EXE_LINKER_FLAGS="-specs=${NX_ROOT}/switch32.specs" \
    -DCMAKE_INSTALL_PREFIX=${NX_ROOT} \
    -DCMAKE_BUILD_TYPE=Release \
    -DFMT_TEST:BOOL=OFF \
    && cmake --build . --target install --parallel $MAKE_JOBS

FROM fmt AS glslang

# Build and install glslang
RUN cd glslang \
    && mkdir build && cd build \
    && cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=${DEVKITPRO}/cmake/devkitARM.cmake \
    -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${DEVKITPRO}/cmake/Platform/NintendoSwitch.cmake \
    -DCMAKE_EXE_LINKER_FLAGS="-specs=${NX_ROOT}/switch32.specs" \
    -DCMAKE_INSTALL_PREFIX=${NX_ROOT} \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_HLSL:BOOL=OFF \
    -DENABLE_GLSLANG_BINARIES:BOOL=OFF \
    -DENABLE_CTEST:BOOL=OFF \
    -DENABLE_SPVREMAPPER:BOOL=OFF \
    && cmake --build . --target install --parallel $MAKE_JOBS

FROM glslang AS uam-host

# Build and install uam as a host executable
RUN cd uam \
    && meson \
    --prefix $DEVKITPRO/tools \
    build_host
RUN cd uam/build_host && ninja -j $MAKE_JOBS install

FROM uam-host AS uam-switch

# Add meson cross file for uam
COPY cross_file_switch32.txt cross_file_switch32.txt

# Build and install uam
RUN cd uam \
    && meson \
    --cross-file ../cross_file_switch32.txt \
    --prefix $DEVKITPRO/libnx32 \
    build
RUN cd uam/build && ninja -j $MAKE_JOBS install

FROM uam-switch AS miniz

# Build and install miniz
RUN cd miniz \
    && mkdir build && cd build \
    && cmake .. \
    -DCMAKE_TOOLCHAIN_FILE=${DEVKITPRO}/cmake/devkitARM.cmake \
    -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=${DEVKITPRO}/cmake/Platform/NintendoSwitch.cmake \
    -DCMAKE_EXE_LINKER_FLAGS="-specs=${NX_ROOT}/switch32.specs" \
    -DCMAKE_INSTALL_PREFIX=${NX_ROOT} \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTS:BOOL=OFF \
    -DBUILD_EXAMPLES:BOOL=OFF \
    && cmake --build . --target install --parallel $MAKE_JOBS

FROM base AS final

# Copy the entire $DEVKITPRO directory from the last build stage
COPY --from=miniz --chown=vita2hos:vita2hos $DEVKITPRO $DEVKITPRO

# Use labels to make images easier to organize
LABEL libnx32.version="${LIBNX32_HASH}"
LABEL buildscripts.version="${BUILDSCRIPTS_HASH}"

USER vita2hos
WORKDIR /home/vita2hos
