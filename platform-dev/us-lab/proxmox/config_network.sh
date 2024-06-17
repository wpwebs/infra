#!/bin/bash

# List of remote nodes
NODES=("192.168.0.131" "192.168.0.132" "192.168.0.133")
SUBNET="/25"
GATEWAY="192.168.0.129"
DNS="192.168.0.129"
# Network interfaces to bond
INTERFACE1="enp0s5"
INTERFACE2="eth0"
# SSH user
SSH_USER="root"

# Function to install necessary packages on a remote node
install_packages() {
  local node=$1
  echo "Installing ifenslave package on $node..."
  ssh "$SSH_USER@$node" "apt-get update && apt-get install -y ifenslave"
  echo "Package installation completed on $node."
}

# Function to configure network interfaces on a remote node
configure_interfaces() {
  local node=$1
  local node_ip=$(echo $node | awk -F. '{print $1"."$2"."$3"."$4}')

  echo "Configuring network interfaces on $node..."

  ssh "$SSH_USER@$node" bash -c "'
    echo \"Backing up current interfaces file...\"
    cp /etc/network/interfaces /etc/network/interfaces.bak
    echo \"Backup completed. Configuring network interfaces...\"

    cat <<EOL > /etc/network/interfaces
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# Bonding interface
auto bond0
iface bond0 inet static
  address $node_ip$SUBNET
  netmask 255.255.255.128  # Adjust according to the subnet mask
  gateway $GATEWAY
  dns-nameservers $DNS
  bond-slaves $INTERFACE1 $INTERFACE2
  bond-mode active-backup
  bond-miimon 100
  bond-primary $INTERFACE1

# VLAN-aware bridge
auto vmbr0
iface vmbr0 inet manual
  bridge_ports bond0
  bridge_stp off
  bridge_fd 0
  bridge_vlan_aware yes

# Interface $INTERFACE1
allow-hotplug $INTERFACE1
iface $INTERFACE1 inet manual
  bond-master bond0

# Interface $INTERFACE2
allow-hotplug $INTERFACE2
iface $INTERFACE2 inet manual
  bond-master bond0
EOL

    echo \"Network interfaces configured on $node.\"

    echo \"Configuring DNS settings...\"
    echo \"nameserver $DNS\" > /etc/resolv.conf
    echo \"DNS settings configured on $node.\"
  '"
}

# Function to bring up the network interfaces on a remote node
bring_up_interfaces() {
  local node=$1
  echo "Bringing up network interfaces on $node..."
  ssh "$SSH_USER@$node" "ifdown $INTERFACE1 $INTERFACE2 bond0 vmbr0 && ifup bond0 vmbr0"
  echo "Network interfaces are up on $node."
}

# Main function
main() {
  for node in "${NODES[@]}"; do
    install_packages "$node"
    configure_interfaces "$node"
    bring_up_interfaces "$node"
    echo "VLAN-aware bridge configuration completed on $node."
  done
}

# Execute main function
main
