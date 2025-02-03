import sys
import pymssql
import datetime
from pathlib import Path
from sql_utils.db_utilities import manage_foreign_keys, manage_triggers

# Define paths
BASE_DIR = Path("..\\DBProjects\\\QueryPerDbPerInstance")
UTILS_DIR = BASE_DIR / "sql_utils"
sys.path.append(str(UTILS_DIR))
OUTPUT_DIR = BASE_DIR / "output_sql_scripts"
CONFIG_FILE = BASE_DIR / "config" / "instance.txt"
LOG_DIR = BASE_DIR / "logs"

# Ensure directory exists
def ensure_dir(directory):
    if not directory.exists():
        directory.mkdir(parents=True)

# Parse instances configuration
def parse_instances(config_file):
    instances = []
    with open(config_file, "r") as file:
        for line in file:
            fqdn, port, user, password = line.strip().split(",")
            instances.append({"fqdn": fqdn, "port": int(port), "user": user, "password": password})
    return instances

# Get databases in the instance excluding system databases
def get_databases(instance):
    excluded_dbs = {"master", "msdb", "model", "tempdb"}
    try:
        # Connect to master database to retrieve all databases
        connection = pymssql.connect(
            server=instance['fqdn'],
            port=instance['port'],
            user=instance['user'],
            password=instance['password'],
            database="master"
        )
        cursor = connection.cursor()
        cursor.execute("SELECT name FROM sys.databases;") #where name in ('')
        databases = [row[0] for row in cursor.fetchall() if row[0] not in excluded_dbs]
        connection.close()
        return databases
    except Exception as e:
        print(f"Error retrieving databases for instance {instance['fqdn']}: {e}")
        return []

# Process databases for an instance
def process_instance(instance):
    fqdn, port, user, password = instance.values()
    print(f"Processing instance: {fqdn}:{port}")

    databases = get_databases(instance)

    for db in databases:
        print(f"Managing database: {db}")

        # Manage Foreign Keys
        fk_results = manage_foreign_keys(instance, db)
        if fk_results:
            fk_file = LOG_DIR / f"{fqdn}_{db}_FK_{datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")}.log"
            with open(fk_file, "w") as file:
                file.write("\n".join(fk_results))
            print(f"Foreign Key scripts saved to: {fk_file}")

        # Manage Triggers
        tr_results = manage_triggers(instance, db)
        if tr_results:
            trigger_file = LOG_DIR / f"{fqdn}_{db}_Trigger_{datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")}.log"
            with open(trigger_file, "w") as file:
                file.write("\n".join(tr_results))
            print(f"Trigger scripts saved to: {trigger_file}")

def main():
    # Ensure required directories exist
    ensure_dir(LOG_DIR)

    # Parse instances and process each one
    if CONFIG_FILE.exists():
        instances = parse_instances(CONFIG_FILE)
        for instance in instances:
            process_instance(instance)
    else:
        print(f"Configuration file not found: {CONFIG_FILE}")

if __name__ == "__main__":
    main()
