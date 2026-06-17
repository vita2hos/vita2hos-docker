#!/usr/bin/env bash

#------------------------------------------------------------
# In case someone from devkitPro finds this:
# I'm truly sorry for creating this script.
# I'd much prefer to use the packages as you release them,
# but without support for 32-bit binaries on the switch
# we'd need to patch your toolchains one way or another.
# I'm not even sure if the changes made to them
# could be upstreamed in a reasonable way.
# Seeing that the homebrew ABI still doesn't support 32-bit,
# I don't think you could expect us to just wait around.
# At least for the tiny experiment that is vita2hos,
# I hope you could look the other way for some time.
#------------------------------------------------------------

BUILD_DKPRO_PACKAGE="1"
# Read variables
. ./select_toolchain.sh

DKARM_RULES_VER="$(grep -e 'DKARM_RULES_VER=' ./build-devkit.sh | awk -F'=' '{print $2}')"
DKARM_CRTLS_VER="$(grep -e 'DKARM_CRTLS_VER=' ./build-devkit.sh | awk -F'=' '{print $2}')"

# Download GNU archives
gnu_archive_names=("binutils-${BINUTILS_VER}.tar.xz" "gcc-${GCC_VER}.tar.xz" "newlib-${NEWLIB_VER}.tar.gz")
gnu_archive_urls=("https://ftpmirror.gnu.org/gnu/binutils/${gnu_archive_names[0]}" "https://ftpmirror.gnu.org/gnu/gcc/gcc-${GCC_VER}/${gnu_archive_names[1]}" "ftp://sourceware.org/pub/newlib/${gnu_archive_names[2]}")
for (( i=0; i<${#gnu_archive_names[@]}; i++))
do
    echo "${gnu_archive_names[$i]}"
    wget -nv --retry-on-http-error=502 "${gnu_archive_urls[$i]}"
done

# Download dkp archives
archives=("devkitarm-rules-${DKARM_RULES_VER}.tar.gz" "devkitarm-crtls-${DKARM_CRTLS_VER}.tar.gz")

for archive in "${archives[@]}"
do
    echo "${archive}"
    wget -nv -U 'Mozilla/5.0 (X11; Linux x86_64; rv:148.0) Gecko/20100101 Firefox/148.0' "https://downloads.devkitpro.org/${archive}"
done
