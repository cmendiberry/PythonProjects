import pymssql
from pathlib import Path
import os
import datetime

# Define base directories
BASE_DIR = Path("..\\DBProjects\\QueryPerDbPerInstance")
OUTPUT_DIR = BASE_DIR / "output_sql_scripts"
LOG_DIR = BASE_DIR / "logs"
CONFIG_FILE = BASE_DIR / "config" / "instances.txt"

# Ensure directories exist
os.makedirs(LOG_DIR, exist_ok=True)

def write_log(file_name, message, success=True):
    """ Write logs for executed SQL scripts. """
    status = "succeed" if success else "error"
    log_file = LOG_DIR / f"Output_{file_name}_{status}.log"
    with open(log_file, "a") as log:
        log.write(f"{datetime.datetime.now()} - {message}\n")

def parse_instances(config_file):
    """ Parse instances.txt to get connection details. """
    instances = []
    with open(config_file, "r") as file:
        for line in file:
            parts = line.strip().split(",")
            if len(parts) >= 4:
                fqdn, port, user, password = parts[:4]  # Use first 4 columns
                instances.append({
                    "fqdn": fqdn.strip(),
                    "port": int(port.strip()),
                    "user": user.strip(),
                    "password": password.strip()
                })
    return instances

def execute_sql_file(instance, sql_file):
    """ Connect to the database and execute a SQL script. """
    file_name = sql_file.stem  # Extracts filename without extension
    db_name = file_name.split("_")[2]  # Extracts database name from filename

    try:
        connection = pymssql.connect(
            server=instance['fqdn'],
            port=instance['port'],
            user=instance['user'],
            password=instance['password'],
            database="master"
        )
        cursor = connection.cursor()

        with open(sql_file, "r") as f:
            sql_commands = f.read().split(";")  # Splitting SQL statements by `;`
        
        for command in sql_commands:
            if command.strip():
                try:
                    cursor.execute(command)
                    connection.commit()
                    #write_log(file_name, f"Executed: {command.strip()}", success=True)
                except Exception as e:
                    write_log(file_name, f"Error executing {command.strip()}: {e}", success=False)
                    continue  # Continue to next command even if one fails

        connection.close()
        write_log(file_name, f"Execution completed successfully.", success=True)

    except Exception as e:
        write_log(file_name, f"Critical error connecting to {db_name} on {instance['fqdn']}: {e}", success=False)

def main():
    """ Main execution flow: Read instance details, find SQL scripts, and execute them. """
    instances = parse_instances(CONFIG_FILE)
    
    if not instances:
        print("No valid instances found in configuration file.")
        return
    
    for sql_file in OUTPUT_DIR.glob("*.sql"):  # Find all .sql files
        for instance in instances:
            execute_sql_file(instance, sql_file)

if __name__ == "__main__":
    main()
