#!/bin/bash

# Parent interface
PARENT_INTERFACE="en0" # Device: en0 / Hardware Port: Ethernet

# List of VLAN IDs
VLAN_IDs="100 110 120 130 140 150 160 170 172 10"
# VLAN_IDs="192 1281 1282 1283 1284 1285 1286 1287 1288 172 10"

# Create VLAN interfaces
for VLAN_ID in $VLAN_IDs; do
  VLAN=VLAN$VLAN_ID
  echo "Creating VLAN interface: $VLAN with VLAN ID: $VLAN_ID on interface: $PARENT_INTERFACE"
  sudo networksetup -deleteVLAN "$VLAN_NAME" "$PARENT_INTERFACE" "$VLAN_ID"
done
