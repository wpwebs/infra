#!/bin/sh

# Define variables
BACKUP_PATH="/tmp/backup.tar.gz"
FIRMWARE_URL="https://downloads.openwrt.org/releases/X.Y.Z/targets/your-target/your-device/openwrt-X.Y.Z-your-device-squashfs-sysupgrade.bin"
CHECKSUM_URL="https://downloads.openwrt.org/releases/X.Y.Z/targets/your-target/sha256sums"
FIRMWARE_FILE="/tmp/openwrt-X.Y.Z-your-device-squashfs-sysupgrade.bin"

# Step 1: Backup Configuration
echo "Backing up current configuration..."
sysupgrade -b $BACKUP_PATH
scp $BACKUP_PATH user@your-pc:/path/to/backup/

# Step 2: Download the latest firmware
echo "Downloading the latest firmware..."
cd /tmp
wget $FIRMWARE_URL

# Step 3: Verify the downloaded firmware
echo "Verifying the firmware checksum..."
wget $CHECKSUM_URL
sha256sum -c sha256sums 2>&1 | grep $(basename $FIRMWARE_FILE)

# Step 4: Perform the upgrade
echo "Upgrading firmware..."
sysupgrade $FIRMWARE_FILE

# Note: The device will automatically reboot after this step

# Optionally, restore the configuration if needed (after rebooting)
# echo "Restoring configuration..."
# scp user@your-pc:/path/to/backup/backup.tar.gz /tmp/backup.tar.gz
# sysupgrade -r /tmp/backup.tar.gz

echo "Upgrade completed."
