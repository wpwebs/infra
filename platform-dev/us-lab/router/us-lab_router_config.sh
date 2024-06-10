#!/bin/sh

# networksetup -setmanual Ethernet 192.168.1.9 255.255.255.0 0.0.0.0
# firstboot -y && reboot now
# ssh-keygen -R 192.168.1.1 && ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.1.1 -y
# ssh-keygen -R 192.168.1.1 && ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.1.1 'tee -a /etc/dropbear/authorized_keys' < /Users/henry/Drive/Personal/Henry/ssh_key/henry_ed25519.pub

# scp -O us-lab_router_config.sh root@192.168.1.1:
# sh us-lab_router_config.sh
# ========================================================
# Setup 
# Hardware: Dynalink DL-WRX36
# Software: OpenWrt 23.05.3
# ========================================================

configure_management(){
  # set hostname
  uci set system.@system[0].hostname='us-lab-router'
  uci commit

  # Apply the hashed password 
  HASHED_PASSWORD='$1$DBmWqRBc$Vjt129pJj0DaVhwnX0WO0/'
  sed -i "s|^root:[^:]*:|root:$HASHED_PASSWORD:|" /etc/shadow

  # Change timezone
  uci del system.ntp.enabled
  uci del system.ntp.enable_server
  uci set system.@system[0].zonename='America/Los Angeles'
  uci set system.@system[0].timezone='PST8PDT,M3.2.0,M11.1.0'
  uci set system.@system[0].log_proto='udp'
  uci set system.@system[0].conloglevel='8'
  uci set system.@system[0].cronloglevel='5'
  uci commit

  # Add schedule daily reboot at 4:30
  # cat >> /etc/crontabs/root << EOF
  # 30 4 * * * sleep 70 && touch /etc/banner && reboot
  # EOF
}

set_lan_interface(){
  # Change lan IP address
  uci set network.lan.ipaddr=$GATEWAY
  uci set network.lan.netmask='255.255.255.0'
  uci set network.lan.gateway=$GATEWAY
  uci set network.lan.dns=$GATEWAY
  uci commit
}

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
    if [ "$INTERFACE_NAME" = "networking" ]; then
      GATEWAY=$INTERFACE_IP
      IFS='.' read -r a b c d <<< "$GATEWAY"
      last_segment=$((d + 1))
      DNS_SERVERS="${a}.${b}.${c}.${last_segment}"
    elif [ "$INTERFACE_NAME" = "operations" ]; then
      WIFI_VLAN_ID=$VLAN_ID
    fi
  done

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
    uci set network.$INTERFACE_NAME.device="br-lan.${VLAN_ID}"
    uci set network.$INTERFACE_NAME.ipaddr="$INTERFACE_IP"
    uci set network.$INTERFACE_NAME.netmask="$INTERFACE_NETMASK"
    uci add_list network.$INTERFACE_NAME.dns="$DNS_SERVERS"
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

# Function to configure DNS settings
configure_dns() {
  # Change default DNS port on the router to 54
  uci set dhcp.@dnsmasq[0].port='54'
  
  # Set forward DNS servers to Google/Cloudflare DNS
  uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
  uci add_list dhcp.@dnsmasq[0].server='8.8.4.4'
  uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
  uci add_list dhcp.@dnsmasq[0].server='1.0.0.1'
  
  uci commit dhcp
}

# Function to configure DHCP for specific interfaces
configure_dhcp() {
  for interface in "${interfaces[@]}"; do
    IFS="|" read -r INTERFACE_NAME INTERFACE_IP INTERFACE_NETMASK VLAN_ID DNS_SERVERS <<< "$interface"
    
    # Configure DHCP server only for specific interfaces
    if [ "$INTERFACE_NAME" = "operations" ] || [ "$INTERFACE_NAME" = "pod_network" ] || [ "$INTERFACE_NAME" = "service_network" ]; then
      uci set dhcp.$INTERFACE_NAME=dhcp
      uci set dhcp.$INTERFACE_NAME.interface=$INTERFACE_NAME
      uci set dhcp.$INTERFACE_NAME.start='100'
      uci set dhcp.$INTERFACE_NAME.limit='150'
      uci set dhcp.$INTERFACE_NAME.leasetime='24h'  # Set lease time to 24 hours
      uci set dhcp.$INTERFACE_NAME.dhcpv6='disabled'
      uci set dhcp.$INTERFACE_NAME.ra='disabled'
      uci set dhcp.$INTERFACE_NAME.dns="$DNS_SERVERS"
      uci commit dhcp
    fi
  done
}

# Function to configure Wi-Fi
configure_wifi(){
  # REMOVE DEFAULT WIFI 
  uci del wireless.default_radio1
  uci del wireless.default_radio0
  uci commit

  # CREATE WIFI
  # Config radio, choosing non-overlapping channels, reducing interference
  uci set wireless.radio0.disabled='0'
  uci set wireless.radio0.channel='36'
  uci set wireless.radio0.htmode='HE160'
  uci set wireless.radio0.hwmode='11a'
  uci set wireless.radio0.txpower='30'
  uci set wireless.radio0.country='US'
  uci set wireless.radio0.cell_density='1'

  # Config SSID - use wifinet1
  uci set wireless.wifinet1=wifi-iface
  uci set wireless.wifinet1.device='radio0'
  uci set wireless.wifinet1.mode='ap'
  uci set wireless.wifinet1.ssid='us-lab'
  uci set wireless.wifinet1.encryption='sae-mixed'
  uci set wireless.wifinet1.key='WPWebs@us-lab'
  uci set wireless.wifinet1.network="br-lan.$WIFI_VLAN_ID"
  uci set wireless.wifinet1.disabled='0'
  # Disable radio1
  uci set wireless.radio1.disabled='1'

  uci commit wireless
  # wifi reload
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
    uci set network.@route[-1].gateway=$GATEWAY  
    uci commit network
  done
}

# Main Function
main() {
  configure_management
  set_lan_interface
  create_interfaces
  configure_dhcp
  configure_wifi
  configure_routing
  service network restart
  service firewall restart
  service dnsmasq restart
  echo "Configuration applied successfully."
}

# Execute main function
main
echo "Rebooting the Router..."
reboot
