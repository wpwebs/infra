# Script fully automate the to create a Linode VM, and installation of Flatcar OS

# Explanation
# 1. Generate Ignition Config:
#     * The script creates an Ignition config file that sets up the SSH key, formats the root filesystem, and configures the system to boot properly with the SSH service enabled.
# 2. Create Linode VM:
#     * The create_linode_vm function creates a Linode VM using the Linode API, captures the VM's ID and IP address, and labels it for easier management.
# 3. Install Flatcar OS:
#     * The install_flatcar_os function downloads the Flatcar image, uploads it to the Linode VM along with the Ignition config file, and installs Flatcar OS by formatting the disk and using the Ignition configuration.
#     * It reboots the VM to complete the installation.
# 4. Automation:
#     * The script waits for 60 seconds to ensure the VM is fully booted and accessible via SSH before starting the installation process.

# Notes
# * API Token: Replace your-linode-api-token with your actual Linode API token.
# * Region and Instance Type: Customize the REGION and INSTANCE_TYPE variables according to your preference and requirements.
# * Root Password: Replace your-root-password with a secure password for the root user.
# * SSH Public Key: Update SSH_PUBLIC_KEY_PATH with the path to your SSH public key.
# * Sleep Time: Adjust the sleep 60 duration as needed to ensure the VM is ready for SSH access.
# This script provides a fully automated solution to create a Linode VM, configure it to boot from Flatcar OS using Ignition, and sets up the necessary SSH keys for secure access.

#!/bin/bash

# Variables
API_TOKEN="your-linode-api-token"
REGION="us-central"  # Change this to your preferred region
INSTANCE_TYPE="g6-standard-2"  # Linode instance type
IMAGE="linode/ubuntu20.04"  # Using Ubuntu as a placeholder
ROOT_PASS="your-root-password"  # Replace with a secure password
LABEL="flatcar-install"
SSH_PUBLIC_KEY_PATH="~/.ssh/id_rsa.pub"
FLATCAR_IMAGE_URL="https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2"
FLATCAR_IMAGE="flatcar_production_qemu_image.img.bz2"
SSH_USER="core"
MACHINE_ID=$(uuidgen)

# Generate Ignition config with SSH key and other necessary configurations
cat > ignition-config.json <<EOF
{
  "ignition": {
    "version": "3.0.0"
  },
  "storage": {
    "files": [
      {
        "path": "/etc/machine-id",
        "contents": {
          "source": "data:,${MACHINE_ID}"
        },
        "mode": 420
      }
    ],
    "filesystems": [
      {
        "device": "/dev/sda1",
        "format": "ext4",
        "label": "ROOT",
        "path": "/sysroot"
      }
    ]
  },
  "passwd": {
    "users": [
      {
        "name": "$SSH_USER",
        "sshAuthorizedKeys": [
          "$(cat $SSH_PUBLIC_KEY_PATH)"
        ]
      }
    ]
  },
  "systemd": {
    "units": [
      {
        "name": "sshd.service",
        "enabled": true
      }
    ]
  }
}
EOF

# Function to create a Linode VM
create_linode_vm() {
  echo "Creating Linode VM..."
  RESPONSE=$(curl -s -X POST https://api.linode.com/v4/linode/instances \
    -H "Authorization: Bearer ${API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
          "region": "'${REGION}'",
          "type": "'${INSTANCE_TYPE}'",
          "image": "'${IMAGE}'",
          "root_pass": "'${ROOT_PASS}'",
          "authorized_keys": ["'"$(cat ${SSH_PUBLIC_KEY_PATH})"'"],
          "label": "'${LABEL}'",
          "booted": true
        }')

  LINODE_ID=$(echo $RESPONSE | jq -r '.id')
  LINODE_IP=$(echo $RESPONSE | jq -r '.ipv4[0]')

  echo "Linode VM created with ID: $LINODE_ID and IP: $LINODE_IP"
}

# Function to install Flatcar OS on the Linode VM
install_flatcar_os() {
  echo "Downloading Flatcar image..."
  curl -LO $FLATCAR_IMAGE_URL
  bunzip2 $FLATCAR_IMAGE

  echo "Uploading Flatcar image and Ignition config to Linode..."
  scp flatcar_production_qemu_image.img root@$LINODE_IP
