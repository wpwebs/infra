#!/bin/bash

# Variables
VM_NAME=${1-"pve11"}
STORAGE=${2-"200G"}

VM_PATH="/Users/henry/proxmox/qemu/vms/$VM_NAME"

# Create the directory for the VM if it doesn't exist
mkdir -p "$VM_PATH/${VM_NAME}"

# Create the QCOW2 disk image
qemu-img create -f qcow2 "$VM_PATH/${VM_NAME}.qcow2" $STORAGE
