#!/bin/bash

echo "=== Проверка работы репликации ==="
echo ""

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. Проверка статуса сервиса репликации
echo "1. Статус сервиса репликации:"
REPLICATION_STATUS=$(docker service ps lab3_postgres_replication_job --format "{{.CurrentState}}" | head -1)
if [[ "$REPLICATION_STATUS" == *"Running"* ]]; then
    echo -e "${GREEN}✓ Сервис репликации работает${NC}"
else
    echo -e "${RED}✗ Сервис репликации не работает: $REPLICATION_STATUS${NC}"
fi
echo ""

# 2. Последние логи репликации
echo "2. Последние логи репликации (последние 10 строк):"
docker service logs lab3_postgres_replication_job --tail 10 2>&1 | grep -E "(Dumping|Restoring|Replication|ERROR|Starting)" | tail -5
echo ""

# 3. Проверка таблиц в реплике
echo "3. Таблицы в репликационной БД:"
REPLICA_CONTAINER=$(docker ps --filter name=lab3_postgres_replica --format "{{.Names}}" | head -1)
if [ -n "$REPLICA_CONTAINER" ]; then
    docker exec $REPLICA_CONTAINER psql -U replica -d replicadb -c "\dt" 2>&1 | grep -v "List of relations" | grep -v "Schema" | grep -v "^---" | grep -v "^$"
    echo ""
    
    # 4. Количество записей в таблицах
    echo "4. Количество записей в таблицах реплики:"
    docker exec $REPLICA_CONTAINER psql -U replica -d replicadb -c "
        SELECT 'customers' as table_name, COUNT(*) as count FROM customers 
        UNION ALL 
        SELECT 'orders', COUNT(*) FROM orders 
        UNION ALL 
        SELECT 'products', COUNT(*) FROM products 
        UNION ALL 
        SELECT 'sales', COUNT(*) FROM sales;
    " 2>&1 | grep -v "table_name" | grep -v "count" | grep -v "^---" | grep -v "^$"
    echo ""
    
    # 5. Сравнение данных в исходных БД и реплике
    echo "5. Сравнение данных (исходные БД vs реплика):"
    echo ""
    
    NODE1_CONTAINER=$(docker ps --filter name=lab3_postgres_node1 --format "{{.Names}}" | head -1)
    NODE2_CONTAINER=$(docker ps --filter name=lab3_postgres_node2 --format "{{.Names}}" | head -1)
    
    if [ -n "$NODE1_CONTAINER" ] && [ -n "$NODE2_CONTAINER" ]; then
        echo "sourcedb1.customers:"
        NODE1_COUNT=$(docker exec $NODE1_CONTAINER psql -U admin -d sourcedb1 -t -c "SELECT COUNT(*) FROM customers;" 2>&1 | tr -d ' ')
        REPLICA_CUSTOMERS=$(docker exec $REPLICA_CONTAINER psql -U replica -d replicadb -t -c "SELECT COUNT(*) FROM customers;" 2>&1 | tr -d ' ')
        echo "  Исходная БД: $NODE1_COUNT записей"
        echo "  Реплика:    $REPLICA_CUSTOMERS записей"
        if [ "$NODE1_COUNT" == "$REPLICA_CUSTOMERS" ]; then
            echo -e "  ${GREEN}✓ Количество совпадает${NC}"
        else
            echo -e "  ${YELLOW}⚠ Количество не совпадает (возможно, репликация еще не завершилась)${NC}"
        fi
        echo ""
        
        echo "sourcedb2.products:"
        NODE2_COUNT=$(docker exec $NODE2_CONTAINER psql -U admin -d sourcedb2 -t -c "SELECT COUNT(*) FROM products;" 2>&1 | tr -d ' ')
        REPLICA_PRODUCTS=$(docker exec $REPLICA_CONTAINER psql -U replica -d replicadb -t -c "SELECT COUNT(*) FROM products;" 2>&1 | tr -d ' ')
        echo "  Исходная БД: $NODE2_COUNT записей"
        echo "  Реплика:    $REPLICA_PRODUCTS записей"
        if [ "$NODE2_COUNT" == "$REPLICA_PRODUCTS" ]; then
            echo -e "  ${GREEN}✓ Количество совпадает${NC}"
        else
            echo -e "  ${YELLOW}⚠ Количество не совпадает (возможно, репликация еще не завершилась)${NC}"
        fi
        echo ""
    fi
    
    # 6. Тест репликации в реальном времени
    echo "6. Тест репликации в реальном времени:"
    echo "   Добавляю тестовую запись в sourcedb1..."
    TEST_NAME="replication_test_$(date +%s)"
    NODE1_CONTAINER=$(docker ps --filter name=lab3_postgres_node1 --format "{{.Names}}" | head -1)
    docker exec $NODE1_CONTAINER psql -U admin -d sourcedb1 -c "INSERT INTO customers(name) VALUES ('$TEST_NAME') RETURNING id, name;" > /dev/null 2>&1
    echo "   Запись добавлена. Ожидание репликации (35 секунд)..."
    sleep 35
    REPLICA_RESULT=$(docker exec $REPLICA_CONTAINER psql -U replica -d replicadb -t -c "SELECT COUNT(*) FROM customers WHERE name = '$TEST_NAME';" 2>&1 | tr -d ' ')
    if [ "$REPLICA_RESULT" == "1" ]; then
        echo -e "   ${GREEN}✓ Репликация работает! Запись найдена в реплике${NC}"
    else
        echo -e "   ${RED}✗ Репликация не работает или еще не завершилась${NC}"
    fi
    echo ""
else
    echo -e "${RED}✗ Контейнер реплики не найден${NC}"
fi

echo "=== Проверка завершена ==="

