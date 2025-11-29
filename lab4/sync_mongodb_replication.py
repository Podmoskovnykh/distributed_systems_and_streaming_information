#!/usr/bin/env python3
"""
Скрипт синхронизации MongoDB с блокчейн-логикой:
- При новых данных извне - обновляются во всех трех репликах одновременно
- При обновлении в одном из трех реплик - обновляются в остальных двух
- Синхронизирует данные из основных узлов в реплики
"""

import pymongo
import time
from datetime import datetime
from bson import ObjectId

def get_all_documents(client, db_name, collection_name):
    """Получает все документы из коллекции"""
    try:
        db = client[db_name]
        collection = db[collection_name]
        return list(collection.find({}))
    except Exception as e:
        print(f"⚠ Ошибка получения документов из {db_name}.{collection_name}: {e}")
        return []

def sync_collection(source_client, target_clients, db_name, collection_name):
    """Синхронизирует коллекцию из источника во все целевые клиенты (объединяет данные)"""
    try:
        # Получаем все документы из источника
        source_docs = get_all_documents(source_client, db_name, collection_name)
        
        if not source_docs:
            return
        
        # Для каждого целевого клиента объединяем данные
        for target_client in target_clients:
            try:
                db = target_client[db_name]
                collection = db[collection_name]
                
                # Получаем существующие документы в реплике
                existing_docs = get_all_documents(target_client, db_name, collection_name)
                existing_ids = {str(doc.get('_id', '')) for doc in existing_docs}
                
                # Объединяем документы: добавляем новые из источника, сохраняем существующие в реплике
                all_docs = {}
                
                # Сначала добавляем существующие документы из реплики
                for doc in existing_docs:
                    doc_id = str(doc.get('_id', ''))
                    all_docs[doc_id] = doc
                
                # Затем добавляем/обновляем документы из источника
                for doc in source_docs:
                    doc_id = str(doc.get('_id', ''))
                    # Если документа нет в реплике, добавляем его
                    if doc_id not in existing_ids:
                        all_docs[doc_id] = doc
                    # Если есть, сравниваем по created_at и обновляем если источник новее
                    elif doc_id in all_docs:
                        source_time = doc.get('created_at', '')
                        existing_time = all_docs[doc_id].get('created_at', '')
                        if source_time and existing_time and source_time > existing_time:
                            all_docs[doc_id] = doc
                
                # Синхронизируем объединенные данные
                docs_list = list(all_docs.values())
                collection.delete_many({})
                if docs_list:
                    docs_to_insert = []
                    for doc in docs_list:
                        new_doc = doc.copy()
                        # MongoDB создаст новый ObjectId при вставке
                        if '_id' in new_doc:
                            del new_doc['_id']
                        docs_to_insert.append(new_doc)
                    if docs_to_insert:
                        collection.insert_many(docs_to_insert)
                    
            except Exception as e:
                print(f"⚠ Ошибка синхронизации в {db_name}.{collection_name}: {e}")
        
    except Exception as e:
        print(f"⚠ Ошибка синхронизации коллекции {db_name}.{collection_name}: {e}")

def get_doc_key(doc):
    """Получает уникальный ключ для документа (использует name+email или _id)"""
    name = doc.get('name', '')
    email = doc.get('email', '')
    if name and email:
        return f"{name}:{email}"
    return str(doc.get('_id', ''))

def sync_between_replicas(replica_clients, db_name, collection_name):
    """Синхронизирует данные между репликами (блокчейн-логика)"""
    try:
        # Получаем документы из всех реплик
        all_docs = {}
        replica_docs = {}
        doc_keys_sets = []
        
        for i, client in enumerate(replica_clients):
            docs = get_all_documents(client, db_name, collection_name)
            replica_docs[i] = docs
            doc_keys = set()
            
            # Собираем все документы по уникальному ключу
            for doc in docs:
                doc_key = get_doc_key(doc)
                doc_keys.add(doc_key)
                
                # Если документа еще нет или этот новее (по created_at)
                if doc_key not in all_docs:
                    all_docs[doc_key] = doc
                else:
                    # Сравниваем по created_at для определения более новой версии
                    existing_time = all_docs[doc_key].get('created_at', '')
                    new_time = doc.get('created_at', '')
                    if new_time and existing_time:
                        if new_time > existing_time:
                            all_docs[doc_key] = doc
                    elif new_time and not existing_time:
                        all_docs[doc_key] = doc
            
            doc_keys_sets.append(doc_keys)
        
        # Проверяем, есть ли различия между репликами
        needs_sync = False
        
        # Проверяем количество документов и их ключи
        if len(doc_keys_sets) > 0:
            first_set = doc_keys_sets[0]
            for doc_keys_set in doc_keys_sets[1:]:
                if doc_keys_set != first_set:
                    needs_sync = True
                    break
        
        # Если есть различия, синхронизируем все реплики с объединенной версией
        if needs_sync or len(all_docs) > 0:
            # Синхронизируем все реплики одновременно
            docs_list = list(all_docs.values())
            for client in replica_clients:
                try:
                    db = client[db_name]
                    collection = db[collection_name]
                    collection.delete_many({})
                    if docs_list:
                        docs_to_insert = []
                        for doc in docs_list:
                            new_doc = doc.copy()
                            # MongoDB создаст новый ObjectId при вставке
                            if '_id' in new_doc:
                                del new_doc['_id']
                            docs_to_insert.append(new_doc)
                        if docs_to_insert:
                            collection.insert_many(docs_to_insert)
                except Exception as e:
                    print(f"⚠ Ошибка синхронизации реплики: {e}")
            
    except Exception as e:
        print(f"⚠ Ошибка синхронизации между репликами: {e}")

