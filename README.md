# vita2hos-docker

Vita2HOS development environment in a docker container

## How to pull the image

Please read the following Github Docs:

- [Authenticating to the Container registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-to-the-container-registry)
- [Pulling container images](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#pulling-container-images)
  - Note: This is an optional step, since the image will be automatically pulled once you try to use/run it

## How to use the image

### VSCode - dev container

1. Pull the dev container image: `ghcr.io/jeliebig/devcontainer/vita2hos`
2. Create a `.devcontainer.json` in the root of your project and add the following content to it:

    ```json
    {
      "image": "ghcr.io/jeliebig/devcontainer/vita2hos"
    }
    ```

3. Now open your project in VSCode and you should be able to reopen the folder using the dev container!

If you want to get more information about dev container have a look at [this](https://code.visualstudio.com/docs/remote/containers).

### Build a project (without using a dev container)

```bash
sudo docker run --rm -it -v $pwd:/workdir ghcr.io/jeliebig/vita2hos-docker:<tag>
# a new bash will be spawned
cd /workdir
make -j $(($(nproc) - 2))
exit
```

## How to build the image

1. Add your github ssh key to your ssh-agent

    ```bash
    ssh-add <path-to-your-key>
    ```

2. Create the secret file `secret/xerpi_gist.txt` and write the URL of the gist to it

3. Run this command to build the image and add the tag `vita2hos-docker` to it

    ```bash
    sudo DOCKER_BUILDKIT=1 docker build --ssh default=${SSH_AUTH_SOCK} --build-arg MAKE_JOBS=$(($(nproc) - 2)) --secret id=xerpi_gist,src=secret/xerpi_gist.txt -t vita2hos-docker .
    ```
