#!/bin/bash

REMOTE_HOST=${1-"192.168.1.1"}
SSH_PUBLIC_KEY_PATH=${2-"$HOME/.ssh/sshkey.pub"}

disable_proxmox_subscription_message_remote() {
  REMOTE_HOST=$1

  SSH_CMD=$(cat <<'EOM'
JS_FILE="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
BACKUP_FILE="$JS_FILE.bak"

# Check if the JS_FILE file exists
if [[ ! -f $JS_FILE ]]; then
    echo "File $JS_FILE does not exist."
    exit 1
fi

# Backup the original file
cp $JS_FILE $BACKUP_FILE

# Apply the sed substitution
sed -Ezi.bak "s/(Ext.Msg.show\(\{\s+title: gettext\('No valid sub)/void\(\{ \/\/\1/g" $JS_FILE

if [[ $? -ne 0 ]]; then
    echo "Failed to modify $JS_FILE."
    exit 1
fi

# Restart the Proxmox Proxy service
systemctl restart pveproxy.service

if [[ $? -ne 0 ]]; then
    echo "Failed to restart pveproxy.service."
    exit 1
fi

# Confirm the change
grep -n -B 1 'No valid sub' "$JS_FILE"

exit 0
EOM
)

  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "root@${REMOTE_HOST}" "$SSH_CMD"
}

upload_sshkey() {
    echo -e "\nUploading public key at $SSH_PUBLIC_KEY_PATH to $REMOTE_HOST"
    ssh-keygen -R $REMOTE_HOST
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${REMOTE_HOST} \
        'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys' < $SSH_PUBLIC_KEY_PATH
}

boot_loader_configuration() {
    REMOTE_HOST=$1
    echo -e "\nExecuting package update on remote server $REMOTE_HOST"

    SSH_CMD=$(cat <<'EOM'
# Check if system is in UEFI mode
if [ -d /sys/firmware/efi ]; then
  echo "System is in UEFI mode."
  
  # Identify the EFI partition
  EFI_PARTITION=$(lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINT | grep -i "vfat" | awk '{print $1}')
  if [ -z "$EFI_PARTITION" ]; then
    echo "EFI partition not found."
    exit 1
  fi
  EFI_PARTITION="/dev/$EFI_PARTITION"
  
  # Mount the EFI partition
  echo "Mounting EFI partition ($EFI_PARTITION)..."
  mkdir -p /boot/efi
  mount $EFI_PARTITION /boot/efi
fi

# Update and upgrade packages
echo "Updating and upgrading packages..."
apt-get update
apt-get upgrade -y

# Run the zz-proxmox-boot script if in UEFI mode
if [ -d /sys/firmware/efi ]; then
  echo "Running zz-proxmox-boot script..."
  /etc/kernel/postinst.d/zz-proxmox-boot --esp-path=/boot/efi
fi

echo "Script execution finished successfully."
EOM
)
    
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$REMOTE_HOST "$SSH_CMD"
}

update() {
    REMOTE_HOST=$1
    echo -e "\nExecuting update packages on remote server $REMOTE_HOST"
    SSH_CMD=$(cat <<'EOM'
# Disable Proxmox Enterprise repository
sed -i 's|deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise|#deb https://enterprise.proxmox.com/debian/pve bookworm pve-enterprise|' /etc/apt/sources.list.d/pve-enterprise.list

# Remove Ceph Quincy enterprise repository
sed -i '/ceph-quincy/d' /etc/apt/sources.list.d/pve-enterprise.list
# Remove Ceph Quincy enterprise repository and any other references to enterprise.proxmox.com
find /etc/apt -type f -name '*.list' -exec sed -i '/enterprise.proxmox.com/d' {} \;

# Add Proxmox no-subscription repository
echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" | tee /etc/apt/sources.list.d/pve-no-subscription.list

# Set the timezone to Pacific Time
timedatectl set-timezone America/Los_Angeles

# Install and configure chrony
apt-get update
apt-get install -y chrony
systemctl enable chrony --now
chronyc -a makestep

# Ensure time is set correctly
chronyc tracking

# Update package lists and upgrade packages
apt-get update && apt-get upgrade -y || echo "Retrying after fixing time"
apt-get update && apt-get upgrade -y
EOM
)
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@${REMOTE_HOST} "$SSH_CMD"
}



main() {
    # Upload sshkey to remote server
    upload_sshkey $REMOTE_HOST $SSH_PUBLIC_KEY_PATH

    # Disable the "No valid subscription" message in Proxmox VE 
    disable_proxmox_subscription_message_remote $REMOTE_HOST

    # updating the boot loader configuration
    boot_loader_configuration $REMOTE_HOST

    # Remote update packages
    update $REMOTE_HOST
}

# Execute main function
main
