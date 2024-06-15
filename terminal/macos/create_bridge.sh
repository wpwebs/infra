#!/bin/bash

# Variables
PARENT_INTERFACE="en0" # Device: en0 / Hardware Port: Ethernet
# List of VLAN IDs
VLAN_IDs="100 110 120 130 140 150 160 170 172 10"
BRIDGE_NAME=${1-"bridge1"}

# Function to get the device name associated with a VLAN ID
get_vlan_device_name() {
  local VLAN_ID=$1
  local DEVICE_NAME

  DEVICE_NAME=$(networksetup -listnetworkserviceorder | grep -A 1 "VLAN${VLAN_ID} Configuration" | grep -o 'Device: [^)]*' | awk '{print $2}')
  
  if [ -z "$DEVICE_NAME" ]; then
    echo "No device found for VLAN ID ${VLAN_ID}" >&2
    return 1
  else
    echo "$DEVICE_NAME"
  fi
}

echo "Deleting bridge $BRIDGE_NAME if exists ..."
sudo ifconfig $BRIDGE_NAME down >/dev/null
sudo ifconfig $BRIDGE_NAME destroy >/dev/null

echo -e "\nCreating bridge interface $BRIDGE_NAME ..."
sudo ifconfig $BRIDGE_NAME create

# Create VLAN interfaces if they don't exist and add to bridge
for VLAN_ID in $VLAN_IDs; do
  VLAN_NAME="VLAN${VLAN_ID}"
  echo -e "\nDeleting existing VLAN interface $VLAN_NAME if exists ..."
  sudo networksetup -deleteVLAN "$VLAN_NAME" "$PARENT_INTERFACE" "$VLAN_ID" >/dev/null
  echo "Creating VLAN interface: $VLAN_NAME with VLAN ID: $VLAN_ID on interface: $PARENT_INTERFACE"
  sudo networksetup -createVLAN "$VLAN_NAME" "$PARENT_INTERFACE" "$VLAN_ID"

  echo "Adding $VLAN_NAME to $BRIDGE_NAME"
  DEVICE_NAME=$(get_vlan_device_name $VLAN_ID)
  sudo ifconfig $BRIDGE_NAME addm $DEVICE_NAME
done

# Bring Up VLAN Interface
echo -e "\nBringing up bridge interface $BRIDGE_NAME"
sudo ifconfig $BRIDGE_NAME up


# Verify Configuration
echo "Verifying configuration:"
ifconfig $BRIDGE_NAME
for VLAN_ID in $VLAN_IDs; do
  VLAN_NAME="VLAN${VLAN_ID}"
  DEVICE_NAME=$(get_vlan_device_name $VLAN_ID)
  ifconfig $DEVICE_NAME
done
