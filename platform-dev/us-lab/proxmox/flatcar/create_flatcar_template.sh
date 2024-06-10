# Script to Create a Flatcar Template from Cloud Image on Proxmox with Passing Ignition Config to the VM

# This script automates the process of creating a Flatcar Linux template VM on a Proxmox server using a cloud image and an Ignition configuration file. Here's a step-by-step breakdown of what the script does:
# 1. Define Variables
# * Node and VM Configuration:
#     * NODE, VM_ID, CORES, RAM, STORAGE_DISK_SIZE, STORAGE_DISK_POOL, VM_VLAN, VM_IP, VM_GW, VM_NAME, HOSTNAME: These variables set up the Proxmox node, VM ID, hardware resources, network settings, and hostname.
# * User and Proxmox Server Configuration:
#     * SSH_PUBLIC_KEY_PATH, SSH_USER, PROXMOX_HOST, PROXMOX_USER: These variables define the paths for the SSH public key, the SSH user, and the Proxmox server login details.
# * Paths for Flatcar and Ignition Config:
#     * FLATCAR_PATH, IGNITION_PATH, FLATCAR_IMG, IGNITION_FILE: These variables define the paths where the Flatcar image and Ignition configuration file will be stored locally and on the Proxmox server.
# 2. Upload Flatcar Cloud Image to Proxmox
# * Check and Download the Flatcar Image:
#     * The script checks if the Flatcar cloud image exists on the remote Proxmox server. If not, it downloads the image from the Flatcar release website to the local machine.
# * Upload the Image to Proxmox:
#     * If the image is not present on the Proxmox server, it uploads the downloaded image to the specified directory on the Proxmox server.
# 3. Generate Ignition Config
# * Create Unique Machine ID:
#     * The script generates a unique machine ID using uuidgen.
# * Generate Ignition Configuration:
#     * The script creates an Ignition configuration file that includes:
#         * Adding the SSH public key for the core user.
#         * Setting the hostname.
#         * Configuring the network interface with the specified IP address, gateway, and DNS.
#         * Enabling the SSH service and network services.
# 4. Upload Ignition Config to Proxmox
# * Ensure Remote Directory Exists:
#     * The script ensures that the directory for storing Ignition configs exists on the Proxmox server.
# * Upload the Ignition Config:
#     * The Ignition configuration file is uploaded to the specified directory on the Proxmox server.
# 5. Create and Configure the VM
# * Create the VM:
#     * The script uses pvesh to create a new VM on Proxmox with the specified hardware and network configuration.
# * Import and Attach the Flatcar Image:
#     * The script uses qm importdisk to import the Flatcar cloud image to the Proxmox storage pool.
#     * The script then uses pvesh to attach the imported disk to the VM, configure it as a SCSI disk, and set it as the boot disk.
# * Configure Additional VM Settings:
#     * Additional settings are applied to the VM, including serial socket configuration, setting the VM to start on boot, and passing the Ignition config to the VM.
# 6. Start the VM
# * Start the VM:
#     * The VM is started using pvesh.
# 7. Verify SSH Access
# * Wait for VM to Boot:
#     * The script waits for 60 seconds to allow the VM to boot up and apply the configuration.
# * Check SSH Access:
#     * The script repeatedly tries to SSH into the VM until it succeeds, indicating that the VM is up and the Ignition config has been applied.
# 8. Convert VM to Template
# * Stop the VM and Convert to Template:
#     * The script stops the VM and converts it into a template using qm.
# 9. Clean Up Local Files
# * Remove Local Files:
#     * The script cleans up by removing the local copies of the Flatcar image and Ignition configuration file.
# 10. Completion Message
# * Success Message:
#     * The script prints a success message indicating that the Flatcar template has been created on Proxmox with SSH key setup for passwordless access.

#!/bin/bash

# Variables
NODE="1"
VM_ID="9000"

CORES="2"
RAM="2048"
STORAGE_DISK_SIZE="50"
STORAGE_DISK_POOL="ssd-storage"   # Storage pool for the additional storage disk

VM_VLAN="172"
VM_IP="10.0.0.${NODE}00"
VM_GW="10.0.6.1"
VM_NAME="flatcar-template"
HOSTNAME="flatcar-template"

SSH_PUBLIC_KEY_PATH="/Users/henry/.ssh/ssh_key.pub"
SSH_USER="core"

PROXMOX_HOST="192.168.1.2$NODE"
PROXMOX_USER="root"
VM_ID=$NODE$VM_ID
NODE="pve$NODE"

# Download the latest Flatcar Container Linux stable cloud image
FLATCAR_PATH="/var/lib/vz/template/images"
IGNITION_PATH="/var/lib/vz/template/snippets"
FLATCAR_IMG="flatcar-stable.img"
IGNITION_FILE="ignition-config-$VM_ID.json"

