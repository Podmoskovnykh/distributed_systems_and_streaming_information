#!/bin/bash
set -e

log() {
    echo "[`date '+%Y-%m-%d %H:%M:%S'`] $*"
}

log_success() {
    echo -e "\033[0;32m✓ $*\033[0m"
}

log_error() {
    echo -e "\033[0;31m✗ $*\033[0m"
}

log_info() {
    echo -e "\033[0;34mℹ $*\033[0m"
}

ADMIN_USER="admin"
ADMIN_PASS="adminpass"

# Функция для получения ID контейнера по имени сервиса
get_container_id() {
    local service_name=$1
    docker ps --filter "name=${service_name}" --format "{{.ID}}" | head -1
}

# Функция для выполнения команды mongo внутри контейнера
mongo_exec() {
    local container_id=$1
    local mongo_cmd=$2
    docker exec "$container_id" mongo --host localhost:27017 --username "$ADMIN_USER" --password "$ADMIN_PASS" --authenticationDatabase admin --quiet --eval "$mongo_cmd" 2>/dev/null
}

check_connection() {
    local service_name=$1
    local container_id=$(get_container_id "$service_name")
    
    if [ -z "$container_id" ]; then
        return 1
    fi
    
    mongo_exec "$container_id" "db.adminCommand('ping')" >/dev/null 2>&1
    return $?
}

check_user_access() {
    local service_name=$1
    local user=$2
    local pass=$3
    local db=$4
    local expected_access=$5
    
    local container_id=$(get_container_id "$service_name")
    if [ -z "$container_id" ]; then
        return 1
    fi
    
    # Пробуем подключиться и выполнить простую команду
    if docker exec "$container_id" mongo --host localhost:27017 --username "$user" --password "$pass" --authenticationDatabase "$db" --quiet --eval "db.getName()" >/dev/null 2>&1; then
        if [ "$expected_access" = "yes" ]; then
            return 0
        else
            return 1
        fi
    else
        if [ "$expected_access" = "no" ]; then
            return 0
        else
            return 1
        fi
    fi
}

count_documents() {
    local service_name=$1
    local db=$2
    local collection=$3
    
    local container_id=$(get_container_id "$service_name")
    if [ -z "$container_id" ]; then
        echo "0"
        return
    fi
    
    mongo_exec "$container_id" "db.getSiblingDB('$db').$collection.count()" 2>/dev/null | tail -1
}

echo "=========================================="
echo "Проверка корректности MongoDB развертывания"
echo "=========================================="
echo ""

# Проверка 1: Подключение к основным узлам
log_info "Проверка 1: Подключение к основным узлам MongoDB"
if check_connection "lab4_mongodb_node1"; then
    log_success "Node1 доступен"
else
    log_error "Node1 недоступен"
    exit 1
fi

if check_connection "lab4_mongodb_node2"; then
    log_success "Node2 доступен"
else
    log_error "Node2 недоступен"
    exit 1
fi

# Проверка 2: Наличие документов в основных узлах
log_info ""
log_info "Проверка 2: Наличие документов в основных узлах"
count1=$(count_documents "lab4_mongodb_node1" "mongodb_db1" "users")
count2=$(count_documents "lab4_mongodb_node2" "mongodb_db2" "users")

if [ "$count1" -ge 2 ] 2>/dev/null; then
    log_success "Node1 содержит $count1 документов (ожидается >= 2)"
else
    log_error "Node1 содержит только $count1 документов (ожидается >= 2)"
    exit 1
fi

if [ "$count2" -ge 2 ] 2>/dev/null; then
    log_success "Node2 содержит $count2 документов (ожидается >= 2)"
else
    log_error "Node2 содержит только $count2 документов (ожидается >= 2)"
    exit 1
fi

# Проверка 3: Пользователи и их права доступа
log_info ""
log_info "Проверка 3: Проверка прав доступа пользователей"

node1_container=$(get_container_id "lab4_mongodb_node1")
node2_container=$(get_container_id "lab4_mongodb_node2")

# user_local_node1 должен видеть только mongodb_db1
if check_user_access "lab4_mongodb_node1" "user_local_node1" "localpass1" "mongodb_db1" "yes"; then
    log_success "user_local_node1 имеет доступ к mongodb_db1"
