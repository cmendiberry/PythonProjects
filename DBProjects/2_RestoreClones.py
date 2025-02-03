import sys
import pymssql
import datetime
import re
from pathlib import Path
from sql_utils.db_utilities import manage_backups, manage_restores

# Define paths
BASE_DIR = Path("..\\DBProjects\\\QueryPerDbPerInstance")
UTILS_DIR = BASE_DIR / "sql_utils"
sys.path.append(str(UTILS_DIR))
#OUTPUT_DIR = BASE_DIR / "output_sql_scripts"
CONFIG_SOURCE= BASE_DIR / "config" / "sourceddl.txt"
CONFIG_FILE = BASE_DIR / "config" / "instance.txt"
LOG_DIR = BASE_DIR / "logs"

# Ensure directory exists
def ensure_dir(directory):
    if not directory.exists():
        directory.mkdir(parents=True)

# Parse instance configuration
def parse_instances(config_file):
    instances = []
    with open(config_file, "r") as file:
        for line in file:
            fqdn, port, user, password = line.strip().split(",")
            instances.append({"fqdn": fqdn, "port": int(port), "user": user, "password": password})
    return instances

# Get databases in the instance excluding system databases
def get_databases(instance):
    
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
        cursor.execute("SELECT name FROM sys.databases WHERE name LIKE '%[_]Clone';") #where name in ('')
        databases = [row[0] for row in cursor.fetchall()]
        connection.close()
        return databases
    except Exception as e:
        print(f"Error retrieving databases for instance {instance['fqdn']}: {e}")
        return []

def process_instance(instance,bkp_path,target_instance):
            fqdn, port, user, password = instance.values()
            print(f"Processing instance: {fqdn}:{port}")

            databases = get_databases(instance)
            for db in databases:
                 print(f"Managing database: {db}")
                 # Manage Backups
                 bkp_results = manage_backups(instance,db,bkp_path)
                 print(bkp_results)
                 if bkp_results == ['Success']:
                      dbrestore = db
                      dbrestore=re.sub("_Clone","",dbrestore)
                      print(dbrestore)
                      # Manage Restores
                      restore_results = manage_restores(target_instance,dbrestore,bkp_path)
                      print(restore_results)
                  #  bkp_file = LOG_DIR / f"{fqdn}_Clone_{datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")}.log"
                    

def main(bkp_path):
    # Ensure required directories exist
    ensure_dir(LOG_DIR)

    # Parse instances and process each one
    if CONFIG_FILE.exists():
        instancesC = parse_instances(CONFIG_FILE)
        '''
        for instance in instancesC:
            process_instance(instance)
        '''
    else:
        print(f"Target configuration file not found: {CONFIG_FILE}")

    if CONFIG_SOURCE.exists():
        instancesA = parse_instances(CONFIG_SOURCE)
        for source in instancesA:
            for target in instancesC:
                 process_instance(source,bkp_path, target)
    else:
        print(f"Source configuration file not found: {CONFIG_SOURCE}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python drop_databases.py <path_to__save_the_backup_files\\>")
        sys.exit(1)

    bkp_path = sys.argv[1]
    main(bkp_path)
