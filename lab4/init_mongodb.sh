#!/bin/bash
set -e

log() {
    echo "[`date '+%Y-%m-%d %H:%M:%S'`] $*"
}

log "Ожидание готовности MongoDB контейнеров..."

NODE1_HOST="mongodb_node1"
NODE2_HOST="mongodb_node2"
NODE1_PORT="27017"
NODE2_PORT="27017"
ADMIN_USER="admin"
ADMIN_PASS="adminpass"

check_mongodb_ready() {
    local host=$1
    local port=$2
    
    mongo --host "$host:$port" --username "$ADMIN_USER" --password "$ADMIN_PASS" --authenticationDatabase admin --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1
    return $?
}

until check_mongodb_ready "$NODE1_HOST" "$NODE1_PORT"; do
    log "Ожидание $NODE1_HOST..."
    sleep 2
done
log "$NODE1_HOST готов"

until check_mongodb_ready "$NODE2_HOST" "$NODE2_PORT"; do
    log "Ожидание $NODE2_HOST..."
    sleep 2
done
log "$NODE2_HOST готов"

log "Запуск инициализации MongoDB..."
python3 /setup_mongodb.py

log "Инициализация завершена"

