#!/bin/bash

# Variables
NODE=${1-"1"}
VM_NAME="pve1$NODE"

CPU=2
RAM=8192

VM_BASE_PATH="/Users/henry/infra/platform-dev/us-lab"
VM_PATH="$VM_BASE_PATH/qemu/vms/$VM_NAME"
IMG_PATH="$VM_BASE_PATH/img"
IMG_FILE="proxmox-ve_8.2-1.iso"

# Check if required files exist
if [ ! -f "$IMG_PATH/$IMG_FILE" ]; then
  echo "Image file not found: $IMG_PATH/$IMG_FILE"
  exit 1
fi

# Generate a random MAC address with the prefix 52:54:00
generate_mac() {
    printf '52:54:00:%02x:%02x:%02x\n' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))
}

MAC_ADDRESS=$(generate_mac)

# Function to start the VM
start_vm() {
  sudo qemu-system-x86_64 \
    -name "$VM_NAME" \
    -m "$RAM" \
    -smp "$CPU" \
    -M q35 \
    -accel hvf \
    -cpu host \
    -nographic \
    -drive if=none,file="$VM_PATH/${VM_NAME}_os.qcow2",id=os_disk \
    -device virtio-blk-pci,drive=os_disk \
    -drive if=none,file="$VM_PATH/${VM_NAME}_ssd.qcow2",id=ssd_disk \
    -device virtio-blk-pci,drive=ssd_disk \
    -drive if=none,file="$VM_PATH/${VM_NAME}_sas.qcow2",id=sas_disk \
    -device virtio-blk-pci,drive=sas_disk \
    -netdev vmnet-shared,id=net0 \
    -device virtio-net-pci,netdev=net0,mac="$MAC_ADDRESS" \
    -drive file="$IMG_PATH/$IMG_FILE",media=cdrom \
    -boot order=c
}
