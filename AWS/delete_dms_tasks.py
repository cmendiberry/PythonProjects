from aws_connect.aws_credentials import get_aws_client

# Get AWS DMS client
client = get_aws_client("dms")

# Define the search string
SEARCH_STRING = input("Enter the search string for task names: ")

def delete_matching_dms_tasks(search_string):
    """Delete AWS DMS tasks that contain the given search string in their name."""
    response = client.describe_replication_tasks()
    
    tasks_to_delete = [
        (task["ReplicationTaskIdentifier"], task["ReplicationTaskArn"])
        for task in response.get("ReplicationTasks", [])
        if search_string in task["ReplicationTaskIdentifier"]
    ]

    if not tasks_to_delete:
        print(f"No tasks found containing '{search_string}'.")
        return

    for task_name, task_arn in tasks_to_delete:
        print(f"Deleting replication task: {task_name} (ARN: {task_arn})")
        client.delete_replication_task(ReplicationTaskArn=task_arn)

    print("Deletion completed.")

def main():
    # Execute deletion
    delete_matching_dms_tasks(SEARCH_STRING)

if __name__ == "__main__":
    main()
