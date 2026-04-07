#!/usr/bin/env sh

# Workaround until https://github.com/ninja-build/ninja/issues/1482 is implemented

if [ -n "${NINJA_JOBS}" ]; then
    ninja -j "${NINJA_JOBS}" "$@"
else
    ninja "$@"
fi
