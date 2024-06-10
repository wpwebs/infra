# Clone Ubuntu Template and  and Configure New VM with Separate Boot and Storage Disks

# Explanation
# 1. Variables: Define the variables for the Proxmox host, template ID, new VM ID, CPU, RAM, boot disk storage, additional storage disk storage, VLAN, IP address, gateway, hostname, and SSH public key path.
# 2. Generate Cloud-Init User Data: Create a user-data file for cloud-init to configure the VM with SSH keys, hostname, and to install the qemu-guest-agent and clear the machine ID.
# 3. Create Cloud-Init ISO: Create a cloud-init ISO from the user-data file.
# 4. Upload Cloud-Init ISO: Upload the cloud-init ISO to the Proxmox server.
# 5. Clone the Template: Use the qm clone command to clone the template VM to create a new VM.
# 6. Configure the New VM: Set the CPU, RAM, separate storage for the boot disk and additional storage disk, network settings, and specify the cloud-init ISO for the new VM.
# 7. Start the New VM: Start the new VM.
# 8. Wait for VM to Start: The script waits for the VM to start and become ready.
# 9. Get IP Address: The script retrieves the IP address assigned to the VM.
# 10. Wait for SSH to be Available: The script waits until SSH is available on the new VM.
# 11. Configure Additional Storage Disk: The script sets up and mounts the additional storage disk inside the VM.
# 12. Clean Up: Remove the local cloud-init ISO and user-data file.
# Notes
# * Automation: The script automates the cloning and configuration of a new VM from an Ubuntu template using cloud-init for initial setup and SSH for additional configurations.
# * Variables: Ensure you replace placeholder values such as your-proxmox-host, and other specific configuration details with your actual Proxmox server details and network configuration.
# * SSH Key Path: Update the SSH_PUBLIC_KEY_PATH variable with the path to your SSH public key file.
# * CPU, RAM, and Storage: The script allows you to define the number of CPU cores, the amount of RAM, and the sizes of the boot disk and additional storage disk for the new VM.
# * Hostname: The script sets the hostname for the new VM and ensures it is reflected in the /etc/hostname file.
# This script sets up a new Ubuntu VM by cloning a template and configuring it with specific resources, network settings, and hostname, ensuring a seamless and automated provisioning process.


#!/bin/bash

# Variables
PROXMOX_HOST="your-proxmox-host"
PROXMOX_USER="root@pam"
TEMPLATE_ID="9000"        # ID of the Ubuntu template
NEW_VM_ID="9001"          # ID for the new VM
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
SSH_USER="ubuntu"
SSH_PUBLIC_KEY_PATH="~/.ssh/id_rsa.pub"

# Generate a unique machine ID
MACHINE_ID=$(uuidgen)

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
    --boot c --bootdisk scsi0 \
	--onboot 1 

# Start the new VM
qm start $NEW_VM_ID
EOF

# Wait for the VM to start
echo "Waiting for the VM to start..."
sleep 60

# Get the IP address assigned to the VM (assuming DHCP)
VM_IP=$(ssh $PROXMOX_USER@$PROXMOX_HOST "qm guest cmd $NEW_VM_ID network-get-interfaces" | jq -r '.[] | select(.name=="ens3") | ."ip-addresses"[0]."ip-address"')

# Wait for SSH to be available
until ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$VM_IP "echo SSH is ready"
do
  echo "Waiting for SSH to be ready..."
  sleep 10
done

# Final configuration inside the VM (e.g., setting up additional storage disk)
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $SSH_USER@$VM_IP <<EOF
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /mnt/storage
sudo mount /dev/sdb /mnt/storage
sudo bash -c 'echo "/dev/sdb /mnt/storage ext4 defaults 0 0" >> /etc/fstab'
EOF

# Clean up local files
rm cloud-init.iso user-data

echo "New Ubuntu VM has been created and configured successfully from the template."
