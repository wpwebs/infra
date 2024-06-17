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
# The loopback network interface
auto lo
iface lo inet loopback

# Bonding interface
auto bond0
iface bond0 inet static
	bond-slaves enp2s0 enp0s31f6
	bond-mode active-backup
	bond-miimon 100
	bond-primary enp2s0

# VLAN-aware bridge
auto vmbr0
iface vmbr0 inet static
	address 192.168.0.151
	netmask 255.255.255.128
	gateway 192.168.0.129
	dns-nameservers 192.168.0.129
	bridge-ports bond0
	bridge-stp off
	bridge-fd 0
	bridge-vlan-aware yes

# Interface $INTERFACE1
allow-hotplug enp2s0
iface enp2s0 inet manual
	bond-master bond0

# Interface $INTERFACE2
allow-hotplug enp0s31f6
iface enp0s31f6 inet manual
	bond-master bond0

source /etc/network/interfaces.d/*

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
