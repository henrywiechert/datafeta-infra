#!/usr/bin/env bash
# deploy-app.sh [TAG]
#
# Pulls the given app image tag (default: latest), restarts the app container,
# and waits for the health check to confirm the new container is healthy.
# Persists TAG in .env so it survives reboots.
#
# Usage:
#   deploy-app.sh                   # deploy latest
#   deploy-app.sh a3f1bc9           # deploy specific git SHA
#   deploy-app.sh a3f1bc9           # rollback to earlier SHA

set -euo pipefail

INFRA_DIR=/opt/datafeta-infra
COMPOSE_FILE=$INFRA_DIR/docker-compose.prod.yml
ENV_FILE=$INFRA_DIR/.env
HEALTH_URL=http://127.0.0.1:8100/api/v1/health
TAG=${1:-latest}

echo "[deploy-app] Deploying tag: $TAG"

# Persist tag so docker compose uses it on reboot
if [[ -f "$ENV_FILE" ]]; then
    if grep -q "^APP_TAG=" "$ENV_FILE"; then
        sed -i "s/^APP_TAG=.*/APP_TAG=$TAG/" "$ENV_FILE"
    else
        echo "APP_TAG=$TAG" >> "$ENV_FILE"
    fi
fi

# Pull the new image
APP_TAG="$TAG" docker compose -f "$COMPOSE_FILE" pull app

# Restart only the app container (leave website container untouched)
APP_TAG="$TAG" docker compose -f "$COMPOSE_FILE" up -d --no-deps app

# Health check: 30 attempts × 3s = 90s timeout
echo "[deploy-app] Waiting for health check at $HEALTH_URL ..."
for i in $(seq 1 30); do
    if curl -sf "$HEALTH_URL" >/dev/null 2>&1; then
        echo "[deploy-app] Healthy after ${i} attempt(s). Done."
        exit 0
    fi
    sleep 3
done

echo "[deploy-app] ERROR: health check timed out after 90s" >&2
docker compose -f "$COMPOSE_FILE" logs --tail=50 app >&2
exit 1