def main():
    ADMIN_USER = "admin"
    ADMIN_PASS = "adminpass"
    
    # Основные узлы
    NODE1_HOST = "mongodb_node1"
    NODE1_PORT = 27017
    NODE2_HOST = "mongodb_node2"
    NODE2_PORT = 27017
    
    # Реплики
    REPLICA1_HOST = "mongodb_replica1"
    REPLICA1_PORT = 27017
    REPLICA2_HOST = "mongodb_replica2"
    REPLICA2_PORT = 27017
    REPLICA3_HOST = "mongodb_replica3"
    REPLICA3_PORT = 27017
    
    try:
        # Подключение к основным узлам
        node1_client = pymongo.MongoClient(
            host=NODE1_HOST,
            port=NODE1_PORT,
            username=ADMIN_USER,
            password=ADMIN_PASS,
            authSource='admin',
            serverSelectionTimeoutMS=5000
        )
        
        node2_client = pymongo.MongoClient(
            host=NODE2_HOST,
            port=NODE2_PORT,
            username=ADMIN_USER,
            password=ADMIN_PASS,
            authSource='admin',
            serverSelectionTimeoutMS=5000
        )
        
        # Подключение к репликам
        replica1_client = pymongo.MongoClient(
            host=REPLICA1_HOST,
            port=REPLICA1_PORT,
            username=ADMIN_USER,
            password=ADMIN_PASS,
            authSource='admin',
            serverSelectionTimeoutMS=5000
        )
        
        replica2_client = pymongo.MongoClient(
            host=REPLICA2_HOST,
            port=REPLICA2_PORT,
            username=ADMIN_USER,
            password=ADMIN_PASS,
            authSource='admin',
            serverSelectionTimeoutMS=5000
        )
        
        replica3_client = pymongo.MongoClient(
            host=REPLICA3_HOST,
            port=REPLICA3_PORT,
            username=ADMIN_USER,
            password=ADMIN_PASS,
            authSource='admin',
            serverSelectionTimeoutMS=5000
        )
        
        replica_clients = [replica1_client, replica2_client, replica3_client]
        
        # ВАЖНО: Сначала синхронизируем между репликами (блокчейн-логика)
        # Это сохраняет изменения, сделанные в репликах
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Синхронизация между репликами (блокчейн-логика)...")
        sync_between_replicas(replica_clients, "mongodb_db1", "users")
        sync_between_replicas(replica_clients, "mongodb_db2", "users")
        
        # Затем синхронизируем из основных узлов в реплики (данные извне)
        # Но только если в репликах нет новых данных
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Синхронизация данных из основных узлов в реплики...")
        
        # Синхронизация из node1
        sync_collection(node1_client, replica_clients, "mongodb_db1", "users")
        
        # Синхронизация из node2
        sync_collection(node2_client, replica_clients, "mongodb_db2", "users")
        
        # После синхронизации из основных узлов, снова синхронизируем между репликами
        # чтобы убедиться, что все реплики имеют одинаковые данные
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Финальная синхронизация между репликами...")
        sync_between_replicas(replica_clients, "mongodb_db1", "users")
        sync_between_replicas(replica_clients, "mongodb_db2", "users")
        
        # Закрываем соединения
        node1_client.close()
        node2_client.close()
        replica1_client.close()
        replica2_client.close()
        replica3_client.close()
        
    except Exception as e:
        print(f"⚠ Ошибка синхронизации: {e}")
        return 1
    
    return 0

if __name__ == "__main__":
    exit(main())

