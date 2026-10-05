# Offline Pi for Apple `container`

This host inherits the [`apple-container`](../apple-container) configuration,
strips it to its essence and only includes Pi, a few light tools, and a Unix to
TCP socket relay to let Pi connect to the inference server.

Pull the CI image from GHCR before you go offline:

```bash
container image pull ghcr.io/aldur/aldur-pi:latest
```

Or build and load the image from the dotfiles root:

```bash
nix build --override-input aldur-dotfiles . ./base_hosts/pi-container#container-image
container image load --input result
```

With inference available at `/path/to/llama.sock`, run Pi offline:

```bash
env -u SSH_AUTH_SOCK container run -it --rm --network none --no-dns \
  --volume /path/to/llama.sock:/var/host-services/llama.sock \
  --volume "$PWD:/workspace" \
  --env LLAMA_SOCKET_PATH=/var/host-services/llama.sock \
  ghcr.io/aldur/aldur-pi:latest pi-yolo --models 'llama-cpp/*'
```

For a local build, use `aldur-pi:latest` in the run command.
The image entrypoint uses socat to relay the socket to `127.0.0.1:8080`.
With no command, it starts `pi-yolo`. This uses the shared agent sandbox to
keep the workspace writable and existing `.git` metadata read-only, including
nested repositories and worktrees.

For extra folders, mount them into the container and grant them to `pi-yolo`:

```bash
env -u SSH_AUTH_SOCK container run -it --rm --network none --no-dns \
  --volume /path/to/llama.sock:/var/host-services/llama.sock \
  --volume "$PWD:/workspace" \
  --volume /path/to/reference:/reference:ro \
  --volume /path/to/output:/output \
  --env LLAMA_SOCKET_PATH=/var/host-services/llama.sock \
  ghcr.io/aldur/aldur-pi:latest \
  pi-yolo --ro /reference --rw /output --models 'llama-cpp/*'
```

`--ro` and `--rw` are repeatable; Git metadata in writable grants is protected
too. Use `fish --login` as the command to open a shell.