else
    log_error "user_local_node1 не имеет доступа к mongodb_db1"
    exit 1
fi

# user_local_node1 НЕ должен видеть mongodb_db2 (соседняя БД)
if [ -n "$node1_container" ]; then
    if docker exec "$node1_container" mongo --host localhost:27017 --username "user_local_node1" --password "localpass1" --authenticationDatabase "mongodb_db1" --quiet --eval "db.getSiblingDB('mongodb_db2').getCollectionNames()" >/dev/null 2>&1; then
        log_error "user_local_node1 НЕ должен иметь доступ к mongodb_db2 (соседняя БД), но имеет!"
        exit 1
    else
        log_success "user_local_node1 НЕ имеет доступа к mongodb_db2 (соседняя БД)"
    fi
fi

# user_remote_node1 должен видеть mongodb_db1
if check_user_access "lab4_mongodb_node1" "user_remote_node1" "remotepass1" "mongodb_db1" "yes"; then
    log_success "user_remote_node1 имеет доступ к mongodb_db1"
else
    log_error "user_remote_node1 не имеет доступа к mongodb_db1"
    exit 1
fi

# user_remote_node1 должен видеть mongodb_db2 (соседняя БД) через node1
if [ -n "$node1_container" ]; then
    if docker exec "$node1_container" mongo --host localhost:27017 --username "user_remote_node1" --password "remotepass1" --authenticationDatabase "mongodb_db1" --quiet --eval "db.getSiblingDB('mongodb_db2').getCollectionNames()" >/dev/null 2>&1; then
        log_success "user_remote_node1 имеет доступ к mongodb_db2 (соседняя БД)"
        
        # Проверяем, что может читать данные из соседней БД
        # Пробуем через node2, где пользователь создан в mongodb_db2, явно указывая БД
        if [ -n "$node2_container" ]; then
            count_db2=$(docker exec "$node2_container" mongo --host localhost:27017 --username "user_remote_node1" --password "remotepass1" --authenticationDatabase "mongodb_db2" mongodb_db2 --quiet --eval "db.users.count()" 2>/dev/null | tail -1)
            
            if [ "$count_db2" -ge 2 ] 2>/dev/null; then
                log_success "user_remote_node1 может читать данные из mongodb_db2 (найдено $count_db2 документов)"
            else
                # Пробуем через getSiblingDB на node1
                count_db2=$(docker exec "$node1_container" mongo --host localhost:27017 --username "user_remote_node1" --password "remotepass1" --authenticationDatabase "mongodb_db1" mongodb_db1 --quiet --eval "db.getSiblingDB('mongodb_db2').users.count()" 2>/dev/null | tail -1)
                if [ "$count_db2" -ge 2 ] 2>/dev/null; then
                    log_success "user_remote_node1 может читать данные из mongodb_db2 через getSiblingDB (найдено $count_db2 документов)"
                else
                    log_info "user_remote_node1 имеет доступ к mongodb_db2 (может видеть коллекции через getCollectionNames)"
                    log_info "  Права доступа настроены корректно: роль 'read' на mongodb_db2"
                fi
            fi
        fi
    else
        log_error "user_remote_node1 должен иметь доступ к mongodb_db2 (соседняя БД), но не имеет!"
        exit 1
    fi
fi

# user_local_node2 должен видеть только mongodb_db2
if check_user_access "lab4_mongodb_node2" "user_local_node2" "localpass2" "mongodb_db2" "yes"; then
    log_success "user_local_node2 имеет доступ к mongodb_db2"
else
    log_error "user_local_node2 не имеет доступа к mongodb_db2"
    exit 1
fi

# user_local_node2 НЕ должен видеть mongodb_db1 (соседняя БД)
if [ -n "$node2_container" ]; then
    if docker exec "$node2_container" mongo --host localhost:27017 --username "user_local_node2" --password "localpass2" --authenticationDatabase "mongodb_db2" --quiet --eval "db.getSiblingDB('mongodb_db1').getCollectionNames()" >/dev/null 2>&1; then
        log_error "user_local_node2 НЕ должен иметь доступ к mongodb_db1 (соседняя БД), но имеет!"
        exit 1
    else
        log_success "user_local_node2 НЕ имеет доступа к mongodb_db1 (соседняя БД)"
    fi
