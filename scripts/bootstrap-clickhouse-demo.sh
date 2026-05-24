#!/usr/bin/env bash
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPOSE_FILE="$INFRA_DIR/docker-compose.prod.yml"
CONTAINER_SCRIPT="/docker-entrypoint-initdb.d/01-create-demo-access.sh"

cd "$INFRA_DIR"

if [[ ! -f "$INFRA_DIR/.env" ]]; then
    echo "[bootstrap-clickhouse-demo] Missing $INFRA_DIR/.env" >&2
    exit 1
fi

echo "[bootstrap-clickhouse-demo] Ensuring ClickHouse demo database(s) and readonly user..."
docker compose --env-file "$INFRA_DIR/.env" -f "$COMPOSE_FILE" exec -T clickhouse sh "$CONTAINER_SCRIPT"
echo "[bootstrap-clickhouse-demo] Done."
