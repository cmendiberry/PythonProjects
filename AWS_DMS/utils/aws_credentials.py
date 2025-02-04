import boto3

def get_aws_client(service_name):
    """Retrieve AWS credentials dynamically and return a boto3 client for the given service."""
    aws_access_key = input("Enter AWS Access Key: ")
    aws_secret_key = input("Enter AWS Secret Key: ")
    aws_session_token= input("Enter AWS Session Token: ")
    aws_region = input("Enter AWS Region (e.g., us-east-1): ")

    return boto3.client(
        service_name,
        aws_access_key_id=aws_access_key,
        aws_secret_access_key=aws_secret_key,
        aws_session_token=aws_session_token,
        region_name=aws_region
    )
