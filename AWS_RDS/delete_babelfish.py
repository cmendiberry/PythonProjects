from utils.aws_credentials import get_aws_client

def delete_babelfish_instance():
    # Get AWS client
    rds_client = get_aws_client("rds")

    # Ask for cluster ARN
    cluster_arn = input("Enter the Babelfish Aurora cluster ARN to delete: ")

    try:
        # Delete Cluster
        response = rds_client.delete_db_cluster(
            DBClusterIdentifier=cluster_arn,
            SkipFinalSnapshot=True  # Change to False if you need a final snapshot
        )
        print(f"DB Cluster {cluster_arn} deletion initiated:", response)

    except Exception as e:
        print(f"Error deleting cluster {cluster_arn}: {e}")

# Run the function
if __name__ == "__main__":
    delete_babelfish_instance()
