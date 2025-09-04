import pymssql
from pathlib import Path
import os
import datetime

# Define base directory for output scripts
BASE_DIR = Path("..\\DBProjects\\\QueryPerDbPerInstance")
OUTPUT_DIR = BASE_DIR / "output_sql_scripts"
LOG_DIR = BASE_DIR / "logs"

# Ensure the directory exists
os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)

def write_log(fqdn, db, action_type, message):
    """Append log entries to the consolidated log file."""
    timestamp = datetime.datetime.now().strftime('%Y_%m_%d-%H_%M_%S')
    log_file = LOG_DIR / f"{fqdn}_{db}_{action_type}_{timestamp}.log"
    with open(log_file, "a") as log:
        log.write(f"{message}\n")

def manage_foreign_keys(instance, db):
    try:
        connection = pymssql.connect(
            server=instance['fqdn'],
            port=instance['port'],
            user=instance['user'],
            password=instance['password'],
            database=db
        )
        
        cursor = connection.cursor()
        # FK Query
        fk_query = """
        SELECT fk.name AS fk_name, t.name AS table_name, s.name AS sch_name, 
        c1.name AS parent_column,schema_name(t2.schema_id) AS referenced_table_schema, 
        object_name(fkc.referenced_object_id) AS referenced_table,c2.name AS referenced_column
        FROM sys.foreign_keys fk  
        INNER JOIN sys.tables t ON fk.parent_object_id=t.object_id
		INNER JOIN sys.schemas s on s.schema_id = t.schema_id
        INNER JOIN sys.foreign_key_columns fkc on fk.object_id=fkc.constraint_object_id
        INNER JOIN sys.tables t2 on t2.object_id=fkc.referenced_object_id 
        INNER JOIN sys.columns c1 on c1.object_id=fkc.parent_object_id and c1.column_id=fkc.parent_column_id 
        INNER JOIN sys.columns c2 on c2.object_id=fkc.referenced_object_id and c2.column_id=fkc.referenced_column_id 
        """
        cursor.execute(fk_query)
        results = cursor.fetchall()
       
        delete_fk_commands = []
        create_fk_commands = []

        for fk_name, table_name, sch_name, parent_column, referenced_table_schema, referenced_table, referenced_column in results:
            create_fk_commands.append(f'ALTER TABLE [{sch_name}].[{table_name}]  WITH CHECK ADD CONSTRAINT {fk_name} FOREIGN KEY([{parent_column}]) REFERENCES [{referenced_table_schema}].[{referenced_table}] ([{referenced_column}]);')
            delete_fk_commands.append(f"ALTER TABLE [{sch_name}].[{table_name}] DROP CONSTRAINT {fk_name};")

        # Execute FK deletions
        for command in delete_fk_commands:
            try:
                cursor.execute(command)
                connection.commit()
                #write_log({instance['fqdn']}, db, "FK", f"Executed: {command}")
            except Exception as e:
                write_log({instance['fqdn']}, db, "FK", f"Error executing {command}: {e}")
                continue  # Continue execution even if an error occurs
        
        connection.close()

        # Save FK creation commands to a SQL file
        if create_fk_commands:
            output_file = OUTPUT_DIR / f"{instance['fqdn']}_{instance['port']}_{db}_fk.sql"
            with open(output_file, "w") as f:
                f.write(f"USE [{db}];\n\n")  # Ensure the script starts with USE <database>
                f.write("\n".join(create_fk_commands))  # Write FK creation statements
            
            return [f"Foreign Key SQL file saved: {output_file}"]

        return ["No Foreign Keys found to process."]
    
    except Exception as e:
        return [f"Error managing FKs for database {db} on instance {instance['fqdn']}: {e}"]

def manage_triggers(instance, db):
    try:
        connection = pymssql.connect(
            server=instance['fqdn'],
            port=instance['port'],
            user=instance['user'],
            password=instance['password'],
            database=db
        )
        cursor = connection.cursor()
        trigger_query = """
         SELECT 
            tr.name AS tr_name,
            t.name AS table_name,
			s.name AS sc_name
        FROM sys.triggers tr
		INNER JOIN sys.tables t ON t.object_id = tr.parent_id
		INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
        WHERE is_disabled = 0
        """
        cursor.execute(trigger_query)
        results = cursor.fetchall()
        
        enable_trigger_commands = []
        disable_trigger_commands = []

        for tr_name, table_name, sc_name in results:
            enable_trigger_commands.append(f"ENABLE TRIGGER {tr_name} ON [{sc_name}].[{table_name}];")
            disable_trigger_commands.append(f"DISABLE TRIGGER {tr_name} ON [{sc_name}].[{table_name}];")

