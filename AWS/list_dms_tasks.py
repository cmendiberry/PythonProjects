from aws_connect.aws_credentials import get_aws_client
import os 
os.system('color')
# Get AWS DMS client
client = get_aws_client("dms")

# Define the search string
SEARCH_STRING = input("Enter the search string for task names: ")

# Change pinted color
def prGreen(skk): print("\033[92m {}\033[00m" .format(skk))
def prRed(skk): print("\033[91m {}\033[00m" .format(skk))

def list_matching_dms_tasks(search_string):
    """List AWS DMS tasks that contain the given search string in their name."""
    response = client.describe_replication_tasks()
    
    tasks_to_list = [
        (task["ReplicationTaskIdentifier"], task["ReplicationTaskArn"])
        for task in response.get("ReplicationTasks", [])
        if search_string in task["ReplicationTaskIdentifier"]
    ]
    print('\033[0m')

    if not tasks_to_list:
        prRed(f"No tasks found containing '{search_string}'")       
        return

    for task_name, task_arn in tasks_to_list:
        prGreen(f"Migration tasks found: {task_name} (ARN: {task_arn})")
    
    print('\033[0m')     

    print("\nList Complete.")

def main():
    # REtrieve Migration tasks
    list_matching_dms_tasks(SEARCH_STRING)

if __name__ == "__main__":
    main()
