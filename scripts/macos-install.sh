#!/bin/bash
set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export DOKPLOY_HOST_ROOT_PATH="${DOKPLOY_HOST_ROOT_PATH:-$HOME/.local/share/dokploy}"

fail() { echo "$*" >&2; exit 1; }
[ "$(uname -s)" = Darwin ] || fail "Run this script on the macOS Docker host."
case "$DOKPLOY_HOST_ROOT_PATH" in
  /Users/*) ;;
  *) fail "Set DOKPLOY_HOST_ROOT_PATH to a shared absolute path under /Users." ;;
esac
docker info >/dev/null

case "${1:-}" in
  prepare)
    state=$(docker info --format '{{.Swarm.LocalNodeState}}')
    if [ "$state" = inactive ]; then
      # This installation uses one host. Cross-host Swarm networking is separate.
      docker swarm init --advertise-addr 127.0.0.1 >/dev/null
    fi
    [ "$(docker info --format '{{.Swarm.ControlAvailable}}')" = true ] || fail "Docker must be a Swarm manager."
    if docker network inspect dokploy-network >/dev/null 2>&1; then
      [ "$(docker network inspect dokploy-network --format '{{.Driver}}')" = overlay ] || fail "dokploy-network must use overlay networking."
    else
      docker network create --driver overlay --attachable dokploy-network >/dev/null
    fi
    mkdir -p "$DOKPLOY_HOST_ROOT_PATH"
    chmod 700 "$DOKPLOY_HOST_ROOT_PATH"
    echo "Swarm, network, and data directory are ready."
    ;;
  install)
    : "${DOKPLOY_IMAGE:?Set DOKPLOY_IMAGE to the locally built fork image.}"
    : "${POSTGRES_IMAGE:?Set POSTGRES_IMAGE to an image pinned by digest.}"
    case "$POSTGRES_IMAGE" in *@sha256:*) ;; *) fail "Pin POSTGRES_IMAGE by digest." ;; esac
    docker image inspect "$DOKPLOY_IMAGE" >/dev/null
    docker network inspect dokploy-network >/dev/null
    [ -d "$DOKPLOY_HOST_ROOT_PATH" ] || fail "Run prepare first."
    for secret in dokploy_postgres_password dokploy_auth_secret dokploy_encryption_key; do
      docker secret inspect "$secret" >/dev/null
    done
    if docker service inspect dokploy >/dev/null 2>&1; then
      fail "Dokploy already exists. Use a reviewed service update to upgrade it."
    fi
    if docker service inspect dokploy-postgres >/dev/null 2>&1; then
      [ "$(docker service inspect dokploy-postgres --format '{{index .Spec.Labels "com.nakama.managed"}}')" = dokploy ] || fail "An unmanaged dokploy-postgres service already exists."
    else
      docker service create --detach --name dokploy-postgres \
        --label com.nakama.managed=dokploy --constraint 'node.role==manager' \
        --network dokploy-network --env POSTGRES_USER=dokploy --env POSTGRES_DB=dokploy \
        --secret source=dokploy_postgres_password,target=postgres_password \
        --env POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password \
        --mount type=volume,source=dokploy-postgres,target=/var/lib/postgresql/data \
        "$POSTGRES_IMAGE" >/dev/null
    fi
    # Both mounts refer to the same data. The first covers upstream fixed paths.
    # The second makes Compose and application bind sources visible to Docker.
    docker service create --detach --no-resolve-image --name dokploy \
      --label com.nakama.managed=dokploy --replicas 1 --constraint 'node.role==manager' \
      --network dokploy-network --update-order stop-first \
      --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
      --mount "type=bind,source=$DOKPLOY_HOST_ROOT_PATH,target=/etc/dokploy" \
      --mount "type=bind,source=$DOKPLOY_HOST_ROOT_PATH,target=$DOKPLOY_HOST_ROOT_PATH" \
      --mount type=volume,source=dokploy,target=/root/.docker \
      --secret source=dokploy_postgres_password,target=postgres_password \
      --secret source=dokploy_auth_secret,target=dokploy_auth_secret \
      --secret source=dokploy_encryption_key,target=dokploy_encryption_key \
      --env POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password \
      --env BETTER_AUTH_SECRET_FILE=/run/secrets/dokploy_auth_secret \
      --env ENCRYPTION_KEY_FILE=/run/secrets/dokploy_encryption_key \
      --env "DOKPLOY_HOST_ROOT_PATH=$DOKPLOY_HOST_ROOT_PATH" \
      --env RELEASE_TAG=latest --env ADVERTISE_ADDR=127.0.0.1 \
      "$DOKPLOY_IMAGE" >/dev/null
    # Registration uses a temporary HTTP proxy bound only to this Mac's loopback.
    docker run --detach --name dokploy-bootstrap --network dokploy-network \
      --label com.nakama.managed=dokploy --publish 127.0.0.1:3000:3000 \
      --entrypoint node "$DOKPLOY_IMAGE" -e '
        const http = require("node:http");
        http.createServer((request, response) => {
          const upstream = http.request({ hostname: "dokploy", port: 3000,
            path: request.url, method: request.method, headers: request.headers }, result => {
            response.writeHead(result.statusCode, result.headers);
            result.pipe(response);
          });
          upstream.on("error", () => { response.writeHead(503); response.end("Dokploy is starting."); });
          request.pipe(upstream);
        }).listen(3000, "0.0.0.0");
      ' >/dev/null
    echo "Create the owner through http://127.0.0.1:3000 on this Mac, or an SSH tunnel."
    ;;
  publish)
    : "${TRAEFIK_IMAGE:?Set TRAEFIK_IMAGE to an image pinned by digest.}"
    case "$TRAEFIK_IMAGE" in *@sha256:*) ;; *) fail "Pin TRAEFIK_IMAGE by digest." ;; esac
    [ -f "$DOKPLOY_HOST_ROOT_PATH/traefik/traefik.yml" ] || fail "Wait for Dokploy to create its Traefik configuration."
    postgres=$(docker ps --filter label=com.docker.swarm.service.name=dokploy-postgres --format '{{.ID}}' | head -1)
    [ -n "$postgres" ] || fail "PostgreSQL is not running."
    owners=$(docker exec "$postgres" psql -U dokploy -d dokploy -tAc "SELECT count(*) FROM member WHERE role = 'owner'")
    [ "$owners" -gt 0 ] || fail "Create the administrator account before publishing."
    if ! docker inspect dokploy-traefik >/dev/null 2>&1; then
      docker run --detach --name dokploy-traefik --restart always \
        --label com.nakama.managed=dokploy --network dokploy-network \
        --mount "type=bind,source=$DOKPLOY_HOST_ROOT_PATH/traefik/traefik.yml,target=/etc/traefik/traefik.yml" \
        --mount "type=bind,source=$DOKPLOY_HOST_ROOT_PATH/traefik/dynamic,target=/etc/dokploy/traefik/dynamic" \
        --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock,readonly \
        --publish 80:80/tcp --publish 443:443/tcp --publish 443:443/udp \
        "$TRAEFIK_IMAGE" >/dev/null
    fi
    ports=$(docker service inspect dokploy --format '{{range .Endpoint.Ports}}{{.PublishedPort}} {{end}}')
    if docker inspect dokploy-bootstrap >/dev/null 2>&1; then
      [ "$(docker inspect dokploy-bootstrap --format '{{index .Config.Labels "com.nakama.managed"}}')" = dokploy ] || fail "An unmanaged bootstrap container exists."
      docker rm --force dokploy-bootstrap >/dev/null
    fi
    case " $ports " in
      *" 3000 "*) ;;
      *) docker service update --detach --publish-add published=3000,target=3000,mode=host dokploy >/dev/null ;;
    esac
    echo "Dokploy is available on port 3000. Traefik uses ports 80 and 443."
    ;;
  *) fail "Usage: $0 prepare|install|publish" ;;
esac
