# Clone Flatcar Template and Configure New VM with Separate Boot and Storage Disks

# Explanation
# 1. Variables: Define the variables for the Proxmox host, template ID, new VM ID, CPU, RAM, boot disk storage, additional storage disk storage, VLAN, IP address, gateway, hostname, and SSH public key path.
# 2. Generate Ignition Config: Create an Ignition configuration file that sets up the SSH key, hostname, unique machine ID, and network configuration.
# 3. Upload Ignition Config: Upload the Ignition configuration file to the Proxmox server.
# 4. Clone the Template: Use the qm clone command to clone the template VM to create a new VM.
# 5. Configure the New VM: Set the CPU, RAM, separate storage for the boot disk and additional storage disk, network settings, and specify the Ignition configuration file for the new VM.
# 6. Start the New VM: Start the new VM.
# 7. Wait for VM to Start: The script waits for the VM to start and become ready.
# 8. Clean Up: Remove the local Ignition configuration file.

# Notes
# * Automation: The script automates the cloning and configuration of a new VM from a Flatcar template using Ignition for initial setup.
# * Variables: Ensure you replace placeholder values such as your-proxmox-host, and other specific configuration details with your actual Proxmox server details and network configuration.
# * SSH Key Path: Update the SSH_PUBLIC_KEY_PATH variable with the path to your SSH public key file.
# * CPU, RAM, and Storage: The script allows you to define the number of CPU cores, the amount of RAM, and the sizes of the boot disk and additional storage disk for the new VM.
# * Hostname: The script sets the hostname for the new VM and ensures it is reflected in the /etc/hostname file.
# This script sets up a new Flatcar VM by cloning a template and configuring it with specific resources, network settings, and hostname, ensuring a seamless and automated provisioning process.

#!/bin/bash

# Variables
PROXMOX_HOST="your-proxmox-host"
PROXMOX_USER="root@pam"
TEMPLATE_ID="9000"
NEW_VM_ID="9001"
NEW_VM_NAME="flatcar-clone"
BOOT_DISK_STORAGE="local-lvm"  # Storage pool for the boot disk
STORAGE_DISK_STORAGE="local"   # Storage pool for the additional storage disk
CPU_CORES=2
RAM_MB=2048
BOOT_DISK_SIZE="32G"
STORAGE_DISK_SIZE="50G"
VLAN="100"
VM_IP="192.168.1.101"
VM_GW="192.168.1.1"
HOSTNAME="new-vm-hostname"
SSH_PUBLIC_KEY_PATH="/Users/henry/.ssh/ssh_key.pub"
SSH_USER="core"

# Generate a unique machine ID
MACHINE_ID=$(uuidgen)

# Generate Ignition config with SSH key and hostname
cat > $IGNITION_CONFIG <<EOF
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
  },
  "network": {
    "version": 2,
    "ethernets": {
      "eth0": {
        "dhcp4": false,
        "addresses": ["${VM_IP}/24"],
        "gateway4": "${VM_GW}",
        "nameservers": {
          "addresses": ["${VM_GW}"]
        }
      }
    }
  }
}
EOF


# Upload Ignition config to Proxmox
scp ignition-config.json $PROXMOX_USER@$PROXMOX_HOST:/var/lib/vz/template/iso/

# Clone the template
ssh $PROXMOX_USER@$PROXMOX_HOST <<EOF
qm clone $TEMPLATE_ID $NEW_VM_ID --name $NEW_VM_NAME --full true --storage $BOOT_DISK_STORAGE

# Configure the new VM
qm set $NEW_VM_ID \
  --cores $CPU_CORES \
  --memory $RAM_MB \
  --scsihw virtio-scsi-pci \
  --scsi0 $BOOT_DISK_STORAGE:$BOOT_DISK_SIZE \
  --scsi1 $STORAGE_DISK_STORAGE:$STORAGE_DISK_SIZE \
  --net0 virtio,bridge=vmbr0,tag=$VLAN \
  --ipconfig0 ip=$VM_IP/24,gw=$VM_GW \
  --serial0 socket \
  --vga serial0 \
  --machine q35 \
  --args "-fw_cfg name=opt/com.coreos/config,file=/var/lib/vz/template/iso/ignition-config.json" \
	--onboot 1 

# Start the new VM
qm start $NEW_VM_ID
EOF

# Wait for the VM to start
echo "Waiting for the VM to start..."
sleep 60

# Clean up local files
rm ignition-config.json

echo "New VM has been created successfully from the Flatcar template with the specified configuration."
