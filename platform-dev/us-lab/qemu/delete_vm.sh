#!/bin/bash

# Variables
NODE=${1-"1"}
VM_NAME="pve1$NODE"
VM_BASE_PATH="/Users/henry/infra/platform-dev/us-lab"
VM_PATH="$VM_BASE_PATH/qemu/vms/$VM_NAME"

# Stop the VM if it is running
VM_PID=$(pgrep -f "qemu.*$VM_NAME")
if [ -n "$VM_PID" ]; then
  echo "Stopping VM $VM_NAME (PID: $VM_PID)..."
  kill $VM_PID
  echo "VM $VM_NAME stopped."
else
  echo "VM $VM_NAME is not running."
fi

# Delete the VM storage and configuration
if [ -d "$(dirname "$VM_PATH")" ]; then
  echo "Deleting VM storage and configuration for $VM_NAME..."
  rm -rf "$VM_PATH.qcow2" "$VM_PATH"
  echo "VM $VM_NAME deleted."
else
  echo "VM storage path $(dirname "$VM_PATH") does not exist."
fi
