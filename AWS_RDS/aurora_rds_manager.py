import re
from utils.aws_credentials import get_aws_client

# Global AWS RDS client
rds_client = None


def list_rds_clusters(pattern):
    response = rds_client.describe_db_clusters()
    matching_clusters = [
        cluster for cluster in response['DBClusters']
        if re.search(pattern, cluster['DBClusterIdentifier'], re.IGNORECASE)
    ]
    return matching_clusters


def print_clusters(clusters):
    if not clusters:
        print("No clusters found.")
        return

    print("\n🔍 Matching Aurora Clusters:")
    for i, cl in enumerate(clusters, start=1):
        print(f"{i}. {cl['DBClusterIdentifier']} ({cl['Status']})")
    print()


def get_cluster_status(cluster_identifier):
    response = rds_client.describe_db_clusters(DBClusterIdentifier=cluster_identifier)
    return response['DBClusters'][0]['Status']


def start_cluster(cluster_identifier):
    rds_client.start_db_cluster(DBClusterIdentifier=cluster_identifier)


def stop_cluster(cluster_identifier):
    rds_client.stop_db_cluster(DBClusterIdentifier=cluster_identifier)


def main_menu():
    global rds_client

    try:
        print("🔐 Getting AWS credentials and initializing RDS client...")
        rds_client = get_aws_client("rds")

        pattern = input("🔍 Enter cluster name pattern to search: ").strip()
        clusters = list_rds_clusters(pattern)
        if not clusters:
            print("No matching Aurora clusters found.")
            return

        print_clusters(clusters)

        while True:
            print("📋 Menu:")
            print("1. Get status for cluster(s)")
            print("2. Start cluster(s)")
            print("3. Stop cluster(s)")
            print("4. Exit")
            choice = input("Select an option (1-4): ").strip()

            if choice not in {'1', '2', '3', '4'}:
                print("❗ Invalid option. Try again.\n")
                continue

            if choice == '4':
                break

            all_choice = input("Apply to all matching clusters? (y/n): ").strip().lower()
            target_clusters = []

            if all_choice == 'y':
                target_clusters = clusters
            else:
                name = input("Enter cluster name from the list above: ").strip()
                cluster = next((c for c in clusters if c['DBClusterIdentifier'] == name), None)
                if not cluster:
                    print("❗ Cluster not found.\n")
                    continue
                target_clusters = [cluster]

            for cl in target_clusters:
                cluster_id = cl['DBClusterIdentifier']
                try:
                    if choice == '1':
                        status = get_cluster_status(cluster_id)
                        print(f"🔎 {cluster_id}: {status}")
                    elif choice == '2':
                        start_cluster(cluster_id)
                        print(f"▶️ Starting cluster {cluster_id}")
                    elif choice == '3':
                        stop_cluster(cluster_id)
                        print(f"⏹️ Stopping cluster {cluster_id}")
                except Exception as e:
                    print(f"❌ Error with {cluster_id}: {str(e)}")

            print()

    finally:
        # Clear sensitive info
        rds_client = None
        print("🧹 AWS credentials cleared. Exiting.")


if __name__ == '__main__':
    main_menu()
