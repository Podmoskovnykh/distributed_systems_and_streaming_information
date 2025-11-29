#!/usr/bin/env python3
"""
Скрипт инициализации MongoDB:
- Создает базы данных в двух контейнерах
- Создает пользователей с разными правами доступа
- Создает документы со случайными данными
"""

import pymongo
import random
import string
import time
from datetime import datetime

def generate_random_string(length=10):
    """Генерирует случайную строку"""
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_random_document():
    """Генерирует случайный документ"""
    return {
        "name": generate_random_string(8),
        "email": f"{generate_random_string(6)}@example.com",
        "age": random.randint(18, 80),
        "city": random.choice(["Moscow", "Saint Petersburg", "Novosibirsk", "Yekaterinburg", "Kazan"]),
        "salary": random.randint(30000, 200000),
        "created_at": datetime.now().isoformat(),
        "status": random.choice(["active", "inactive", "pending"]),
        "tags": [generate_random_string(5) for _ in range(random.randint(1, 5))]
    }

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

def setup_mongodb_node(host, port, admin_user, admin_pass, db_name, local_user, local_pass, remote_user, remote_pass, can_access_remote=False, remote_host=None, remote_port=None):
    """Настраивает MongoDB узел"""
    print(f"\n=== Настройка MongoDB {host}:{port} ===")
    
    # Подключение как администратор
    client = pymongo.MongoClient(
        host=host,
        port=port,
        username=admin_user,
        password=admin_pass,
        authSource='admin'
    )
    
    db = client[db_name]
    
    # Создание коллекции и документов
    collection = db['users']
    
    # Удаляем старые данные
    collection.delete_many({})
    
    # Создаем два документа со случайными данными
    print(f"Создание документов в базе {db_name}...")
    doc1 = generate_random_document()
    doc2 = generate_random_document()
    
    result1 = collection.insert_one(doc1)
    result2 = collection.insert_one(doc2)
    
    print(f"✓ Созданы документы: {result1.inserted_id}, {result2.inserted_id}")
    
    # Создание пользователей
    print(f"Создание пользователей...")
    
    # Локальный пользователь (только своя БД)
    try:
        db.command(
            "createUser",
            local_user,
            pwd=local_pass,
            roles=[{"role": "readWrite", "db": db_name}]
        )
        print(f"✓ Создан пользователь {local_user} (доступ только к {db_name})")
    except Exception as e:
        if "already exists" not in str(e):
            print(f"⚠ Ошибка создания пользователя {local_user}: {e}")
        else:
            # Обновляем пароль если пользователь уже существует
            try:
                db.command("updateUser", local_user, pwd=local_pass)
            except:
                pass
    
    # Удаленный пользователь
    remote_db_name = "mongodb_db2" if db_name == "mongodb_db1" else "mongodb_db1"
    roles = [{"role": "readWrite", "db": db_name}]
    
    if can_access_remote:
        roles.append({"role": "read", "db": remote_db_name})
        print(f"✓ Создан пользователь {remote_user} (доступ к {db_name} и {remote_db_name})")
    else:
        print(f"✓ Создан пользователь {remote_user} (доступ только к {db_name})")
    
    try:
        db.command(
            "createUser",
            remote_user,
            pwd=remote_pass,
            roles=roles
        )
    except Exception as e:
        if "already exists" not in str(e):
            print(f"⚠ Ошибка создания пользователя {remote_user}: {e}")
        else:
            # Обновляем пароль и роли если пользователь уже существует
            try:
                db.command("updateUser", remote_user, pwd=remote_pass, roles=roles)
            except:
                pass
    
    # Если пользователь должен иметь доступ к соседней БД, создаем его там тоже
    if can_access_remote and remote_host and remote_port:
        try:
            remote_client = pymongo.MongoClient(
                host=remote_host,
                port=remote_port,
                username=admin_user,
                password=admin_pass,
                authSource='admin'
            )
            remote_db = remote_client[remote_db_name]
            try:
                remote_db.command(
                    "createUser",
                    remote_user,
                    pwd=remote_pass,
                    roles=[{"role": "read", "db": remote_db_name}]
                )
                print(f"✓ Создан пользователь {remote_user} в соседней БД {remote_db_name}")
            except Exception as e:
                if "already exists" not in str(e):
                    print(f"⚠ Ошибка создания пользователя {remote_user} в соседней БД: {e}")
                else:
                    try:
                        remote_db.command("updateUser", remote_user, pwd=remote_pass, roles=[{"role": "read", "db": remote_db_name}])
                    except:
                        pass
            remote_client.close()
        except Exception as e:
            print(f"⚠ Не удалось создать пользователя в соседней БД: {e}")
    
    client.close()
    print(f"✓ Настройка {host}:{port} завершена\n")

def main():
    print("=" * 60)
    print("Инициализация MongoDB кластера")
    print("=" * 60)
    
    # Параметры подключения
    NODE1_HOST = "mongodb_node1"
    NODE1_PORT = 27017
    NODE2_HOST = "mongodb_node2"
    NODE2_PORT = 27017
    
    ADMIN_USER = "admin"
    ADMIN_PASS = "adminpass"
    
    # Ожидание готовности MongoDB
    print("\nОжидание готовности MongoDB контейнеров...")
    if not wait_for_mongodb(NODE1_HOST, NODE1_PORT):
        print("Ошибка: MongoDB node1 не готов")
        return 1
    
    if not wait_for_mongodb(NODE2_HOST, NODE2_PORT):
        print("Ошибка: MongoDB node2 не готов")
        return 1
    
    time.sleep(5)  # Дополнительная пауза для полной инициализации
    
    # Настройка первого узла
    setup_mongodb_node(
        host=NODE1_HOST,
        port=NODE1_PORT,
        admin_user=ADMIN_USER,
        admin_pass=ADMIN_PASS,
        db_name="mongodb_db1",
        local_user="user_local_node1",
        local_pass="localpass1",
        remote_user="user_remote_node1",
        remote_pass="remotepass1",
        can_access_remote=True,  # Этот пользователь может видеть соседнюю БД
        remote_host=NODE2_HOST,
        remote_port=NODE2_PORT
    )
    
    # Настройка второго узла
    setup_mongodb_node(
        host=NODE2_HOST,
        port=NODE2_PORT,
        admin_user=ADMIN_USER,
        admin_pass=ADMIN_PASS,
        db_name="mongodb_db2",
        local_user="user_local_node2",
        local_pass="localpass2",
        remote_user="user_remote_node2",
        remote_pass="remotepass2",
        can_access_remote=True,  # Этот пользователь может видеть соседнюю БД
        remote_host=NODE1_HOST,
        remote_port=NODE1_PORT
    )
    
    print("=" * 60)
    print("✓ Инициализация MongoDB завершена успешно")
    print("=" * 60)
    return 0

if __name__ == "__main__":
    exit(main())

