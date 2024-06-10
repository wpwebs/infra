#!/bin/bash

# Variables
VM_NAME=${1-"pve1m1"}
VM_PATH="/Users/henry/proxmox/qemu/vms/$VM_NAME"

# Find the PID of the running VM
VM_PID=$(pgrep -f "qemu")

if [ -z "$VM_PID" ]; then
  echo "VM $VM_NAME is not running."
else
  echo "Stopping VM $VM_NAME (PID: $VM_PID)..."
  kill $VM_PID
  echo "VM $VM_NAME stopped."
fi
