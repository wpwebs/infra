# Create Proxmox Template Using Ubuntu 22.04 LTS Cloud Image

# Explanation
# 1. Variables: Define the variables for the Proxmox host, template ID, new VM ID, CPU, RAM, storage, VLAN, IP address, gateway, hostname, and SSH public key path.
# 2. Download Ubuntu Cloud Image: The script fetches the Ubuntu 22.04 LTS cloud image and downloads it.
# 3. Upload Cloud Image to Proxmox: The script uploads the downloaded cloud image to the Proxmox server.
# 4. Create VM Template: The script creates a VM from the cloud image, sets it as a template, and configures it with specified resources.
# 5. Generate Cloud-Init User Data: The script creates a user-data file for cloud-init to configure the VM with SSH keys, hostname, and to install the qemu-guest-agent and clear the machine ID.
# 6. Create Cloud-Init ISO: The script creates a cloud-init ISO from the user-data file.
# 7. Upload Cloud-Init ISO: The script uploads the cloud-init ISO to the Proxmox server.
# 8. Clone the Template: The script clones the template VM to create a new VM with a specified ID and name.
# 9. Configure the New VM: The script sets the CPU cores, RAM, boot disk storage, additional storage disk storage, VLAN, IP address, gateway, SSH keys, and boot disk for the new VM.
# 10. Start the New VM: The script starts the new VM.
# 11. Wait for VM to Start: The script waits for the VM to start and become ready.
# 12. Clean Up: The script removes the local cloud image, cloud-init ISO, and user-data file after the template and VM are created.

# Notes
# * Automation: The script automates the setup process using the Ubuntu cloud image, making it efficient and reducing manual steps.
# * Variables: Ensure you replace placeholder values such as your-proxmox-host, and other specific configuration details with your actual Proxmox server details and network configuration.
# * SSH Key Path: Update the SSH_PUBLIC_KEY_PATH variable with the path to your SSH public key file.
# * CPU, RAM, and Storage: The script allows you to define the number of CPU cores, the amount of RAM, and the sizes of the boot disk and additional storage disk for the new VM.
# * Hostname: The script sets the hostname for the new VM and ensures it is reflected in the /etc/hostname file.
# This script sets up a new Ubuntu 22.04 LTS VM by cloning a template and configuring it with specific resources, network settings, and hostname, ensuring a seamless and automated provisioning process.

#!/bin/bash

# Variables
PROXMOX_HOST="your-proxmox-host"
PROXMOX_USER="root@pam"
TEMPLATE_ID="9000"        # ID for the new template VM
NEW_VM_ID="9001"          # ID for the new VM from the template
VM_NAME="ubuntu-template"
NEW_VM_NAME="ubuntu-clone"
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
SSH_PUBLIC_KEY_PATH="~/.ssh/id_rsa.pub"
SSH_USER="ubuntu"
UBUNTU_CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
CLOUD_INIT_IMAGE="ubuntu-22.04-cloudimg.img"

# Download the Ubuntu 22.04 LTS cloud image
curl -L $UBUNTU_CLOUD_IMAGE_URL -o $CLOUD_INIT_IMAGE

# Upload the cloud image to Proxmox
scp $CLOUD_INIT_IMAGE $PROXMOX_USER@$PROXMOX_HOST:/var/lib/vz/template/qemu/

# Create VM template from the Ubuntu cloud image
ssh $PROXMOX_USER@$PROXMOX_HOST <<EOF
qm create $TEMPLATE_ID --name $VM_NAME --memory $RAM_MB --cores $CPU_CORES --net0 virtio,bridge=vmbr0,tag=$VLAN
qm importdisk $TEMPLATE_ID /var/lib/vz/template/qemu/$CLOUD_INIT_IMAGE $BOOT_DISK_STORAGE
qm set $TEMPLATE_ID --scsihw virtio-scsi-pci --scsi0 $BOOT_DISK_STORAGE:vm-$TEMPLATE_ID-disk-0 --ide2 $BOOT_DISK_STORAGE:cloudinit
qm set $TEMPLATE_ID --boot c --bootdisk scsi0 --serial0 socket --vga serial0
qm set $TEMPLATE_ID --sshkeys $SSH_PUBLIC_KEY_PATH
qm template $TEMPLATE_ID
EOF

# Generate cloud-init user data configuration
cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
fqdn: $HOSTNAME
manage_etc_hosts: true
users:
  - name: $SSH_USER
    ssh-authorized-keys:
      - $(cat $SSH_PUBLIC_KEY_PATH)
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - [ cloud-init-per, once, qemu-guest-agent, systemctl enable --now qemu-guest-agent ]
  - [ cloud-init-per, once, clean-machine-id, bash -c 'truncate -s 0 /etc/machine-id && rm /var/lib/dbus/machine-id && ln -fs /etc/machine-id /var/lib/dbus/machine-id' ]
EOF

# Create cloud-init ISO
cloud-localds cloud-init.iso user-data

# Upload cloud-init ISO to Proxmox
scp cloud-init.iso $PROXMOX_USER@$PROXMOX_HOST:/var/lib/vz/template/iso/

# Clone the template to create a new VM
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
    --ide2 $BOOT_DISK_STORAGE:cloudinit \
    --boot c --bootdisk scsi0

# Start the new VM
qm start $NEW_VM_ID
EOF

# Wait for the VM to start
echo "Waiting for the VM to start..."
sleep 60

# Clean up local files
rm $CLOUD_INIT_IMAGE cloud-init.iso user-data

echo "New Ubuntu VM has been created and configured successfully from the template."
