#!/usr/bin/env bash

script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

docker build --pull --build-arg MAKE_JOBS=$(($(nproc) - 2)) "$@" -t vita2hos-dev "$script_dir"
