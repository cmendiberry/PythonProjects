from aws_connect.aws_credentials import get_aws_client

# Get AWS DMS client
client = get_aws_client("dms")

# Define the search string
SEARCH_STRING = input("Enter the search string for task names: ")
StartType = input("Enter the start type ('reload-target'|'resume-processing'|'start-replication'): ")

def run_matching_dms_tasks(search_string,starttype):
    """Exucute AWS DMS tasks that contain the given search string in their name."""
    response = client.describe_replication_tasks()
    
    tasks_to_execute = [
        (task["ReplicationTaskIdentifier"], task["ReplicationTaskArn"])
        for task in response.get("ReplicationTasks", [])
        if search_string in task["ReplicationTaskIdentifier"]
    ]

    if not tasks_to_execute:
        print(f"No tasks found containing '{search_string}'.")
        return

    for task_name, task_arn in tasks_to_execute:
        print(f"Running replication task: {task_name} (ARN: {task_arn})")
        client.start_replication_task(
            ReplicationTaskArn=task_arn,
            StartReplicationTaskType=starttype
            )

    print("Execution started.")

def main():
    # Execute deletion
    run_matching_dms_tasks(SEARCH_STRING,StartType)

if __name__ == "__main__":
    main()
