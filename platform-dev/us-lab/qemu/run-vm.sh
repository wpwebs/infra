#!/bin/bash

# Variables
VM_NAME=${1-"pve1m1"}

VM_PATH="/Users/henry/proxmox/qemu/vms/$VM_NAME"
IMG_PATH="$HOME/proxmox/img"
IMG_FILE="flatcar_production_qemu_uefi_image.img"
IGNITION_FILE="ignition-config.json"

CPU=4
RAM=8192
SSH_PORT=2222

VM_VLAN="172"
VM_IP="10.0.0.${NODE}00"
VM_GW="10.0.6.1"

HOSTNAME="$VM_NAME"
SSH_PUBLIC_KEY_PATH="/Users/henry/.ssh/ssh_key.pub"


# Generate a unique machine ID
MACHINE_ID=$(uuidgen)

# Generate Ignition config with SSH key and hostname
cat > $VM_PATH/${IGNITION_FILE} <<'EOF'
{
  "ignition": {
    "version": "3.0.0"
  },
  "passwd": {
    "users": [
      {
        "name": "core",
        "sshAuthorizedKeys": [
          "$(cat $SSH_PUBLIC_KEY_PATH)"
        ]
      }
    ]
  },
  "storage": {
    "files": [
      {
        "path": "/etc/hostname",
        "contents": {
          "source": "data:,${HOSTNAME}"
        },
        "mode": 420
      },
      {
        "path": "/etc/machine-id",
        "contents": {
          "source": "data:,${MACHINE_ID}"
        },
        "mode": 420
      }
    ]
  },
  "systemd": {
    "units": [
      {
        "name": "sshd.service",
        "enabled": true
      },
      {
        "name": "systemd-networkd.service",
        "enabled": true
      },
      {
        "name": "systemd-resolved.service",
        "enabled": true
      }
    ]
  }
}

EOF


qemu-system-aarch64 \
  -m $RAM \
  -cpu cortex-a72 \d
  -smp $CPU \
  -M virt \
  -bios /opt/homebrew/share/qemu/edk2-aarch64-code.fd \
  -nographic \
  -drive if=none,file="$VM_PATH/${VM_NAME}.qcow2",id=hd \
  -device virtio-blk-device,drive=hd \
  -netdev user,id=net0,hostfwd=tcp::$SSH_PORT-:22 \
  -device virtio-net-device,netdev=net0 \
  -drive if=none,file="$IMG_PATH/${IMG_FILE}",format=qcow2,id=cdrom \
  -device virtio-blk-device,drive=cdrom \
  -boot c \
  -fw_cfg name=opt/org.flatcar-linux/config,file=$VM_PATH/${IGNITION_FILE}
