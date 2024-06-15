#!/bin/bash

# Variables
NODE=${1:-"1"}
OS_DISK_SIZE=${2:-"32G"}
SSD_DISK_SIZE=${3:-"50G"}
SAS_DISK_SIZE=${4:-"100G"}
VM_NAME="pve1$NODE"

VM_BASE_PATH="/Users/henry/infra/platform-dev/us-lab"
VM_PATH="$VM_BASE_PATH/qemu/vms/$VM_NAME"

# Create the directory for the VM if it doesn't exist
if [ -d "$VM_PATH" ]; then
  echo -e "\nRemoving existing VM directory..."
  rm -rf "$VM_PATH"
fi
echo -e "\nCreating VM directory..."
mkdir -p "$VM_PATH"

# Create the QCOW2 disk images
echo "Creating OS disk image..."
qemu-img create -f qcow2 "$VM_PATH/${VM_NAME}_os.qcow2" $OS_DISK_SIZE

echo "Creating SSD disk image..."
qemu-img create -f qcow2 "$VM_PATH/${VM_NAME}_ssd.qcow2" $SSD_DISK_SIZE

echo "Creating SAS disk image..."
qemu-img create -f qcow2 "$VM_PATH/${VM_NAME}_sas.qcow2" $SAS_DISK_SIZE

echo "Disk images created at $VM_PATH"
