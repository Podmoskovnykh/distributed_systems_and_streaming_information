import os
import psycopg2
from psycopg2 import sql
from jinja2 import Environment, FileSystemLoader
from dotenv import dotenv_values
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s [%(levelname)s] %(message)s')

def load_env(env_path):
    if not os.path.exists(env_path):
        raise FileNotFoundError(f"Env-файл {env_path} не найден")
    return dotenv_values(env_path)

def build_dsn(env):
    host = env.get("DB_HOST", "localhost")
    port = env.get("DB_PORT", "5432")
    dbname = env.get("POSTGRES_DB")
    user = env.get("POSTGRES_USER")
    password = env.get("POSTGRES_PASSWORD")

    if not all([dbname, user, password]):
        raise ValueError("В env-файле должны быть POSTGRES_DB, POSTGRES_USER и POSTGRES_PASSWORD")

    return f"postgresql://{user}:{password}@{host}:{port}/{dbname}"

def apply_template_sql(dsn, template_file, template_data):
    env = Environment(loader=FileSystemLoader("sql"))
    template = env.get_template(template_file)
    rendered_sql = template.render(template_data)

    logging.info(f"Подключение к БД: {dsn}")
    conn = psycopg2.connect(dsn)
    conn.autocommit = True
    try:
        with conn.cursor() as cur:
            cur.execute(rendered_sql)
        logging.info(f"SQL из шаблона {template_file} выполнен успешно!")
    finally:
        conn.close()

def main():
    first_env_path = "pg_first.env"
    second_env_path = "pg_second.env"

    first_env = load_env(first_env_path)
    second_env = load_env(second_env_path)

    first_dsn = build_dsn(first_env)
    second_dsn = build_dsn(second_env)

    first_template_data = {
        "LocalUser": first_env.get("LOCAL_USER"),
        "LocalPass": first_env.get("LOCAL_PASS"),
        "CrossUser": first_env.get("CROSS_USER"),
        "CrossPass": first_env.get("CROSS_PASS"),
        "DbName": first_env.get("POSTGRES_DB")
    }

    second_template_data = {
        "LocalUser": second_env.get("LOCAL_USER"),
        "LocalPass": second_env.get("LOCAL_PASS"),
        "CrossUser": second_env.get("CROSS_USER"),
        "CrossPass": second_env.get("CROSS_PASS"),
        "DbName": second_env.get("POSTGRES_DB")
    }

    logging.info("=== Настройка postgres_node1 ===")
    apply_template_sql(first_dsn, "postgres_node1.sql.tmpl", first_template_data)
    
    first_cross_access_data = {
        "RemoteCrossUser": second_env.get("CROSS_USER"),
        "RemoteCrossPass": second_env.get("CROSS_PASS"),
        "DbName": first_env.get("POSTGRES_DB")
    }
    apply_template_sql(first_dsn, "postgres_node1_cross_access.sql.tmpl", first_cross_access_data)

    logging.info("=== Настройка postgres_node2 ===")
    apply_template_sql(second_dsn, "postgres_node2.sql.tmpl", second_template_data)
    
    second_cross_access_data = {
        "RemoteCrossUser": first_env.get("CROSS_USER"),
        "RemoteCrossPass": first_env.get("CROSS_PASS"),
        "DbName": second_env.get("POSTGRES_DB")
    }
    apply_template_sql(second_dsn, "postgres_node2_cross_access.sql.tmpl", second_cross_access_data)

if __name__ == "__main__":
    main()
