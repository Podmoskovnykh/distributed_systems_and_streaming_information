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

## MongoDB кластер

### Развертывание

Инициализация MongoDB происходит автоматически через контейнер `mongodb_init`. При необходимости можно запустить вручную:

```bash
./init_mongodb.sh
```

### Проверка MongoDB

```bash
./check_mongodb.sh
```

### Подключение к MongoDB

- **mongodb_node1**: `mongosh --host localhost:27017 --username admin --password adminpass --authenticationDatabase admin`
- **mongodb_node2**: `mongosh --host localhost:27018 --username admin --password adminpass --authenticationDatabase admin`
- **mongodb_replica1**: `mongosh --host localhost:27019 --username admin --password adminpass --authenticationDatabase admin`
- **mongodb_replica2**: `mongosh --host localhost:27020 --username admin --password adminpass --authenticationDatabase admin`
- **mongodb_replica3**: `mongosh --host localhost:27021 --username admin --password adminpass --authenticationDatabase admin`

### MongoDB Пользователи

- `user_local_node1` / `localpass1` - доступ только к `mongodb_db1` (видит только свою БД)
- `user_remote_node1` / `remotepass1` - доступ к `mongodb_db1` и `mongodb_db2` (может видеть БД в соседнем контейнере)
- `user_local_node2` / `localpass2` - доступ только к `mongodb_db2` (видит только свою БД)
- `user_remote_node2` / `remotepass2` - доступ к `mongodb_db2` и `mongodb_db1` (может видеть БД в соседнем контейнере)

### Базы данных MongoDB

- **mongodb_db1** - база данных в node1, содержит коллекцию `users` с двумя документами
- **mongodb_db2** - база данных в node2, содержит коллекцию `users` с двумя документами

### Репликация MongoDB

Реализована репликация с блокчейн-логикой:
- При новых данных извне (из основных узлов) - данные обновляются во всех трех репликах одновременно
- При обновлении данных в одном из трех реплик - данные синхронизируются в остальных двух
- Синхронизация происходит автоматически каждые 10 секунд через скрипт `sync_mongodb_replication.py`

## Вывод о проделанной работе

### PostgreSQL кластер
✅ Развернут кластер с двумя PostgreSQL БД в Docker Swarm  
✅ Созданы таблицы со случайными данными (customers/orders в node1, products/sales в node2)  
✅ Настроены пользователи: LocalUser (только своя БД) и CrossUser (доступ к обеим БД)  
✅ Реализована автоматическая репликация каждые 30 секунд в отдельный контейнер  

### MongoDB кластер
✅ Развернут кластер с двумя MongoDB БД в Docker Swarm (cluster2-net)  
✅ Созданы базы данных со случайными документами (mongodb_db1 и mongodb_db2)  
✅ Настроены пользователи: LocalUser (только своя БД) и RemoteUser (доступ к соседней БД)  
✅ Реализована репликация с блокчейн-логикой в 3 отдельных контейнера (standalone сети)  
✅ Синхронизация данных из основных узлов в реплики и между репликами работает автоматически  
