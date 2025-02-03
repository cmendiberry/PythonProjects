Import the function required
Add the following code to the python script
from utils.db_utilities import manage_foreign_keys, manage_triggers

    def main():
            # Example
        instance = {
            "fqdn": "your_instance",
            "port": 1433,
            "user": "your_user",
            "password": "your_password"
        }
        db = "your_database"

        # Manage FKs
        fk_scripts = manage_foreign_keys(instance, db)
        print(f"FK Scripts: {fk_scripts}")

        # Manage triggers
        trigger_scripts = manage_triggers(instance, db)
        print(f"Trigger Scripts: {trigger_scripts}")

        # Manage Clones
        cl_results = manage_clones(instance,db)
        print(f"Clone scripts saved to: {clone_file}")

        # Manage Backups
        bkp_results = manage_backups(instance,db,bkp_path)
        print(bkp_results)

        # Manage Restores
        restore_results = manage_restores(target_instance,dbrestore,bkp_path)
        print(restore_results)

        # Manage indexes (no PK)
        index_scripts = manage_indexes(instance, db)
        print(f"Index Scripts: {index_scripts}")

    if __name__ == "__main__":
    main()
