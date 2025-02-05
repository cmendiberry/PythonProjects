import os
import pymssql
import subprocess
from pathlib import Path
from utils.colors import prRed,prCyan,prGreen

# Define paths
BASE_DIR = Path("..\\DMSAssessment")
CONFIG_FILE = BASE_DIR / "config" / "instances.txt"
assessment = BASE_DIR / "awsdms_support_collector_sql_server.sql" 

# Hardcoded databases to exclude
def get_databases(connection):
    exclude_dbs = {'master', 'tempdb', 'model', 'msdb', 'Admin','AdcQueryResearch','AqruQueryResearch','Bktb4_JobCoordinator_Db'}
    with connection.cursor() as cursor:
        cursor.execute("SELECT name FROM sys.databases")
        databases = [row[0] for row in cursor.fetchall() if row[0] not in exclude_dbs]
    return databases

#def process_instances(instances_file, folder):
def process_instances(instance, folder):
    fqdn, port, username, password = instance.strip().split(',') 
    try:
                connection = pymssql.connect(server=fqdn, user=username, password=password, port=port)
                databases = get_databases(connection)
                prGreen(f"Running DMS assessment for the instance: {fqdn}:{port}")
                for db in databases:
                    command=f"sqlcmd -U{username} -P{password} -S{fqdn},{port} -y 0 -i{assessment} -o{folder}\\DMS_{db}.html -d{db}"
                    process = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                                
                    print(f"Assessment finished for the database: {db}")                    
                    if process.stderr:
                        print(f"Error: {process.stderr}")
                        
                connection.close()
                prCyan(f"All reports saved in the folder: {folder}")
    except pymssql.OperationalError as e:
                print(f"Could not connect to {fqdn}:{port} - {e}")

def create_directories(root_folder, instances_file):
    try:
        with open(instances_file, 'r') as f:
            lines = f.readlines()
            
        for line in lines:            
            line = line.strip()
            if not line:
                continue

            parts = line.split(',')
            if len(parts) < 2:
                print(f"Skipping invalid line: {line}")
                continue

            fqdn = parts[0]
            port = parts[1]
            first_part_of_fqdn = fqdn.split('.')[0]

            # Create the main directory for the FQDN
            fqdn_directory = os.path.join(root_folder, 'DMSAssessments',first_part_of_fqdn)
            os.makedirs(fqdn_directory, exist_ok=True)
            
            # Create the nested directory for the port
            port_directory = os.path.join(fqdn_directory, port)
            os.makedirs(port_directory, exist_ok=True)
            
            print(f"Created directory: {port_directory}")
            process_instances(line, port_directory)
    
    except Exception as e:
        print(f"An error occurred: {e}")
import argparse

def main():
    # Define arguments
    parser = argparse.ArgumentParser(
        description=prRed(f"python dms_assessment.py <root folder> <path to find the instances info>"),
        formatter_class=argparse.RawTextHelpFormatter  # Ensures color formatting isn't altered
    )
    
    parser.add_argument("arg1", help="First mandatory argument")
    parser.add_argument("arg2", nargs="?", default=None, help="Second optional argument")
  
    args = parser.parse_args()

    # Check if the second argument was provided
    if args.arg2 is None:
        default_value = CONFIG_FILE
        response = input(f"The second argument was not provided. The default value '{default_value}' will be used. Do you want to proceed? (yes/no): ").strip().lower()

        if response != "yes":
            args.arg2 = input("Please enter the second argument: ").strip()
        else:
            args.arg2 = default_value

    print(f"Arg1: {args.arg1}")
    print(f"Arg2: {args.arg2}")
    create_directories(args.arg1, args.arg2)

if __name__ == "__main__":
    main()