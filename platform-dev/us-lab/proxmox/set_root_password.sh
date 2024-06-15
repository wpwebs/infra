#!/bin/bash

REMOTE_USER="root"
REMOTE_HOST=${1-"192.168.1.1"}

# Generate a strong password
ROOT_PASSWORD=$(openssl rand -base64 12)
echo "Generated root password: $ROOT_PASSWORD"

# Create a hash of the password
HASHED_PASSWORD=$(openssl passwd -6 "$ROOT_PASSWORD")

# Upload the password to the remote server
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $REMOTE_USER@$REMOTE_HOST "echo '$REMOTE_USER:$HASHED_PASSWORD' | sudo chpasswd -e"
