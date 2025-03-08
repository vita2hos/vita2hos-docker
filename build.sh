#!/bin/bash

script_dir=$(dirname $(realpath ${BASH_SOURCE}))

docker buildx build --pull --ssh default="${SSH_AUTH_SOCK}" --build-arg MAKE_JOBS=$((`nproc` - 2)) $@ -t vita2hos-dev "$script_dir" --output type=docker
