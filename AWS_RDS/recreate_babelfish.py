import json
import os
from utils.aws_credentials import get_aws_client

def recreate_babelfish_cluster(json_file):
    # Get AWS client
    rds_client = get_aws_client("rds")
    
    # Read the configuration from the JSON file
    try:
        with open(json_file, 'r') as f:
            config = json.load(f)
    except Exception as e:
        print(f"Error reading the configuration file: {e}")
        return
    
    # Extract parameters from the JSON configuration
    db_cluster_identifier = config["DBClusterIdentifier"]
    engine = config["Engine"]
    engine_version = config["EngineVersion"]
    master_username = config["MasterUsername"]
    db_subnet_group = config["DBSubnetGroup"]
    vpc_security_groups = config["VpcSecurityGroups"]
    db_parameter_groups = config["DBClusterParameterGroups"]

    # Recreate the DB Cluster
    try:
        response = rds_client.create_db_cluster(
            DBClusterIdentifier=db_cluster_identifier,
            Engine=engine,
            EngineVersion=engine_version,
            MasterUsername=master_username,
            DBSubnetGroupName=db_subnet_group,
            VpcSecurityGroupIds=vpc_security_groups,
            DBClusterParameterGroupName=db_parameter_groups[0],  # Use the first parameter group
            # If needed, you can add additional parameters like tags or backup retention
        )
        print(f"Cluster {db_cluster_identifier} created successfully: {response}")
    except Exception as e:
        print(f"Error creating the DB Cluster: {e}")
        return

    # Extract instance details and recreate DB instances associated with the cluster
    for instance in config["Instances"]:
        db_instance_identifier = instance["DBInstanceIdentifier"]
        db_instance_class = instance["DBInstanceClass"]
        availability_zone = instance["AvailabilityZone"]
        
        try:
            response = rds_client.create_db_instance(
                DBInstanceIdentifier=db_instance_identifier,
                DBClusterIdentifier=db_cluster_identifier,
                DBInstanceClass=db_instance_class,
                AvailabilityZone=availability_zone,
                Engine=engine,
                DBSubnetGroupName=db_subnet_group
            )
            print(f"DB Instance {db_instance_identifier} created successfully: {response}")
        except Exception as e:
            print(f"Error creating DB instance {db_instance_identifier}: {e}")

# Run the function
if __name__ == "__main__":
    json_file = input("Enter the path to the configuration JSON file: ")
    if os.path.exists(json_file):
        recreate_babelfish_cluster(json_file)
    else:
        print(f"Configuration file {json_file} does not exist.")