# Execute Trigger disable
        for command in disable_trigger_commands:
            try:
                cursor.execute(command)
               # write_log(instance['fqdn'], db, "TR", f"Executed: {command}")
            except Exception as e:
                write_log(instance['fqdn'], db, "TR", f"Error executing {command}: {e}")
                continue  # Continue execution even if an error occurs
        connection.commit()
        connection.close()

        # Save TR ensble commands to a SQL file
        if enable_trigger_commands:
            output_file = OUTPUT_DIR / f"{instance['fqdn']}_{instance['port']}_{db}_tr.sql"
            with open(output_file, "w") as f:
                f.write(f"USE [{db}];\n\n")  # Ensure the script starts with USE <database>
                f.write("\n".join(enable_trigger_commands))  # Write TR enable statements
            
            return [f"Triggers SQL file saved: {output_file}"]

        return ["No trigges found to process."]
        
    except Exception as e:
        return [f"Error managing triggers for database {db} on instance {instance['fqdn']}: {e}"]

def manage_clones(instance,db):
    try:
        connection = pymssql.connect(
            server=instance['fqdn'],
            port=instance['port'],
            user=instance['user'],
            password=instance['password'],
            database=db
        )

        connection.autocommit(True)
                               
        try:
            cursor = connection.cursor()

            clone_db=f"{db}_Clone"
            # Clone Databases 
            command= f"DBCC CLonedatabase('{db}','{clone_db}');"
            cursor.execute(command)
            print(f"Database cloned successfully: {clone_db}")           

            # Alter Clone Databases to RW
            command=f"ALTER DATABASE {clone_db} SET READ_WRITE WITH rollback immediate;"
            cursor.execute(command)
            print(f"Database {clone_db} set to READ_WRITE mode")

        except Exception as e:
             write_log(instance['fqdn'], {db}, "CL-RW", f"Error executing {command}: {e}")
        
    except Exception as e:
        return [f"Error managing clones for the instance {instance['fqdn']}: {e}"]
    finally:
        cursor.close()
        connection.close()


def manage_backups(instance, db, bkp_path):
    try:
        # Connect to the database (needed for backup)
        connection = pymssql.connect(
            server=instance['fqdn'],
            port=instance['port'],
            user=instance['user'],
            password=instance['password'],
            database=db
        )
        connection.autocommit(True)
        cursor = connection.cursor()

        try:
            # Backup Database
            backup_file = f"{bkp_path}{db}_rb.bak"
            backup_command = f"""
                BACKUP DATABASE [{db}]
                TO DISK = N'{backup_file}'
                WITH COPY_ONLY, NOFORMAT, INIT, 
                NAME = N'{db} - Full Database Backup',
                SKIP, NOREWIND, NOUNLOAD, COMPRESSION, STATS = 10
            """
            #print(f"Executing: {backup_command}")
            cursor.execute(backup_command)
            print(f"Database Backup successfully created: {backup_file}")

        except Exception as e:
            write_log(instance['fqdn'], db, "Backup", f"Error executing backup: {e}")

        finally:
            cursor.close()
            connection.close()  # Close the connection before dropping

        # Drop the Clone database
        connection = pymssql.connect(
            server=instance['fqdn'],
            port=instance['port'],
            user=instance['user'],
            password=instance['password'],
            database="master"  
        )
        connection.autocommit(True)
        cursor = connection.cursor()

        try:
            # Force drop connections and drop the database
            drop_command = f"""
                ALTER DATABASE [{db}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
                DROP DATABASE [{db}];
            """
            #print(f"Executing: {drop_command}")
            cursor.execute(drop_command)
            print(f"Database {db} dropped successfully")
            return["Success"]

        except Exception as e:
            write_log(instance['fqdn'], db, "Drop", f"Error executing DROP DATABASE: {e}")
            return["Failed"]

        finally:
            cursor.close()
            connection.close()

    except Exception as e:
        return [f"Error managing backups for instance {instance['fqdn']}: {e}"]


