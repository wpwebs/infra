# Script to Create Debian 12 Template on Proxmox Using Debian Cloud Image

# Explanation
# 1. Download Debian Cloud Image: The script fetches the Debian 12 cloud image and downloads it.
# 2. Upload Cloud Image to Proxmox: The script uploads the downloaded QCOW2 image to the Proxmox server.
# 3. Create VM: The script creates a VM on Proxmox using the uploaded QCOW2 image, with specified CPU cores, RAM, and SSH keys.
# 4. Import Disk: The script imports the downloaded QCOW2 image as a disk for the VM and sets it as the boot disk.
# 5. Configure Cloud-Init: The script sets up a cloud-init drive for the VM.
# 6. Start VM: The script starts the VM.
# 7. Install qemu-guest-agent and Clear Machine ID: The script SSHs into the VM to install the qemu-guest-agent, enable it, and clear the machine ID to ensure it is unique.
# 8. Reboot VM: The script reboots the VM to apply the changes.
# 9. Convert to Template: After verifying the VM has rebooted and SSH is available, the script stops the VM and converts it into a template.
# 10. Clean Up: The script cleans up the local QCOW2 image after the template is created.
# Notes
# * Automation: The script automates the setup process using the Debian cloud image, making it efficient and reducing manual steps.
# * Variables: Ensure you replace placeholder values such as your-proxmox-host, and other specific configuration details with your actual Proxmox server details and network configuration.
# * SSH Key Path: Update the SSH_PUBLIC_KEY_PATH variable with the path to your SSH public key file.
# * CPU and RAM: The script allows you to define the number of CPU cores and the amount of RAM for the VM.
# This script sets up a Debian 12 template VM on Proxmox, providing the necessary steps for automated installation and ensuring the template is ready for future cloning with defined CPU and RAM settings, SSH key configuration, qemu-guest-agent installation, and a unique machine ID.

#!/bin/bash

# Variables
PROXMOX_HOST="your-proxmox-host"
PROXMOX_USER="root@pam"
STORAGE_NAME="local-lvm"
ISO_STORAGE="local"
VM_ID="9000"
VM_NAME="debian-template"
VM_VLAN="100"
VM_VMIP="192.168.1.100"
VM_VMGW="192.168.1.1"
VM_USER="debian"

DEBIAN_CLOUD_IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
QCOW2_IMAGE="debian-12-generic-amd64.qcow2"
SSH_PUBLIC_KEY_PATH="~/.ssh/ssh_id.pub"
CPU_CORES=2
RAM_MB=2048
DISK_SIZE=32


# Download the Debian 12 cloud image
curl -L $DEBIAN_CLOUD_IMAGE_URL -o $QCOW2_IMAGE

# Upload the cloud image to Proxmox
scp $QCOW2_IMAGE $PROXMOX_USER@$PROXMOX_HOST:/var/lib/vz/template/qemu/

# Create VM
ssh $PROXMOX_USER@$PROXMOX_HOST <<EOF
qm create $VM_ID \
    --name $VM_NAME \
    --memory $RAM_MB \
    --cores $CPU_CORES \
    --net0 virtio,bridge=vmbr0,tag=$VM_VLAN \
    --ipconfig0 ip=$VM_IP/24,gw=$VM_GW \
    --scsihw virtio-scsi-pci \
    --scsi0 $STORAGE_NAME:$DISK_SIZE \
    --serial0 socket \
    --vga serial0 \
    --machine q35 \
    --sshkeys $SSH_PUBLIC_KEY_PATH

qm importdisk $VM_ID /var/lib/vz/template/qemu/$QCOW2_IMAGE $STORAGE_NAME
qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE_NAME:vm-$VM_ID-disk-0
qm set $VM_ID --boot c --bootdisk scsi0

# Configure cloud-init drive
qm set $VM_ID --ide2 $STORAGE_NAME:cloudinit

# Set the VM to use cloud-init and start it
qm set $VM_ID --serial0 socket --vga serial0 --boot c --bootdisk scsi0 --ide2 $STORAGE_NAME:cloudinit
qm set $VM_ID --ipconfig0 ip=dhcp
qm start $VM_ID
EOF

# Wait for the VM to start
echo "Waiting for the VM to start..."
sleep 60

# SSH into the VM to install qemu-guest-agent and clear machine-id
ssh $PROXMOX_USER@$PROXMOX_HOST <<EOF
# Get the VM IP address from Proxmox API
VM_IP=\$(qm guest cmd $VM_ID network-get-interfaces | jq -r '.[] | select(.name=="ens3") | ."ip-addresses"[0]."ip-address"')

# Wait for SSH to be available
until ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_USER@\${VM_IP} "echo SSH is ready"
do
  echo "Waiting for SSH to be ready..."
  sleep 10
done

# Install qemu-guest-agent and clear machine-id
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_USER@\${VM_IP} <<'EOC'
sudo apt-get update && sudo apt-get install -y qemu-guest-agent
sudo systemctl enable qemu-guest-agent --now
sudo truncate -s 0 /etc/machine-id
sudo rm /var/lib/dbus/machine-id
sudo ln -fs /etc/machine-id /var/lib/dbus/machine-id
sudo reboot
EOC
EOF

# Wait for the VM to reboot and verify SSH access again
echo "Waiting for the VM to reboot..."
sleep 60

ssh $PROXMOX_USER@$PROXMOX_HOST <<EOF
# Wait for SSH to be available after reboot
until ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $VM_USER@\${VM_IP} "echo SSH is ready"
do
  echo "Waiting for SSH to be ready..."
  sleep 10
done

# Stop the VM and convert it to a template
qm stop $VM_ID
qm template $VM_ID
EOF

# Clean up local files
rm $QCOW2_IMAGE

echo "Debian 12 template has been created successfully on Proxmox with SSH key, qemu-guest-agent, and unique machine-id."
