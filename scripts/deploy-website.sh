#!/usr/bin/env bash
# deploy-website.sh [TAG]
#
# Pulls the given website image tag (default: latest) and restarts the container.
# Persists TAG in .env so it survives reboots.
#
# Usage:
#   deploy-website.sh               # deploy latest
#   deploy-website.sh a3f1bc9       # deploy specific git SHA (or rollback)

set -euo pipefail

INFRA_DIR=/opt/datafeta-infra
COMPOSE_FILE=$INFRA_DIR/docker-compose.prod.yml
ENV_FILE=$INFRA_DIR/.env
TAG=${1:-latest}

echo "[deploy-website] Deploying tag: $TAG"

# Persist tag so docker compose uses it on reboot
if [[ -f "$ENV_FILE" ]]; then
    if grep -q "^WEBSITE_TAG=" "$ENV_FILE"; then
        sed -i "s/^WEBSITE_TAG=.*/WEBSITE_TAG=$TAG/" "$ENV_FILE"
    else
        echo "WEBSITE_TAG=$TAG" >> "$ENV_FILE"
    fi
fi

WEBSITE_TAG="$TAG" docker compose -f "$COMPOSE_FILE" pull website
WEBSITE_TAG="$TAG" docker compose -f "$COMPOSE_FILE" up -d --no-deps website

echo "[deploy-website] Done."
