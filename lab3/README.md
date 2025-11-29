## Развертывание через Docker Swarm

```bash
# Создать сети
docker network create cluster1-net cluster2-net standalone1-net standalone2-net standalone3-net

# Инициализировать Swarm (если нужно)
docker swarm init

# Развернуть stack
docker stack deploy -c docker-compose.yml lab3

# Проверить статус
docker stack services lab3
```

Инициализация БД происходит автоматически через контейнер `postgres_init`. При необходимости можно запустить вручную:

```bash
./init_db.sh
```

## Проверка репликации

```bash
./check_replication.sh
```

## Подключение к БД

- **postgres_node1**: `psql -h localhost -p 5432 -U admin -d sourcedb1` (пароль: `adminpass`)
- **postgres_node2**: `psql -h localhost -p 5433 -U admin -d sourcedb2` (пароль: `adminpass`)
- **postgres_replica**: `psql -h localhost -p 5434 -U replica -d replicadb` (пароль: `replicapass`)

## Пользователи

- `user_local_node1/node2` - доступ только к своей БД
- `user_remote_node1/node2` - доступ к своей БД и соседней БД

## Вывод о проделанной работе

✅ Развернут кластер с двумя PostgreSQL БД в Docker Swarm  
✅ Созданы таблицы со случайными данными (customers/orders в node1, products/sales в node2)  
✅ Настроены пользователи: LocalUser (только своя БД) и CrossUser (доступ к обеим БД)  
✅ Реализована автоматическая репликация каждые 30 секунд в отдельный контейнер  