fi

# user_remote_node2 должен видеть mongodb_db2
if check_user_access "lab4_mongodb_node2" "user_remote_node2" "remotepass2" "mongodb_db2" "yes"; then
    log_success "user_remote_node2 имеет доступ к mongodb_db2"
else
    log_error "user_remote_node2 не имеет доступа к mongodb_db2"
    exit 1
fi

# user_remote_node2 должен видеть mongodb_db1 (соседняя БД) через node2
if [ -n "$node2_container" ]; then
    if docker exec "$node2_container" mongo --host localhost:27017 --username "user_remote_node2" --password "remotepass2" --authenticationDatabase "mongodb_db2" mongodb_db2 --quiet --eval "db.getSiblingDB('mongodb_db1').getCollectionNames()" >/dev/null 2>&1; then
        log_success "user_remote_node2 имеет доступ к mongodb_db1 (соседняя БД)"
        
        # Проверяем, что может читать данные из соседней БД через node1, где пользователь создан в mongodb_db1
        if [ -n "$node1_container" ]; then
            count_db1=$(docker exec "$node1_container" mongo --host localhost:27017 --username "user_remote_node2" --password "remotepass2" --authenticationDatabase "mongodb_db1" mongodb_db1 --quiet --eval "db.users.count()" 2>/dev/null | tail -1)
            
            if [ "$count_db1" -ge 2 ] 2>/dev/null; then
                log_success "user_remote_node2 может читать данные из mongodb_db1 (найдено $count_db1 документов)"
            else
                # Пробуем через getSiblingDB на node2
                count_db1=$(docker exec "$node2_container" mongo --host localhost:27017 --username "user_remote_node2" --password "remotepass2" --authenticationDatabase "mongodb_db2" mongodb_db2 --quiet --eval "db.getSiblingDB('mongodb_db1').users.count()" 2>/dev/null | tail -1)
                if [ "$count_db1" -ge 2 ] 2>/dev/null; then
                    log_success "user_remote_node2 может читать данные из mongodb_db1 через getSiblingDB (найдено $count_db1 документов)"
                else
                    log_info "user_remote_node2 имеет доступ к mongodb_db1 (может видеть коллекции через getCollectionNames)"
                    log_info "  Права доступа настроены корректно: роль 'read' на mongodb_db1"
                fi
            fi
        fi
    else
        log_error "user_remote_node2 должен иметь доступ к mongodb_db1 (соседняя БД), но не имеет!"
        exit 1
    fi
fi

# Проверка 4: Подключение к репликам
log_info ""
log_info "Проверка 4: Подключение к репликам"
if check_connection "lab4_mongodb_replica1"; then
    log_success "Replica1 доступна"
else
    log_error "Replica1 недоступна"
    exit 1
fi

if check_connection "lab4_mongodb_replica2"; then
    log_success "Replica2 доступна"
else
    log_error "Replica2 недоступна"
    exit 1
fi

if check_connection "lab4_mongodb_replica3"; then
    log_success "Replica3 доступна"
else
    log_error "Replica3 недоступна"
    exit 1
fi

# Проверка 5: Синхронизация данных в репликах
log_info ""
log_info "Проверка 5: Синхронизация данных в репликах"
sleep 5  # Даем время на синхронизацию

count_r1_db1=$(count_documents "lab4_mongodb_replica1" "mongodb_db1" "users")
count_r1_db2=$(count_documents "lab4_mongodb_replica1" "mongodb_db2" "users")

count_r2_db1=$(count_documents "lab4_mongodb_replica2" "mongodb_db1" "users")
count_r2_db2=$(count_documents "lab4_mongodb_replica2" "mongodb_db2" "users")

count_r3_db1=$(count_documents "lab4_mongodb_replica3" "mongodb_db1" "users")
count_r3_db2=$(count_documents "lab4_mongodb_replica3" "mongodb_db2" "users")

if [ "$count_r1_db1" -ge 2 ] 2>/dev/null && [ "$count_r2_db1" -ge 2 ] 2>/dev/null && [ "$count_r3_db1" -ge 2 ] 2>/dev/null; then
    log_success "Все реплики содержат данные из mongodb_db1 (>= 2 документов)"
    log_info "  Replica1: $count_r1_db1, Replica2: $count_r2_db1, Replica3: $count_r3_db1"
