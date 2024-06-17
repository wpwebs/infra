#!/bin/bash

VIRTUAL_IP="192.168.0.130"
NODES=("192.168.0.131" "192.168.0.132" "192.168.0.133")
S3_USERID="s3_user"
S3_USERNAME="s3_user"
# Function to check if s3cmd is installed
install_s3cmd_if_needed() {
    if ! command -v s3cmd &> /dev/null; then
        echo "s3cmd not found. Installing..."
        apt-get update
        apt-get install -y s3cmd
    else
        echo "s3cmd is already installed."
    fi
}

# Function to create a new RGW user on a node
create_rgw_user() {
    local node=$1
    echo "Attempting to create RGW user on $node..."
    ssh root@$node "radosgw-admin user create --uid=$S3_USERID --display-name=$S3_USERNAME" 2>/dev/null
}

# Function to replicate the RGW user to other nodes
replicate_rgw_user() {
    local node=$1
    local user_info=$2
    echo "Replicating RGW user to $node..."
    ssh root@$node "echo '$user_info' | radosgw-admin user create --infile -"
}

# Function to extract access and secret keys
extract_keys() {
    local output=$1
    ACCESS_KEY=$(echo $output | jq -r '.keys[0].access_key')
    SECRET_KEY=$(echo $output | jq -r '.keys[0].secret_key')
}

# Install s3cmd if needed
install_s3cmd_if_needed

# Create a new RGW user on the first available node and replicate it to other nodes
for node in "${NODES[@]}"; do
    user_output=$(create_rgw_user $node)
    if [ -n "$user_output" ]; then
        echo "RGW user created successfully on $node."
        extract_keys "$user_output"
        break
    else
        echo "Failed to create RGW user on $node. Trying the next node..."
    fi
done

# Check if keys were extracted
if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
    echo "Failed to create RGW user on any node. Exiting."
    exit 1
fi

# Replicate the RGW user to other nodes
for node in "${NODES[@]}"; do
    if [ "$node" != "$PRIMARY_NODE" ]; then
        replicate_rgw_user $node "$user_output"
    fi
done

# Create s3cmd configuration file
cat <<EOF > ~/.s3cfg
[default]
access_key = $ACCESS_KEY
secret_key = $SECRET_KEY
host_base = $VIRTUAL_IP:7480
host_bucket = $VIRTUAL_IP:7480
use_https = False
EOF

# Test s3cmd setup by creating a bucket and uploading a file
s3cmd mb s3://test-bucket
echo "This is a test file." > testfile.txt
s3cmd put testfile.txt s3://test-bucket

# Verify the file was uploaded
s3cmd ls s3://test-bucket

echo "s3cmd configuration and testing completed successfully."
