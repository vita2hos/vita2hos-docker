# vita2hos-docker

Vita2HOS development environment in a docker container

## How to build the image

1. Add your github ssh key to your ssh-agent

    ```bash
    ssh-add <path-to-your-key>
    ```

2. Create a file called `xerpi_gist.txt` and write the URL of the gist to it

3. Run this command to build the image and add the tag vita2hos-dev to it

    ```bash
    sudo DOCKER_BUILDKIT=1 docker build --ssh default=${SSH_AUTH_SOCK} --build-arg MAKE_JOBS=$nproc --secret id=xerpi_gist,src=xerpi_gist.txt -t vita2hos-dev .
    ```
