# Dokploy on macOS

This fork supports a containerized Dokploy installation on an Apple Silicon Mac with OrbStack.
It uses Dokploy `v0.30.6` from commit `6dcd0e185939292c9e07b3829c38b669b3c8cb78`.

## Build the image

Run from this repository with Docker running:

```sh
docker build --platform linux/arm64 -f Dockerfile.macos \
  -t nakamadevs/dokploy:0.30.6-macos .
```

The build uses the upstream runtime image by digest and the committed pnpm lockfile.
It builds the application from this checkout.
It derives build environment files from the public production template.
The Dockerfile-specific ignore file excludes private environment files.

## Prepare the host

Run these commands on the target Mac. Use its local Docker context.
The installation uses a single-node Swarm.

```sh
export DOKPLOY_HOST_ROOT_PATH="$HOME/.local/share/dokploy"
bash scripts/macos-install.sh prepare
```

Keep PostgreSQL, authentication, encryption, and administrator credentials in your password manager.
Create these Docker secrets from the stored values through standard input:

```sh
op read "$POSTGRES_PASSWORD_REF" | docker secret create dokploy_postgres_password -
op read "$AUTH_SECRET_REF" | docker secret create dokploy_auth_secret -
op read "$ENCRYPTION_KEY_REF" | docker secret create dokploy_encryption_key -
```

Each reference must identify its existing password-manager field.
Use independently generated values with at least 32 random bytes.
Keep these values unchanged during upgrades.

## Start and register

Load the built image on the target Mac, then run:

```sh
export DOKPLOY_IMAGE=nakamadevs/dokploy:0.30.6-macos
export POSTGRES_IMAGE=postgres:16@sha256:f1c3376c26f2609ab9f29f71f824103fe2fcd8ee0346485cb6122a4f93df6f94
bash scripts/macos-install.sh install
```

The script creates PostgreSQL and Dokploy services.
A temporary HTTP proxy exposes registration only on the Mac's loopback address.
PostgreSQL has no published host port.

On the target Mac, open `http://127.0.0.1:3000`.
From another machine, create an SSH tunnel:

```sh
ssh -N -L 13000:127.0.0.1:3000 hdbmm
```

Then open `http://localhost:13000` and create the administrator account.
Store its password in your password manager.

After registration, publish the dashboard and start Traefik:

```sh
export TRAEFIK_IMAGE=traefik:v3.6.25@sha256:31267173a15b4944e797a76ffd9c419707c8d8b32fe5b610f80cd0cfa05f372d
bash scripts/macos-install.sh publish
```

The script verifies that an owner exists before it publishes port `3000`.
It removes the temporary proxy and starts Traefik on ports `80` and `443`.
For `hdbmm`, the dashboard address is `http://hdbmm.local:3000`.

## Filesystem layout

The same host directory is mounted at `/etc/dokploy` and its original absolute macOS path.
Set `DOKPLOY_HOST_ROOT_PATH` to that macOS path.
Local application paths, Compose directories, file mounts, Traefik, and monitoring then share the Docker host's filesystem namespace.
The `/etc/dokploy` mount supports fixed paths in upstream code.
Remote Linux servers continue to use `/etc/dokploy`.

PostgreSQL data uses the `dokploy-postgres` Docker volume.
Docker client configuration uses the `dokploy` volume.
Monitoring reports the Docker Linux environment, not the physical macOS host.

## Verify and operate

```sh
docker service ls
curl --fail http://127.0.0.1:3000/api/trpc/settings.health
docker service logs --tail 80 dokploy
docker logs --tail 80 dokploy-traefik
```

Enable monitoring through the administrator settings after registration.
Store the monitoring token in your password manager.
Test application file mounts, Compose relative mounts, and a Traefik route before deploying workloads.

Use a verified fork image for upgrades.
The upstream dashboard updater installs the upstream image and removes this fork's macOS support.
Record the previous image ID before an upgrade.
Back up PostgreSQL, the host data directory, and Docker volumes before database migrations.
If rollback requires an older database schema, restore the matching backup.
Do not remove persistent volumes during rollback.

## Development checks

```sh
pnpm install --frozen-lockfile
pnpm --filter=@dokploy/server typecheck
pnpm --filter=dokploy test --run __test__/setup/host-paths.test.ts
bash -n scripts/macos-install.sh
git diff --check
```

The upstream `*.real.test.ts` suites require Docker, network access, and build tools.
Run them only in a disposable test environment.

Upstream GitHub Actions jobs run only in `Dokploy/dokploy`.
They remain inactive in this fork, including release and formatting automation.
Run the local checks before publishing fork changes.
