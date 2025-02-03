import sys
import pymssql
import datetime
from pathlib import Path
from sql_utils.db_utilities import manage_clones

# Define paths
BASE_DIR = Path("..\\DBProjects\\\QueryPerDbPerInstance")
UTILS_DIR = BASE_DIR / "sql_utils"
sys.path.append(str(UTILS_DIR))
CONFIG_SOURCE = BASE_DIR / "config" / "sourceddl.txt"
LOG_DIR = BASE_DIR / "logs"

# Ensure directory exists
def ensure_dir(directory):
    if not directory.exists():
        directory.mkdir(parents=True)

# Parse instances configuration
def parse_instances(CONFIG_Instances):
    instances = []
    with open(CONFIG_Instances, "r") as file:
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

def process_instance(instance):
            fqdn, port, user, password = instance.values()
            print(f"Processing instance: {fqdn}:{port}")

            databases = get_databases(instance)
            for db in databases:
                 print(f"Managing database: {db}")
                 # Manage Clones
                 cl_results = manage_clones(instance,db)
                 if cl_results:
                    clone_file = LOG_DIR / f"{fqdn}_Clone_{datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")}.log"
                    with open(clone_file, "w") as file:
                        file.write("\n".join(cl_results))
                        print(f"Clone scripts saved to: {clone_file}")

def main():
    # Ensure required directories exist
    ensure_dir(LOG_DIR)

    # Parse instances and process each one
    if CONFIG_SOURCE.exists():
        instances = parse_instances(CONFIG_SOURCE)
        for instance in instances:
            process_instance(instance)
    else:
        print(f"Configuration file not found: {CONFIG_SOURCE}")

if __name__ == "__main__":
    main()
