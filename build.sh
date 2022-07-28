#!/bin/bash

script_dir=$(dirname $(realpath ${BASH_SOURCE}))
secret_file="${script_dir}/secret/xerpi_gist.txt"

if [ -s $secret_file ]; then
	docker buildx build --pull --ssh default="${SSH_AUTH_SOCK}" --secret id=xerpi_gist,src=$secret_file --build-arg MAKE_JOBS=$((`nproc` - 2)) $@ -t vita2hos-dev "$script_dir"
else
	echo "Make sure the secret file exists and is not empty."
fi