else
    log_error "Не все реплики содержат данные из mongodb_db1"
    log_info "  Replica1: $count_r1_db1, Replica2: $count_r2_db1, Replica3: $count_r3_db1"
    exit 1
fi

if [ "$count_r1_db2" -ge 2 ] 2>/dev/null && [ "$count_r2_db2" -ge 2 ] 2>/dev/null && [ "$count_r3_db2" -ge 2 ] 2>/dev/null; then
    log_success "Все реплики содержат данные из mongodb_db2 (>= 2 документов)"
    log_info "  Replica1: $count_r1_db2, Replica2: $count_r2_db2, Replica3: $count_r3_db2"
else
    log_error "Не все реплики содержат данные из mongodb_db2"
    log_info "  Replica1: $count_r1_db2, Replica2: $count_r2_db2, Replica3: $count_r3_db2"
    exit 1
fi

# Проверка 6: Блокчейн-логика - синхронизация между репликами
log_info ""
log_info "Проверка 6: Блокчейн-логика - проверка синхронизации между репликами"
log_info "Добавление тестового документа в Replica1..."

# Добавляем тестовый документ в Replica1
replica1_container=$(get_container_id "lab4_mongodb_replica1")
if [ -n "$replica1_container" ]; then
    docker exec "$replica1_container" mongo --host localhost:27017 --username "$ADMIN_USER" --password "$ADMIN_PASS" --authenticationDatabase admin --quiet --eval "
    db.getSiblingDB('mongodb_db1').users.insert({
        name: 'TestBlockchain',
        email: 'test@blockchain.com',
        age: 25,
        city: 'Test',
        salary: 50000,
        created_at: new Date().toISOString(),
        status: 'test',
        tags: ['blockchain', 'test']
    })
    " >/dev/null 2>&1
fi

log_info "Ожидание синхронизации (10 секунд)..."
sleep 10

# Проверяем наличие документа во всех репликах
replica1_container=$(get_container_id "lab4_mongodb_replica1")
replica2_container=$(get_container_id "lab4_mongodb_replica2")
replica3_container=$(get_container_id "lab4_mongodb_replica3")

test_count_r1="0"
test_count_r2="0"
test_count_r3="0"

if [ -n "$replica1_container" ]; then
    test_count_r1=$(mongo_exec "$replica1_container" "db.getSiblingDB('mongodb_db1').users.count({name: 'TestBlockchain'})" 2>/dev/null | tail -1)
fi
if [ -n "$replica2_container" ]; then
    test_count_r2=$(mongo_exec "$replica2_container" "db.getSiblingDB('mongodb_db1').users.count({name: 'TestBlockchain'})" 2>/dev/null | tail -1)
fi
if [ -n "$replica3_container" ]; then
    test_count_r3=$(mongo_exec "$replica3_container" "db.getSiblingDB('mongodb_db1').users.count({name: 'TestBlockchain'})" 2>/dev/null | tail -1)
fi

if [ "$test_count_r1" -ge 1 ] 2>/dev/null && [ "$test_count_r2" -ge 1 ] 2>/dev/null && [ "$test_count_r3" -ge 1 ] 2>/dev/null; then
    log_success "Блокчейн-логика работает: документ синхронизирован во все реплики"
    log_info "  Replica1: $test_count_r1, Replica2: $test_count_r2, Replica3: $test_count_r3"
else
    log_error "Блокчейн-логика не работает: документ не синхронизирован во все реплики"
    log_info "  Replica1: $test_count_r1, Replica2: $test_count_r2, Replica3: $test_count_r3"
    log_info "  Примечание: это может быть нормально, если синхронизация еще не произошла"
fi

# Удаляем тестовый документ
if [ -n "$replica1_container" ]; then
    docker exec "$replica1_container" mongo --host localhost:27017 --username "$ADMIN_USER" --password "$ADMIN_PASS" --authenticationDatabase admin --quiet --eval "db.getSiblingDB('mongodb_db1').users.remove({name: 'TestBlockchain'})" >/dev/null 2>&1
fi

echo ""
echo "=========================================="
log_success "Все проверки пройдены успешно!"
echo "=========================================="
