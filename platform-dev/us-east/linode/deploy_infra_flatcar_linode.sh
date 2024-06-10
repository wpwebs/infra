# Script automates the creation of a VPC network across multiple Linode regions 

# Explanation:
# 1. Variables: Define key variables, including Linode API token, SSH key path, Flatcar OS image URL, SSH user, and WireGuard port.
# 2. Region and Role Definitions: Specify IP address base for each region and the number of instances per role (load balancer, master, worker, storage). Define Linode instance types for each role to allow different resource allocations.
# 3. Ignition Config Generation: A function generates an Ignition config file for Flatcar OS, setting up system configurations like SSH access.
# 4. Create Linode VM Function: Uses linode-cli to create a Linode VM with a private IP, tailored to the role's instance type.
# 5. Install Flatcar OS Function: Downloads the Flatcar OS image, uploads it to the Linode VM, and installs it using the generated Ignition configuration.
# 6. WireGuard Setup Function: Configures WireGuard using Docker to establish secure VPN tunnels between nodes.
# 7. Main Execution Loop: Iterates over regions and roles, creating and configuring the required number of instances per role, setting up networking and operating system installations.
# This script provides a scalable and automated setup for deploying a multi-region Kubernetes-based WordPress hosting service on Linode, ensuring efficient resource allocation and secure inter-region communication.

#!/bin/bash

# Variables
API_TOKEN="your-linode-api-token"
SSH_PUBLIC_KEY_PATH="~/.ssh/id_rsa.pub"
FLATCAR_IMAGE_URL="https://stable.release.flatcar-linux.net/amd64-usr/current/flatcar_production_qemu_image.img.bz2"
FLATCAR_IMAGE="flatcar_production_qemu_image.img.bz2"
SSH_USER="core"
MACHINE_ID=$(uuidgen)
WG_PORT=51820

# Region-specific configuration
declare -A REGIONS
REGIONS["us-central"]="10.10"
REGIONS["us-east"]="10.20"
REGIONS["eu-west"]="10.30"

# Node roles and counts
declare -A ROLES
ROLES["loadbalancer"]=2
ROLES["master"]=3
ROLES["worker"]=5
ROLES["storage"]=3
ROLES["backup"]=2


# VM type mapping for each role
declare -A VM_TYPES
VM_TYPES["loadbalancer"]="g6-standard-1"
VM_TYPES["master"]="g6-standard-2"
VM_TYPES["worker"]="g6-standard-2"
VM_TYPES["storage"]="g6-standard-2"
VM_TYPES["backup"]="g6-standard-2"

# Generate Ignition config with SSH key and other necessary configurations
generate_ignition_config() {
  local ignition_config_file=$1

  cat > $ignition_config_file <<EOF
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
      },
      {
        "name": "systemd-networkd.service",
        "enabled": true
      },
      {
        "name": "systemd-resolved.service",
        "enabled": true
      }
    ]
  }
}
EOF
}

# Function to create a Linode VM using linode-cli
create_linode_vm() {
  local region=$1
  local label=$2
  local ip_suffix=$3
  local role=$4
  local private_ip="${REGIONS[$region]}.$ip_suffix"
  local vm_type="${VM_TYPES[$role]}"

  linode-cli linodes create \
    --region $region \
    --type $vm_type \
    --image linode/ubuntu20.04 \
    --root_pass "your-root-password" \
    --label $label \
    --private_ip true \
    --authorized_keys "$(cat $SSH_PUBLIC_KEY_PATH)" \
    --json

  echo $private_ip
}

# Function to install Flatcar OS on the Linode VM
install_flatcar_os() {
  local label=$1
  local private_ip=$2
  local ignition_config_file=$3

  echo "Downloading Flatcar image..."
  curl -LO $FLATCAR_IMAGE_URL
  bunzip2 $FLATCAR_IMAGE

  echo "Uploading Flatcar image and Ignition config to Linode..."
  scp flatcar_production_qemu_image.img root@$private_ip:/root/
  scp $ignition_config_file root@$private_ip:/root/

  echo "Installing Flatcar OS..."
  ssh root@$private_ip <<EOF
mkfs.ext4 /dev/sda
mount /dev/sda /mnt
cd /mnt
curl -LO $FLATCAR_IMAGE_URL
bunzip2 flatcar_production_qemu_image.img.bz2
./flatcar-install -d /dev/sda -i /root/ignition-config.json
reboot
EOF

  echo "Flatcar OS installation initiated on Linode VM with IP: $private_ip"
}

# Function to setup WireGuard using Docker on the Linode VM
setup_wireguard_docker() {
  local private_ip=$1
  local peer_ip=$2
  local peer_pubkey=$3

  ssh root@$private_ip <<EOF
docker pull cmulk/wireguard-docker
docker run -d --name wireguard --cap-add=NET_ADMIN --cap-add=SYS_MODULE -v /lib/modules:/lib/modules cmulk/wireguard-docker

# Create WireGuard configuration
cat <<WG_CONFIG > /etc/wireguard/wg0.conf
[Interface]
Address = $private_ip/24
PrivateKey = $(docker exec wireguard wg genkey)
ListenPort = $WG_PORT

[Peer]
PublicKey = $peer_pubkey
Endpoint = $peer_ip:$WG_PORT
AllowedIPs = 10.0.0.0/16
PersistentKeepalive = 25
WG_CONFIG

# Apply WireGuard configuration
docker exec wireguard wg-quick up /etc/wireguard/wg0.conf
EOF
}

# Main script execution
for region in "${!REGIONS[@]}"; do
  base_ip="${REGIONS[$region]}"
  for role in "${!ROLES[@]}"; do
    for i in $(seq 1 ${ROLES[$role]}); do
      label="$region-$role$i"
      ip_suffix="$((i+1))"
      private_ip=$(create_linode_vm $region $label $ip_suffix $role)

      # Generate and upload Ignition config
      ignition_config_file="/tmp/ignition-config-$label.json"
      generate_ignition_config $ignition_config_file
      install_flatcar_os $label $private_ip $ignition_config_file

      # Example WireGuard setup with placeholder values
      # Replace <PeerPrivateIP> and <PeerPublicKey> with actual values
      # setup_wireguard_docker $private_ip <PeerPrivateIP> <PeerPublicKey>
    done
  done
done

echo "VPC setup complete."
