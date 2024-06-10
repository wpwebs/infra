#!/bin/sh

# Function to create interfaces, VLANs, firewall zones, and routing
create_interfaces() {
  # Define the interface configurations
  interfaces=(
    "proxmox|192.168.0.1|255.255.255.0|192"
    "networking|128.0.1.1|255.255.255.0|1281"
    "load_balancer|128.0.2.1|255.255.255.0|1282"
    "master_node|128.0.3.1|255.255.255.0|1283"
    "worker_node|128.0.4.1|255.255.255.0|1284"
    "storage_node|128.0.5.1|255.255.255.0|1285"
    "backup_node|128.0.6.1|255.255.255.0|1286"
    "management|128.0.7.1|255.255.255.0|1287"
    "operations|128.0.8.1|255.255.255.0|1288"
    "pod_network|172.0.0.1|255.255.0.0|172"
    "service_network|10.0.0.1|255.255.0.0|10"
  )

  for interface in "${interfaces[@]}"; do
    IFS="|" read -r INTERFACE_NAME INTERFACE_IP INTERFACE_NETMASK VLAN_ID <<< "$interface"
    
    # Create VLAN device
    uci add network bridge-vlan
    uci set network.@bridge-vlan[-1].device='br-lan'
    uci set network.@bridge-vlan[-1].vlan=$VLAN_ID
    uci add_list network.@bridge-vlan[-1].ports='lan1:u*'
    uci add_list network.@bridge-vlan[-1].ports='lan2:t'
    uci add_list network.@bridge-vlan[-1].ports='lan3:t'
    uci add_list network.@bridge-vlan[-1].ports='lan4:t'
    uci commit network

    # Create VLAN interface
    uci set network.$INTERFACE_NAME=interface
    uci set network.$INTERFACE_NAME.proto='static'
    uci set network.$INTERFACE_NAME.device="eth0.${VLAN_ID}"
    uci set network.$INTERFACE_NAME.ipaddr="$INTERFACE_IP"
    uci set network.$INTERFACE_NAME.netmask="$INTERFACE_NETMASK"
    uci commit network

    # Create VLAN firewall zone
    uci add firewall zone
    uci set firewall.@zone[-1].name="${INTERFACE_NAME}_z"
    uci set firewall.@zone[-1].input='ACCEPT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].forward='ACCEPT'
    uci add_list firewall.@zone[-1].network=$INTERFACE_NAME
    uci commit firewall

    # Add forwarding between zones (optional, depends on your requirements)
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].src="${INTERFACE_NAME}_z"
    uci set firewall.@forwarding[-1].dest='wan'
    uci commit firewall
  done
}

# Function to configure DHCP
configure_dhcp() {
  for interface in "${interfaces[@]}"; do
    IFS="|" read -r INTERFACE_NAME INTERFACE_IP INTERFACE_NETMASK VLAN_ID <<< "$interface"
    
    # Configure DHCP server
    uci set dhcp.$INTERFACE_NAME=dhcp
    uci set dhcp.$INTERFACE_NAME.interface=$INTERFACE_NAME
    uci set dhcp.$INTERFACE_NAME.start='100'
    uci set dhcp.$INTERFACE_NAME.limit='150'
    uci set dhcp.$INTERFACE_NAME.leasetime='12h'
    uci set dhcp.$INTERFACE_NAME.dhcpv6='disabled'
    uci set dhcp.$INTERFACE_NAME.ra='disabled'
    uci commit dhcp
  done
}

# Function to configure routing
configure_routing() {
  for interface in "${interfaces[@]}"; do
    IFS="|" read -r INTERFACE_NAME INTERFACE_IP INTERFACE_NETMASK VLAN_ID <<< "$interface"
    
    # Add static routes
    uci add network route
    uci set network.@route[-1].interface=$INTERFACE_NAME
    uci set network.@route[-1].target="${INTERFACE_IP%.*}.0"
    uci set network.@route[-1].netmask=$INTERFACE_NETMASK
    uci set network.@route[-1].gateway='128.0.1.1'  # Change this to your actual gateway
    uci commit network
  done
}

# Main Function
main() {
  create_interfaces
  configure_dhcp
  configure_routing
  /etc/init.d/network restart
  /etc/init.d/firewall restart
  /etc/init.d/dnsmasq restart
  echo "Configuration applied successfully."
}

# Execute main function
main
