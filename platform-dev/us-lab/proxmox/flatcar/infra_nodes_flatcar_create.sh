#!/bin/bash

# Define regions and IP prefix
REGIONS="us-lab"
IP_PREFIX="10.0"

# Define node and template information
NODE="1"
VLAN="172"

PROXMOX_USER="root"
PROXMOX_HOST="192.168.1.2$NODE"
NODE_NAME="pve$NODE"

# Path variables for the Flatcar image and Ignition configs on the Proxmox server
IGNITION_PATH="/var/lib/vz/template/snippets"
FLATCAR_PATH="/var/lib/vz/template/images"
FLATCAR_IMG="flatcar-stable.img"

# Define IP ranges and roles
IP_RANGES_loadbalancer="$IP_PREFIX.1.0/24"
IP_RANGES_master="$IP_PREFIX.2.0/24"
IP_RANGES_worker="$IP_PREFIX.3.0/24"
IP_RANGES_storage="$IP_PREFIX.4.0/24"
IP_RANGES_backup="$IP_PREFIX.5.0/24"
IP_RANGES_network="$IP_PREFIX.6.0/24"  # Network devices
IP_RANGES_monitoring="$IP_PREFIX.7.0/24"
IP_RANGES_operations="$IP_PREFIX.8.0/24"

# Node roles and counts
ROLES_loadbalancer=1
ROLES_master=1
ROLES_worker=2
ROLES_storage=1
ROLES_backup=1

# VM type mapping for each role
VM_TYPES_loadbalancer="CORES=2; RAM=4096; STORAGE_DISK_POOL=ssd-storage; STORAGE_DISK_SIZE=50"
VM_TYPES_master="CORES=8; RAM=8192; STORAGE_DISK_POOL=ssd-storage; STORAGE_DISK_SIZE=100"
VM_TYPES_worker="CORES=8; RAM=8192; STORAGE_DISK_POOL=ssd-storage; STORAGE_DISK_SIZE=100"
VM_TYPES_storage="CORES=2; RAM=4096; STORAGE_DISK_POOL=ssd-storage; STORAGE_DISK_SIZE=1000"
VM_TYPES_backup="CORES=2; RAM=4096; STORAGE_DISK_POOL=ssd-storage; STORAGE_DISK_SIZE=1000"

# Extract the gateway from the network IP range
NETWORK_GATEWAY=$(echo $IP_RANGES_network | cut -d'.' -f1-3).1
NETWORK_DNS=$(echo $IP_RANGES_network | cut -d'.' -f1-3).1

# SSH and public key variables
SSH_USER="core"
SSH_PUBLIC_KEY_PATH="/Users/henry/.ssh/ssh_key.pub"

# Function to get a value from a string-based mapping
extract_value() {
    local string=$1
    local key=$2
    echo "$string" | sed -n "s/.*$key=\([^;]*\).*/\1/p" | tr -d "'"
}

# Function to create VMs
create_vm() {
    local role=$1
    local count=$2
    local ip_prefix=$3

    local ip_range_var="IP_RANGES_$role"
    local vm_type_var="VM_TYPES_$role"
    local ip_range=${!ip_range_var}
    local vm_type=${!vm_type_var}

    local ip_base=$(echo $ip_range | cut -d'.' -f1-3)

    # Extract VM types
    CORES=$(extract_value "$vm_type" "CORES")
    RAM=$(extract_value "$vm_type" "RAM")
    STORAGE_DISK_POOL=$(extract_value "$vm_type" "STORAGE_DISK_POOL")
    STORAGE_DISK_SIZE=$(extract_value "$vm_type" "STORAGE_DISK_SIZE")

    for ((i=1; i<=count; i++)); do
        local last_ip=$((100 + i))
        local vm_id="${NODE}${ip_base##*.}${last_ip}"
        local ip="${ip_base}.${last_ip}"
        local vm_name="${role}-${i}"

        echo "Creating VM: $vm_name with ID: $vm_id, IP: $ip for role: $role"

        # Generate a unique machine ID
        local machine_id=$(uuidgen)

        # Generate Ignition config
        local ignition_file="ignition-config-${vm_id}.json"
        cat > $ignition_file <<EOF
{
  "ignition": {
    "version": "3.0.0"
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
  "storage": {
    "files": [
      {
        "path": "/etc/hostname",
        "contents": {
          "source": "data:,${vm_name}"
        },
        "mode": 420
      },
      {
        "path": "/etc/machine-id",
        "contents": {
          "source": "data:,${machine_id}"
        },
        "mode": 420
      },
      {
        "path": "/etc/systemd/network/00-eth0.network",
        "contents": {
          "source": "data:,%5BMatch%5D%0AName=eth0%0A%5BNetwork%5D%0ADHCP=yes%0A"
        },
        "mode": 420
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

        # Upload Ignition config to Proxmox
        ssh $PROXMOX_USER@$PROXMOX_HOST "mkdir -p $IGNITION_PATH"
        scp $ignition_file $PROXMOX_USER@$PROXMOX_HOST:$IGNITION_PATH/

        ssh $PROXMOX_USER@$PROXMOX_HOST <<EOF
# Create VM
pvesh create /nodes/${NODE_NAME}/qemu \
  -vmid $vm_id \
  -name $vm_name \
  -machine q35 \
  -memory $RAM \
  -sockets 1 \
  -cores $CORES \
  -net0 virtio,bridge=vmbr0,tag=$VLAN \
  -scsihw virtio-scsi-pci \
  -numa 1 \
  -hotplug disk,network,cpu,memory

# Import the Flatcar image to the VM's storage
qm importdisk $vm_id $FLATCAR_PATH/$FLATCAR_IMG $STORAGE_DISK_POOL --format raw

# Attach the imported disk to the VM
pvesh set /nodes/${NODE_NAME}/qemu/$vm_id/config -scsi0 ${STORAGE_DISK_POOL}:vm-${vm_id}-disk-0,discard=on,ssd=1 
pvesh set /nodes/${NODE_NAME}/qemu/$vm_id/config -scsi1 ${STORAGE_DISK_POOL}:${STORAGE_DISK_SIZE}
pvesh set /nodes/${NODE_NAME}/qemu/$vm_id/config -boot order=scsi0
pvesh set /nodes/${NODE_NAME}/qemu/$vm_id/config -serial0 socket
pvesh set /nodes/${NODE_NAME}/qemu/$vm_id/config -onboot 1
pvesh set /nodes/${NODE_NAME}/qemu/$vm_id/config -args "-fw_cfg name=opt/org.flatcar-linux/config,file=$IGNITION_PATH/$ignition_file"

# Start the VM
qm start $vm_id

EOF

        # Cleanup Ignition config
        rm $ignition_file

        # Add to summary
        summary+="VM $vm_name (ID: $vm_id) - IP: $ip\n"

        echo "VM $vm_name (ID: $vm_id) created and started."
    done
}

# Main script

# Summary of created VMs
summary=""

# Create VMs for each role
# for role in loadbalancer master worker storage backup; do
for role in loadbalancer; do
    count_var="ROLES_$role"
    count=${!count_var}
    create_vm $role $count "$IP_PREFIX"
done

# Print out summary
echo -e "\nSummary of created nodes:\n"
echo -e "$summary"

echo "VM nodes for a Kubernetes cluster infrastructure creation process completed."
