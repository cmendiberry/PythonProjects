import json
import os
import hashlib
from utils.aws_credentials import get_aws_client

def extract_babelfish_info():
    # Get AWS client
    rds_client = get_aws_client("rds")

    # Ask for the cluster ARN
    cluster_arn = input("Enter the Babelfish Aurora cluster ARN: ")

    # Get Cluster Info using ARN
    clusters = rds_client.describe_db_clusters(DBClusterIdentifier=cluster_arn)['DBClusters']
    if not clusters:
        print("No cluster found.")
        return
    cluster = clusters[0]

    # Get Instances associated with this cluster
    instances = rds_client.describe_db_instances()['DBInstances']
    cluster_instances = [i for i in instances if i['DBClusterIdentifier'] == cluster['DBClusterIdentifier']]

    # Extract Security Groups & Parameter Groups
    security_groups = [sg['VpcSecurityGroupId'] for sg in cluster['VpcSecurityGroups']]
    parameter_groups = [pg['DBParameterGroupName'] for pg in cluster['DBClusterParameterGroup']]

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
    with open(output_file, "w") as f:
        json.dump(data, f, indent=4)

    print(f"Configuration saved to {output_file}")

# Run the function
if __name__ == "__main__":
    extract_babelfish_info()
