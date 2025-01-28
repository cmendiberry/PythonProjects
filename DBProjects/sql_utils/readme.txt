Import the function required
add the following code to the python script
from utils.db_utilities import manage_foreign_keys, manage_triggers, manage_indexes

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

    # Manage indexes (no PK)
    index_scripts = manage_indexes(instance, db)
    print(f"Index Scripts: {index_scripts}")

if __name__ == "__main__":
    main()
