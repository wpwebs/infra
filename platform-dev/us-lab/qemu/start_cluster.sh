#!/bin/bash

# Function to generate a random MAC address with the prefix 52:54:00
generate_mac() {
    printf '52:54:00:%02x:%02x:%02x\n' $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))
}

# Function to start a VM
start_vm() {
    local NODE=${1:-"1"}
    local VM_NAME="pve1$NODE"
    local CPU=2
    local RAM=8192
    local VM_BASE_PATH="/Users/henry/infra/platform-dev/us-lab"
    local VM_PATH="$VM_BASE_PATH/qemu/vms/$VM_NAME"
    local IMG_PATH="$VM_BASE_PATH/img"
    local IMG_FILE="proxmox-ve_8.2-1.iso"

    # Check if required files exist
    if [ ! -f "$IMG_PATH/$IMG_FILE" ]; then
        echo "Image file not found: $IMG_PATH/$IMG_FILE"
        exit 1
    fi

    local MAC_ADDRESS=$(generate_mac)

    # Start the VM in the background
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
        -boot order=c &
}

# Loop to start VMs in the background
for i in {1..3}; do
    echo -e "\nStarting node $i ..."
    start_vm $i
done

# Wait for the VMs to start
sleep 30

# Add en0 to bridge100
echo -e "\nAdding en0 to bridge100."
sudo ifconfig bridge100 addm en0