# Upload the Flatcar cloud image to Proxmox
# Check if the cloud image file exists on the remote server
if ssh $PROXMOX_USER@$PROXMOX_HOST "[ ! -f $FLATCAR_PATH/$FLATCAR_IMG ]"; then
    echo "Cloud image file does not exist on the remote server. Uploading..."
    # Download the latest Flatcar Container Linux stable QCOW2 image, if not exist
    if [ ! -f "$FLATCAR_IMG" ]; then
        echo "Cloud image file does not exist on the local folder. Downloading..."
        FLATCAR_CHANNEL="stable"
        FLATCAR_VERSION="current"
        LATEST_FLATCAR_URL="https://${FLATCAR_CHANNEL}.release.flatcar-linux.net/amd64-usr/${FLATCAR_VERSION}/flatcar_production_qemu_image.img"
        curl -L $LATEST_FLATCAR_URL -o $FLATCAR_IMG
    else
        echo "Cloud image file already exists on the local folder. Skipping download."
    fi
    echo "Uploading the cloud image file to the remote server. ..."
    # Ensure the destination directory exists on the remote server
    ssh $PROXMOX_USER@$PROXMOX_HOST "mkdir -p $FLATCAR_PATH"
    scp $FLATCAR_IMG $PROXMOX_USER@$PROXMOX_HOST:$FLATCAR_PATH/
else
    echo "Cloud image file already exists on the remote server. Skipping upload."
fi

# Generate a unique machine ID
MACHINE_ID=$(uuidgen)

# Generate Ignition config with SSH key and hostname
cat > $IGNITION_FILE <<EOF
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
          "source": "data:,${HOSTNAME}"
        },
        "mode": 420
      },
      {
        "path": "/etc/machine-id",
        "contents": {
          "source": "data:,${MACHINE_ID}"
        },
        "mode": 420
      },
      {
        "path": "/etc/systemd/network/00-eth0.network",
        "contents": {
          "source": "data:,%5BMatch%5D%0AName=eth0%0A%5BNetwork%5D%0AAddress=${VM_IP}/24%0AGateway=${VM_GW}%0ADNS=${VM_GW}%0A"
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
# Ensure the destination directory exists on the remote server
ssh $PROXMOX_USER@$PROXMOX_HOST "mkdir -p $IGNITION_PATH"
scp $IGNITION_FILE $PROXMOX_USER@$PROXMOX_HOST:$IGNITION_PATH

# Create VM using pvesh
ssh $PROXMOX_USER@$PROXMOX_HOST <<EOF
pvesh create /nodes/${NODE}/qemu \
  -vmid $VM_ID \
  -name $VM_NAME \
  -machine q35 \
  -memory $RAM \
  -sockets 1 \
  -cores $CORES \
  -net0 virtio,bridge=vmbr0,tag=$VM_VLAN \
  -scsihw virtio-scsi-pci

# Import the Flatcar image to the VM's storage
qm importdisk $VM_ID $FLATCAR_PATH/$FLATCAR_IMG $STORAGE_DISK_POOL --format raw

# Attach the imported disk to the VM
pvesh set /nodes/${NODE}/qemu/$VM_ID/config -scsi0 ${STORAGE_DISK_POOL}:vm-$VM_ID-disk-0,discard=on,ssd=1 
# pvesh set /nodes/${NODE}/qemu/$VM_ID/config -scsi1 $STORAGE_DISK_POOL:$STORAGE_DISK_SIZE
pvesh set /nodes/${NODE}/qemu/$VM_ID/config -boot order="scsi0"
pvesh set /nodes/${NODE}/qemu/$VM_ID/config -serial0 socket
pvesh set /nodes/${NODE}/qemu/$VM_ID/config -onboot 1
# pvesh set /nodes/${NODE}/qemu/$VM_ID/config -args "-fw_cfg name=opt/org.flatcar-linux/config,file=$IGNITION_PATH/$IGNITION_FILE"

pvesh create /nodes/${NODE}/qemu/$VM_ID/status/start

EOF

# Wait for the VM to boot and setup Flatcar
echo "Wait for the VM to boot and setup Flatcar..."
sleep 60

# Verify SSH access
# until ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$VM_IP "echo SSH is ready"
# do
#   echo "Waiting for SSH to be ready..."
#   sleep 10
# done

# Stop the VM and convert it to a template
ssh $PROXMOX_USER@$PROXMOX_HOST <<EOF
qm stop $VM_ID
qm template $VM_ID
EOF

# Clean up local files
rm $FLATCAR_IMG
rm $IGNITION_FILE

echo "Flatcar template has been created successfully on Proxmox with SSH key setup for passwordless access."
