#!/bin/bash
set -e

log() {
    echo "[`date '+%Y-%m-%d %H:%M:%S'`] $*"
}

if [ -f /setup_postgres.py ]; then
    NODE1_HOST="postgres_node1"
    NODE2_HOST="postgres_node2"
    NODE1_PORT="5432"
    NODE2_PORT="5432"
    SETUP_SCRIPT="/setup_postgres.py"
    USE_DOCKER=false
else
    NODE1_HOST="localhost"
    NODE2_HOST="localhost"
    NODE1_PORT="5432"
    NODE2_PORT="5433"
    SETUP_SCRIPT="./setup_postgres.py"
    USE_DOCKER=true
fi

log "Ожидание готовности PostgreSQL контейнеров..."

check_db_ready() {
    local db=$1
    
    if [ "$USE_DOCKER" = true ]; then
        local container_name="lab3_postgres_node1"
        if [ "$db" = "sourcedb2" ]; then
            container_name="lab3_postgres_node2"
        fi
        
        local container=$(docker ps --filter "name=$container_name" --format "{{.Names}}" | head -1)
        if [ -n "$container" ]; then
            docker exec "$container" psql -U admin -d "$db" -c "SELECT 1" >/dev/null 2>&1
            return $?
        fi
        return 1
    else
        PGPASSWORD=adminpass psql -h "$NODE1_HOST" -p "$NODE1_PORT" -U admin -d "$db" -c "SELECT 1" >/dev/null 2>&1
    fi
}

until check_db_ready "sourcedb1"; do
    log "Ожидание postgres_node1..."
    sleep 2
done
log "postgres_node1 готов"

until check_db_ready "sourcedb2"; do
    log "Ожидание postgres_node2..."
    sleep 2
done
log "postgres_node2 готов"

log "Запуск инициализации БД..."

if [ ! -f /setup_postgres.py ]; then
    init_container=$(docker ps --filter "name=lab3_postgres_init" --format "{{.Names}}" | head -1)
    if [ -n "$init_container" ]; then
        log "Запуск инициализации через контейнер $init_container..."
        docker exec "$init_container" /usr/bin/python3 /setup_postgres.py
    else
        log "ERROR: Контейнер postgres_init не найден. Убедитесь, что Docker stack запущен."
        exit 1
    fi
else
    /usr/bin/python3 "$SETUP_SCRIPT"
fi

log "Инициализация завершена!"