def manage_restores(instance, db, bkp_path):
    cursor = None
    backup_file = f"{bkp_path}{db}_Clone_rb.bak"
    try:
        # connect to target instance
        connection = pymssql.connect(
            server=instance['fqdn'],
            port=instance['port'],
            user=instance['user'],
            password=instance['password'],
            database="master"
        )
        connection.autocommit(True)
        cursor = connection.cursor()

        # Check if the database exists
        cursor.execute(f"SELECT name FROM sys.databases WHERE name = '{db}'")
        db_exists = cursor.fetchone() is not None

        # Get default MDF & LDF file locations from target instance
        cursor.execute(f"""
            SELECT type_desc, physical_name 
            FROM sys.master_files 
            WHERE database_id = DB_ID('{db}')
        """)
        file_locations = {row[0]: row[1] for row in cursor.fetchall()}

        # If database doesn't exist, get the default data/log locations from master
        if not file_locations:
            cursor.execute("SELECT SERVERPROPERTY('InstanceDefaultDataPath'), SERVERPROPERTY('InstanceDefaultLogPath')")
            default_data_path, default_log_path = cursor.fetchone()
            file_locations = {
                "ROWS": f"{default_data_path}{db}.mdf",
                "LOG": f"{default_log_path}{db}_log.ldf"
            }

        # Extract logical file names from the backup
        cursor.execute(f"RESTORE FILELISTONLY FROM DISK = N'{backup_file}'")
        backup_files = cursor.fetchall()

        # Build MOVE statements dynamically
        move_statements = []
        for file in backup_files:
            logical_name, file_type = file[0], file[2]
            new_path = file_locations.get("ROWS" if file_type == "D" else "LOG")
            if isinstance(new_path, bytes):
                new_path = new_path.decode('utf-8')  # Decode byte strings if necessary
            new_path = new_path.replace("b'", "")  # Escape single quotes correctly
            new_path = new_path.replace("\\'", "\\")  # Remove ' fom the file names
            new_path = new_path.replace("\\\\", "\\")  # Ensure backslashes are single
            move_statements.append(f"MOVE N'{logical_name}' TO N'{new_path}'")
           

            '''
            if new_path:
                new_path = new_path.replace("'", "''")  # Escape single quotes for SQL
                move_statements.append(f"MOVE N'{logical_name}' TO N'{new_path}'")
            '''
        # Generate the RESTORE DATABASE command
        restore_command = f"""
            RESTORE DATABASE [{db}]
            FROM DISK = N'{backup_file}'
            WITH {", ".join(move_statements)}, REPLACE, RECOVERY, STATS = 10;
        """

        # If database exists, set it to SINGLE_USER mode before restore
        if db_exists:
            cursor.execute(f"ALTER DATABASE [{db}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE")

        print(f"Executing: {restore_command}")
        cursor.execute(restore_command)

        print(f"Database {db} restored successfully!")

    except Exception as e:
        print(f"Error restoring database {db}: {e}")

    finally:
        cursor.close()
        connection.close()


def manage_indexes(instance, db):
    try:
        connection = pymssql.connect(
            server=instance['fqdn'],
            port=instance['port'],
            user=instance['user'],
            password=instance['password'],
            database=db
        )
        cursor = connection.cursor()
        index_query = """
		SELECT 
            i.name AS index_name,
            t.name AS table_name,
			s.name AS sc_name
        FROM sys.indexes i
		INNER JOIN sys.tables t ON t.object_id = i.object_id
		INNER JOIN sys.schemas s on s.schema_id = t.schema_id
        WHERE i.name  is not null 
			and i.is_primary_key = 0 
			AND i.is_unique_constraint = 0
        """
        cursor.execute(index_query)
        results = cursor.fetchall()

        drop_index_commands = []

        for index_name, table_name, sc_name in results:
            drop_index_commands.append(f"DROP INDEX {index_name} ON {sc_name}.{table_name};")

        for command in drop_index_commands:
            cursor.execute(command)

        connection.commit()
        connection.close()
        return [f"Indexes dropped with success"]
    except Exception as e:
        return [f"Error managing indexes for database {db} on instance {instance['fqdn']}: {e}"]
