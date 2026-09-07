# Rider Development Container

This container provides .NET, SSH, and the Linux GUI libraries required to run
JetBrains Rider. The Compose configuration passes the host X11/Wayland sockets
through to the container.

## Prerequisites

- Podman and `podman-compose`
- An SSH public key at `~/.ssh/id_ed25519.pub`
- Rider extracted to `~/workspace/rider` on the host. The workspace is mounted
  at `/workspace`, so the Rider executable is `/workspace/rider/bin/rider` in
  the container.
- A graphical session with `DISPLAY`, `XAUTHORITY`, `XDG_RUNTIME_DIR`, and
  `WAYLAND_DISPLAY` set as appropriate for the host.

## Build

Pass the SSH public key as a build argument. The nested quoting is required
because an SSH public key contains spaces.

```bash
podman-compose --podman-build-args "--build-arg 'SSH_PUBKEY=$(cat ~/.ssh/id_ed25519.pub)'" -f ~/cloud_computing/dev_container/podman-compose.yml   build
```

## Create And Start

Create and start the container after building the image:

```bash
podman-compose \
  -f ~/cloud_computing/dev_container/podman-compose.yml \
  up -d
```

Confirm that it is running:

```bash
podman-compose \
  -f ~/cloud_computing/dev_container/podman-compose.yml \
  ps
```

## Run Rider

Start Rider in the running container:

```bash
podman exec -d dev_container_net /workspace/rider/bin/rider
```

To run Rider in the foreground and see startup errors, omit `-d`:

```bash
podman exec -d  dev_container_net /root/rider/bin/rider

```

## SSH Access

Connect to the container using the key supplied during the build:

```bash
ssh -i ~/.ssh/id_ed25519 -p 2222 root@localhost
```

This SSH endpoint can also be used by JetBrains Rider Remote Development or
JetBrains Gateway.

## Stop And Restart

Stop the container without removing it:

```bash
podman-compose \
  -f ~/cloud_computing/dev_container/podman-compose.yml \
  stop
```

Start the existing container again:

```bash
podman-compose \
  -f ~/cloud_computing/dev_container/podman-compose.yml \
  start
```

Stop and remove the container and network:

```bash
podman-compose \
  -f ~/cloud_computing/dev_container/podman-compose.yml \
  down
```
