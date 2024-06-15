#!/bin/bash

# Find the PID of the QEMU process
# Variables
NODE=${1-"1"}
VM_NAME=${2-"pve1$NODE"}

# Find the PIDs of the QEMU processes
PIDS=$(pgrep -f "qemu-system-x86_64.*-name $VM_NAME")

if [ -n "$PIDS" ]; then
  echo "Stopping VM with PIDs: $PIDS..."
  for PID in $PIDS; do
    kill -SIGTERM $PID
    echo "Sent SIGTERM to PID $PID"
  done
  echo "All related QEMU processes have been stopped."
else
  echo "No running VM processes found with name $VM_NAME."
fi
