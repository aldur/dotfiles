# Pi containers

Run Pi with hosted providers or use the offline image for local inference. The
images include shell tools and start `pi-yolo` with Git metadata read-only and
`tmux` for interactive sessions. Pull or rebuild the image to update Pi.

## Quick start

Set your provider keys in the host environment, then run it. For example, with
Anthropic:

```bash
env -u SSH_AUTH_SOCK container run -it --rm \
  --read-only \
  --tmpfs /tmp:mode=1777 \
  --tmpfs /var/tmp:mode=1777 \
  --tmpfs /home/aldur:uid=501,gid=100,mode=0700 \
  --cap-drop ALL \
  --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add SYS_CHROOT \
  --env ANTHROPIC_API_KEY --env TAVILY_API_KEY \
  --volume "$PWD:/workspace" \
  ghcr.io/aldur/aldur-pi:latest \
  --env ANTHROPIC_API_KEY --env TAVILY_API_KEY
```

`TAVILY_API_KEY` is optional.

Before the image name, `--env` passes a variable into the container. After it,
`--env NAME` grants that variable to the inner sandbox. Use both for each
required key or endpoint, such as `OPENAI_API_KEY` or `PI_OPENAI_BASE_URL`. Put
sandbox options before Pi arguments.

For either image:

- Use `fish --login` after the image name to open a shell.
- Mount extra folders with `--volume`, then grant them with `--ro` or `--rw`
  after the image name. Git metadata stays read-only in writable grants.
- The tmpfs home discards settings and sessions on exit. To keep them, replace
  it with a writable home volume owned by UID 501 and GID 100.
- Add `--cpus 2` or `--memory 2G` to limit resources.

Build and load the default image from the dotfiles root:

```bash
nix build --override-input aldur-dotfiles . ./base_hosts/pi-container
container image load --input result
```

Use `aldur-pi:latest` to run the local build. The explicit build target
is `./base_hosts/pi-container#container-image-online`.

## Offline inference on macOS

The offline image omits Tavily and adds a Unix-to-TCP inference relay. Start
[sandboxed inference][0] on macOS, with its socket at
`~/.local/state/sandboxed-ai/sockets/llama-server.sock`.

Pull the image before you go offline:

```bash
container image pull ghcr.io/aldur/aldur-pi-offline:latest
```

Run it with the inference socket mounted and networking disabled:

```bash
env -u SSH_AUTH_SOCK container run -it --rm \
  --network none --no-dns \
  --read-only \
  --tmpfs /tmp:mode=1777 \
  --tmpfs /var/tmp:mode=1777 \
  --tmpfs /home/aldur:uid=501,gid=100,mode=0700 \
  --cap-drop ALL \
  --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add SYS_CHROOT \
  --volume "$HOME/.local/state/sandboxed-ai/sockets/llama-server.sock:/var/host-services/llama.sock" \
  --volume "$PWD:/workspace" \
  ghcr.io/aldur/aldur-pi-offline:latest --models 'llama-cpp/*'
```

The relay exposes inference at `127.0.0.1:8080` inside the container.
The launch flags enforce network isolation; the image itself does not.

To build locally, run these commands from the dotfiles root:

```bash
nix build --override-input aldur-dotfiles . ./base_hosts/pi-container#container-image-offline
container image load --input result
```

Use `aldur-pi-offline:latest` to run the local build.

[0]: https://github.com/aldur/sandboxed-ai
