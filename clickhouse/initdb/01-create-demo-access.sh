#!/bin/sh
set -eu

trim() {
    printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

escape_sql_string() {
    printf '%s' "$1" | sed "s/'/''/g"
}

DEMO_DATABASES_RAW="${CLICKHOUSE_DEMO_DATABASES:-}"
DEMO_USER="$(trim "${CLICKHOUSE_DEMO_USER:-demo_readonly}")"
DEMO_PASSWORD="${CLICKHOUSE_DEMO_PASSWORD:-}"

if [ -z "$DEMO_DATABASES_RAW" ]; then
    echo "[clickhouse-init] No CLICKHOUSE_DEMO_DATABASES configured; skipping demo bootstrap."
    exit 0
fi

case "$DEMO_PASSWORD" in
    ""|change-me*)
        echo "[clickhouse-init] Refusing to create demo user with an empty or placeholder password." >&2
        exit 1
        ;;
esac

DEMO_PASSWORD_ESCAPED="$(escape_sql_string "$DEMO_PASSWORD")"

OLD_IFS=$IFS
IFS=','
set -- $DEMO_DATABASES_RAW
IFS=$OLD_IFS

clickhouse-client --query "CREATE USER IF NOT EXISTS \`$DEMO_USER\` IDENTIFIED BY '$DEMO_PASSWORD_ESCAPED'"
clickhouse-client --query "ALTER USER \`$DEMO_USER\` IDENTIFIED BY '$DEMO_PASSWORD_ESCAPED' SETTINGS readonly = 1"

for raw_database in "$@"; do
    database="$(trim "$raw_database")"
    if [ -z "$database" ]; then
        continue
    fi

    echo "[clickhouse-init] Ensuring demo database exists: $database"
    clickhouse-client --query "CREATE DATABASE IF NOT EXISTS \`$database\`"
    clickhouse-client --query "GRANT SHOW, SELECT ON \`$database\`.* TO \`$DEMO_USER\`"
done

echo "[clickhouse-init] Demo database(s) and readonly user ensured for: $DEMO_USER"
