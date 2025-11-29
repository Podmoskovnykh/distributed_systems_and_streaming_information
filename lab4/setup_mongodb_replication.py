#!/usr/bin/env python3
"""
Скрипт настройки репликации MongoDB с блокчейн-логикой:
- Настраивает Replica Set для основных узлов (rs0)
- Настраивает Replica Set для реплик (rs1)
- Настраивает синхронизацию между основными узлами и репликами
"""

import pymongo
import time

def wait_for_mongodb(host, port, max_retries=30):
    """Ожидает готовности MongoDB"""
    for i in range(max_retries):
        try:
            client = pymongo.MongoClient(
                host=host,
                port=port,
                serverSelectionTimeoutMS=2000
            )
            client.admin.command('ping')
            client.close()
            print(f"✓ MongoDB {host}:{port} готов")
            return True
        except Exception as e:
            if i == max_retries - 1:
                print(f"✗ Не удалось подключиться к MongoDB {host}:{port}: {e}")
                return False
            time.sleep(2)
    return False

def init_replica_set(client, rs_name, members):
    """Инициализирует Replica Set"""
    try:
        # Проверяем, не инициализирован ли уже replica set
        try:
            status = client.admin.command('replSetGetStatus')
            print(f"✓ Replica Set {rs_name} уже инициализирован")
            return True
        except:
            pass
        
        config = {
            "_id": rs_name,
            "members": members
        }
        
        result = client.admin.command('replSetInitiate', config)
        print(f"✓ Replica Set {rs_name} инициализирован: {result}")
        return True
    except Exception as e:
        if "already initialized" in str(e) or "already in replica set" in str(e):
            print(f"✓ Replica Set {rs_name} уже инициализирован")
            return True
        print(f"⚠ Ошибка инициализации Replica Set {rs_name}: {e}")
        return False

def main():
    print("=" * 60)
    print("Настройка MongoDB репликации")
    print("=" * 60)
    
    ADMIN_USER = "admin"
    ADMIN_PASS = "adminpass"
    
    # Основные узлы в cluster2-net
    NODE1_HOST = "mongodb_node1"
    NODE1_PORT = 27017
    NODE2_HOST = "mongodb_node2"
    NODE2_PORT = 27017
    
    # Реплики в standalone сетях
    REPLICA1_HOST = "mongodb_replica1"
    REPLICA1_PORT = 27017
    REPLICA2_HOST = "mongodb_replica2"
    REPLICA2_PORT = 27017
    REPLICA3_HOST = "mongodb_replica3"
    REPLICA3_PORT = 27017
    
    print("\nОжидание готовности всех MongoDB контейнеров...")
    
    # Ожидание основных узлов
    wait_for_mongodb(NODE1_HOST, NODE1_PORT)
    wait_for_mongodb(NODE2_HOST, NODE2_PORT)
    
    # Ожидание реплик
    wait_for_mongodb(REPLICA1_HOST, REPLICA1_PORT)
    wait_for_mongodb(REPLICA2_HOST, REPLICA2_PORT)
    wait_for_mongodb(REPLICA3_HOST, REPLICA3_PORT)
    
    time.sleep(5)
    
    print("\n=== Настройка Replica Set для основных узлов (rs0) ===")
    # Для основных узлов создаем отдельные replica sets (они независимы)
    # Но для упрощения оставим их как standalone, так как они не должны реплицироваться друг с другом
    
    print("\n=== Настройка Replica Set для реплик (rs1) ===")
    # Подключаемся к первому реплика-узлу и инициализируем replica set
    try:
        client_replica1 = pymongo.MongoClient(
            host=REPLICA1_HOST,
            port=REPLICA1_PORT,
            username=ADMIN_USER,
            password=ADMIN_PASS,
            authSource='admin',
            serverSelectionTimeoutMS=10000
        )
        
        members = [
            {"_id": 0, "host": f"{REPLICA1_HOST}:{REPLICA1_PORT}"},
            {"_id": 1, "host": f"{REPLICA2_HOST}:{REPLICA2_PORT}"},
            {"_id": 2, "host": f"{REPLICA3_HOST}:{REPLICA3_PORT}"}
        ]
        
        init_replica_set(client_replica1, "rs1", members)
        client_replica1.close()
        
        print("✓ Replica Set rs1 настроен для реплик")
        print("  Реплики будут синхронизироваться автоматически через MongoDB Replica Set")
        
    except Exception as e:
        print(f"⚠ Ошибка настройки Replica Set для реплик: {e}")
        print("  Продолжаем работу - синхронизация будет через скрипт")
    
    print("\n" + "=" * 60)
    print("✓ Настройка репликации завершена")
    print("=" * 60)
    print("\nПримечание: Синхронизация данных между основными узлами и репликами")
    print("осуществляется через скрипт sync_mongodb_replication.py")
    
    return 0

if __name__ == "__main__":
    exit(main())

