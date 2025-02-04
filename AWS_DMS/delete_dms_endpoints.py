from utils.aws_credentials import get_aws_client

# Get AWS DMS client
client = get_aws_client("dms")

# Define the search string
search_string = input("Enter the search string for endpoints names: ")
endpoint_type = input("Enter the endpoint type (s: source| t: taget | a: all): ")
ep_choices = {"s": "source", "t": "target", "a": "all"}

def delete_enpoint(search_string, endpoint_type):

    response = client.describe_endpoints()
    # Define the entpoint type to delete:
    endpoint_to_delete = [
            (endpoint["EndpointIdentifier"], endpoint["EndpointArn"], endpoint["EndpointType"])
            for endpoint in response.get("Endpoints", [])
            if search_string in endpoint["EndpointIdentifier"] and 
           (ep_choices[endpoint_type] == "all" or endpoint["EndpointType"].lower() == ep_choices[endpoint_type])
            ]
   
    if not endpoint_to_delete:
        print(f"No endpoint found containing '{search_string}'.")
        return
    
    # Confirm deletion
    confirm = input("\nAre you sure you want to delete these endpoints? (yes/no): ").strip().lower()
    if confirm != "yes":
        print("Deletion canceled.")
        return
    
    # Delete endpoints
    for ep_name, ep_arn, ep_type in endpoint_to_delete:
        print(f"Deleting endpoint: {ep_name} , type: {ep_type} (ARN: {ep_arn})")
        client.delete_endpoint(EndpointArn=ep_arn)

    print("Deletion completed.")

def main():
        # Execute deletion
        delete_enpoint(search_string, endpoint_type)

if __name__ == "__main__":
    main()
