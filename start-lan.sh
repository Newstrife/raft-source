#!/usr/bin/env bash
# Local convenience launcher (not part of the upstream snapshot).
# Starts the raft dev environment for LAN access:
#   - Web UI (vite dev + HMR) on https://<LAN-IP>:15244 for PC browsers
#   - Production bundle (vite preview) on http://localhost:15245, exposed
#     through a cloudflared quick tunnel for the mobile app. The tunnel gets
#     the built bundle because vite dev's ~769-module waterfall trips
#     Cloudflare quick-tunnel request limits (429 cf-int-tunnel-request-limit),
#     which white-screens the app on phones.
#   - Auto-stop disabled
set -euo pipefail
cd "$(dirname "$0")"

# Pin the toolchain to the Node version in .node-version (mise install node@24.22.3).
export PATH="/home/edward/.local/share/mise/installs/node/24.22.3/bin:/home/edward/.local/bin:$PATH"

export SLOCKDEV_IDLE_TTL_SECONDS=0
# Survive stop/start with the environment's data: Postgres moves to a named
# volume and stop preserves it plus the RustFS attachments volume and the seed
# file (the next start skips seeding). `./raftdev nuke` still removes everything.
export SLOCKDEV_KEEP_DATA=1
export VITE_DEV_HOST=0.0.0.0
export VITE_DEV_HTTPS_KEY="$PWD/.slockdev/certs/key.pem"
export VITE_DEV_HTTPS_CERT="$PWD/.slockdev/certs/cert.pem"

# The tunnel serves the production build (packages/web/dist) via `vite preview`.
WEB_PORT_FOR_PREVIEW=15245
if [ ! -f packages/web/dist/index.html ]; then
  echo "[start-lan] packages/web/dist missing; building (pnpm --filter @botiverse/raft-web run build:vite)..."
  (cd packages/web && SLOCK_SERVER_PORT=13072 VITE_DEPLOYMENT_ENV=slockdev VITE_SLOCKDEV_ENV_NAME=raft-source pnpm run build:vite)
fi
# Restart the preview server cleanly on its port.
lsof -ti:"$WEB_PORT_FOR_PREVIEW" | xargs -r kill 2>/dev/null || true
(
  cd packages/web
  # Unset the HTTPS opt-in: the tunnel origin is plain http on loopback, and
  # vite preview otherwise inherits server.https from the dev config.
  env -u VITE_DEV_HTTPS_KEY -u VITE_DEV_HTTPS_CERT \
    SLOCK_SERVER_PORT=13072 VITE_DEV_PORT=$WEB_PORT_FOR_PREVIEW \
    nohup pnpm run preview >/tmp/raft-web-preview.log 2>&1 &
)
export SLOCKDEV_TUNNEL_ORIGIN="http://localhost:$WEB_PORT_FOR_PREVIEW"

exec ./raftdev start "$@"
