import json
import os
import hashlib
from utils.aws_credentials import get_aws_client

def extract_babelfish_info():
    # Get AWS client
    rds_client = get_aws_client("rds")

    # Ask for the cluster ARN
    cluster_arn = input("Enter the Babelfish Aurora cluster ARN: ")

    # Fetch all clusters and print the response to debug
    try:
        clusters = rds_client.describe_db_clusters()['DBClusters']
        print("Clusters fetched successfully:", clusters)
    except Exception as e:
        print(f"Error fetching DB clusters: {e}")
        return

    # Find the cluster that matches the ARN
    cluster = next((c for c in clusters if c['DBClusterArn'] == cluster_arn), None)

    if not cluster:
        print("No matching DB Cluster found for the provided ARN.")
        return

    print(f"Cluster found: {cluster}")

    # Fetch instances associated with this cluster
    try:
        instances = rds_client.describe_db_instances()['DBInstances']
        print("Instances fetched successfully:", instances)
    except Exception as e:
        print(f"Error fetching DB instances: {e}")
        return

    cluster_instances = [i for i in instances if 'DBClusterIdentifier' in i and i['DBClusterIdentifier'] == cluster['DBClusterIdentifier']]

    # Print instance information for debugging
    print(f"Cluster Instances: {cluster_instances}")

    # Extract Security Groups (Use get() to avoid KeyError if key is missing)
    security_groups = [sg['VpcSecurityGroupId'] for sg in cluster.get('VpcSecurityGroups', [])]
    print(f"Security Groups: {security_groups}")

    # Safely access the DBClusterParameterGroups with get() to avoid KeyError
    parameter_groups = [pg['DBParameterGroupName'] for pg in cluster.get('DBClusterParameterGroups', [])]
    print(f"Parameter Groups: {parameter_groups}")

    # Prepare data
    data = {
        "DBClusterARN": cluster['DBClusterArn'],
        "DBClusterIdentifier": cluster['DBClusterIdentifier'],
        "Engine": cluster['Engine'],
        "EngineVersion": cluster['EngineVersion'],
        "MasterUsername": cluster['MasterUsername'],
        "DBSubnetGroup": cluster['DBSubnetGroup'],
        "VpcSecurityGroups": security_groups,
        "DBClusterParameterGroups": parameter_groups,
        "Instances": [
            {
                "DBInstanceIdentifier": i['DBInstanceIdentifier'],
                "DBInstanceClass": i['DBInstanceClass'],
                "AvailabilityZone": i['AvailabilityZone']
            } for i in cluster_instances
        ]
    }

    # Generate hash for filename
    arn_hash = hashlib.md5(cluster_arn.encode()).hexdigest()

    # Ensure Clusters folder exists
    clusters_folder = os.path.join(os.path.dirname(__file__), "Clusters")
    os.makedirs(clusters_folder, exist_ok=True)

    # Save to JSON file
    output_file = os.path.join(clusters_folder, f"babelfish_config_{arn_hash}.json")
    try:
        with open(output_file, "w") as f:
            json.dump(data, f, indent=4)
        print(f"Configuration saved to {output_file}")
    except Exception as e:
        print(f"Error saving configuration: {e}")

# Run the function
if __name__ == "__main__":
    extract_babelfish_info()
