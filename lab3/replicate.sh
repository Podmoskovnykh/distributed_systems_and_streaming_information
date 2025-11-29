#!/bin/bash
set -e

log() {
  echo "[`date '+%Y-%m-%d %H:%M:%S'`] $*"
}

log "Starting replication job..."

SRC1_HOST="${SRC1_HOST:-postgres_node1}"
SRC1_PORT="${SRC1_PORT:-5432}"
SRC1_DB="${SRC1_DB:-sourcedb1}"
SRC1_USER="${SRC1_USER:-admin}"
SRC1_PASSWORD="${SRC1_PASSWORD:-adminpass}"

SRC2_HOST="${SRC2_HOST:-postgres_node2}"
SRC2_PORT="${SRC2_PORT:-5432}"
SRC2_DB="${SRC2_DB:-sourcedb2}"
SRC2_USER="${SRC2_USER:-admin}"
SRC2_PASSWORD="${SRC2_PASSWORD:-adminpass}"

DST_HOST="${DEST_HOST:-postgres_replica}"
DST_PORT="${DEST_PORT:-5432}"
DST_DB="${DEST_DB:-replicadb}"
DST_USER="${DEST_USER:-replica}"
DST_PASSWORD="${DEST_PASSWORD:-replicapass}"

for VAR in SRC1_DB SRC1_USER SRC1_PASSWORD SRC2_DB SRC2_USER SRC2_PASSWORD DST_DB DST_USER DST_PASSWORD DST_HOST; do
    if [ -z "${!VAR}" ]; then
        log "ERROR: переменная $VAR не задана"
        exit 1
    fi
done

replicate() {
    local SRC_H="$1"
    local SRC_P="$2"
    local SRC_D="$3"
    local SRC_U="$4"
    local SRC_PW="$5"

    export PGPASSWORD="$SRC_PW"
    if ! psql -h "$SRC_H" -p "$SRC_P" -U "$SRC_U" -d "$SRC_D" -c "SELECT 1" >/dev/null 2>&1; then
        log "ERROR: нет доступа к исходной БД $SRC_H/$SRC_D"
        return 1
    fi

    log "Dumping $SRC_H/$SRC_D..."
    pg_dump -h "$SRC_H" -p "$SRC_P" -U "$SRC_U" -d "$SRC_D" \
        --clean --no-owner --no-privileges --no-acl --no-security-labels \
        > /tmp/dump.sql

    export PGPASSWORD="$DST_PASSWORD"
    if ! psql -h "$DST_HOST" -p "$DST_PORT" -U "$DST_USER" -d "$DST_DB" -c "SELECT 1" >/dev/null 2>&1; then
        log "ERROR: нет доступа к реплике $DST_HOST/$DST_DB"
        return 1
    fi

    log "Restoring dump into replica..."
    psql -h "$DST_HOST" -p "$DST_PORT" -U "$DST_USER" -d "$DST_DB" < /tmp/dump.sql
}

while true; do
    replicate "$SRC1_HOST" "$SRC1_PORT" "$SRC1_DB" "$SRC1_USER" "$SRC1_PASSWORD"
    replicate "$SRC2_HOST" "$SRC2_PORT" "$SRC2_DB" "$SRC2_USER" "$SRC2_PASSWORD"

    log "Replication cycle finished. Sleeping ${REPLICATION_INTERVAL_SECONDS:-30}s..."
    sleep "${REPLICATION_INTERVAL_SECONDS:-30}"
done
