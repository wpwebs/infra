#!/bin/sh

# networksetup -setmanual Ethernet 192.168.1.9 255.255.255.0 0.0.0.0
# firstboot -y && reboot now
# ssh-keygen -R 192.168.1.1 && ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.1.1 -y
# ssh-keygen -R 192.168.1.1
# ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@192.168.1.1 'tee -a /etc/dropbear/authorized_keys' < $HOME/.ssh/sshkey.pub

# scp -O us-lab_router_config.sh root@192.168.1.1:
# sh us-lab_router_config.sh
# ========================================================
# Setup Router at Region: Setup Management, Create VLAN, Create Interface, Create Firewall Zones, Configure DHCP, Firewall rules, Create routing 
# Hardware: Dynalink DL-WRX36
# Software: OpenWrt 23.05.3
# ========================================================

# Global variable for interfaces
INTERFACES="networking|192.168.0.1|255.255.255.128|100
proxmox|192.168.0.129|255.255.255.128|110
load_balancer|192.168.1.1|255.255.255.128|120
master_node|192.168.1.129|255.255.255.128|130
worker_node|192.168.2.1|255.255.255.128|140
storage_node|192.168.2.129|255.255.255.128|150
backup_node|192.168.3.1|255.255.255.128|160
operations|192.168.3.129|255.255.255.128|170
service_network|172.16.0.1|255.255.0.0|172
pod_network|10.0.0.1|255.255.0.0|10"

# Function to calculate DHCP start and limit based on IP and netmask
calculate_dhcp_range() {
  local ip=$1
  local netmask=$2
  local base_ip=${ip%.*}
  local last_octet=${ip##*.}

  if [ "$netmask" = "255.255.255.128" ]; then
    dhcp_start=$((last_octet + 1))
    dhcp_limit=126
  elif [ "$netmask" = "255.255.0.0" ]; then
    dhcp_start=$((last_octet + 1))
    dhcp_limit=10000
  else
    dhcp_start=$((last_octet + 1))
    dhcp_limit=150
  fi

  echo "$dhcp_start $dhcp_limit"
}

# Set global variables: GATEWAY and WIFI_VLAN_ID
while IFS="|" read -r INTERFACE_NAME INTERFACE_IP INTERFACE_NETMASK VLAN_ID; do
  if [ "$INTERFACE_NAME" = "networking" ]; then
    export GATEWAY=$INTERFACE_IP
    set -- $(echo "$GATEWAY" | tr '.' ' ')
    a=$1
    b=$2
    c=$3
    d=$4
    # last_segment=$((d + 1))
    last_segment=$((d + 0))
    export DNS_SERVER="${a}.${b}.${c}.${last_segment}"
  elif [ "$INTERFACE_NAME" = "operations" ]; then
    export WIFI_INTERFACE=$INTERFACE_NAME
  fi
done <<EOF
$INTERFACES
EOF

# Configure management settings
configure_management() {
  # Set hostname
  uci set system.@system[0].hostname='us-lab-router'
  uci commit system

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
  uci commit system

  # Add scheduled daily reboot at 4:30
  # echo "30 4 * * * sleep 70 && touch /etc/banner && reboot" >> /etc/crontabs/root
}

# Set LAN interface
set_lan_interface() {
  uci set network.lan.ipaddr=$GATEWAY
  uci set network.lan.netmask='255.255.255.128'
  # uci set dhcp.lan.ignore='1'
  uci commit network
}

# Set WAN interface
set_wan_interface() {
uci set network.wan=interface
uci set network.wan.proto='dhcp'
uci set network.wan.device='wan'
uci set firewall.@zone[1].name='wan'
uci del firewall.@zone[1].network
uci add_list firewall.@zone[1].network='wan'
uci add_list firewall.@zone[1].network='wan6'
uci set network.wan.defaultroute='1'
uci set network.wan.peerdns='1'
uci commit 
}


# Create interfaces, VLANs, firewall zones, and routing
create_interfaces() {
  
  echo "$INTERFACES" | while IFS="|" read -r INTERFACE_NAME INTERFACE_IP INTERFACE_NETMASK VLAN_ID; do
    # Create VLAN device
    echo -e "\nCreating VLAN ID: $VLAN_ID ..."

    if [ "$INTERFACE_NAME" = "networking" ]; then
      uci add network bridge-vlan
      uci set network.@bridge-vlan[-1].device='br-lan'
      uci set network.@bridge-vlan[-1].vlan=$VLAN_ID
      uci add_list network.@bridge-vlan[-1].ports='lan1:u*'
      uci add_list network.@bridge-vlan[-1].ports='lan2:u*'
      uci add_list network.@bridge-vlan[-1].ports='lan3:u*'
      uci add_list network.@bridge-vlan[-1].ports='lan4:u*'
    else
      uci add network bridge-vlan
      uci set network.@bridge-vlan[-1].device='br-lan'
      uci set network.@bridge-vlan[-1].vlan=$VLAN_ID
      uci add_list network.@bridge-vlan[-1].ports='lan1:t'
      uci add_list network.@bridge-vlan[-1].ports='lan2:t'
      uci add_list network.@bridge-vlan[-1].ports='lan3:t'
      uci add_list network.@bridge-vlan[-1].ports='lan4:t'
    fi

    # uci add network device
    # uci set network.@device[-1].name="br-lan.${VLAN_ID}"
    # uci set network.@device[-1].type='8021q'
    # uci set network.@device[-1].ifname='lan1'
    # uci set network.@device[-1].vid=$VLAN_ID
    uci commit network

    # Create VLAN interface
    echo -e "\nCreating interface: $INTERFACE_NAME ..."
    uci set network.$INTERFACE_NAME=interface
    uci set network.$INTERFACE_NAME.proto='static'
    uci set network.$INTERFACE_NAME.device="br-lan.${VLAN_ID}"
    uci set network.$INTERFACE_NAME.ipaddr="$INTERFACE_IP"
    uci set network.$INTERFACE_NAME.netmask="$INTERFACE_NETMASK"
    uci add_list network.$INTERFACE_NAME.dns="$DNS_SERVER"
    uci commit network

    # Create truncated firewall zone name
    FIREWALL_ZONE_NAME=$(echo "$INTERFACE_NAME" | cut -c1-6)
    FIREWALL_ZONE_NAME=${FIREWALL_ZONE_NAME}_ZONE

    # Create VLAN firewall zone
    echo -e "\nCreating firewall zone: ${FIREWALL_ZONE_NAME} ..."
    uci add firewall zone
    uci set firewall.@zone[-1].name="${FIREWALL_ZONE_NAME}"
    uci set firewall.@zone[-1].input='ACCEPT'
    uci set firewall.@zone[-1].output='ACCEPT'
    uci set firewall.@zone[-1].forward='ACCEPT'
    uci add_list firewall.@zone[-1].network=$INTERFACE_NAME
    uci commit firewall

    # Add forwarding between zones allow to access to Internet (optional, depends on your requirements)
    if [ "$INTERFACE_NAME" != "pod_network" ]|| [ "$INTERFACE_NAME" != "service_network" ]; then
      echo -e "\nAllowing ${FIREWALL_ZONE_NAME} access WAN ..."
      uci add firewall forwarding
      uci set firewall.@forwarding[-1].src="${FIREWALL_ZONE_NAME}"
      uci set firewall.@forwarding[-1].dest='wan'
      uci commit firewall
    fi

    # Add forwarding from operations to other zones if necessary
    if [ "$INTERFACE_NAME" = "operations" ]; then
      echo -e "\nAllowing operations zone to access other zones ..."
      for dest_zone in proxmox networking load_balancer master_node worker_node storage_node backup_node pod_network service_network; do
        # Create truncated firewall zone name
        dest_zone=$(echo "$dest_zone" | cut -c1-6)
        dest_zone_name=${dest_zone}_ZONE
        
        uci add firewall forwarding
        uci set firewall.@forwarding[-1].src="${FIREWALL_ZONE_NAME}"
        uci set firewall.@forwarding[-1].dest="${dest_zone_name}"
        uci commit firewall
      done
    fi
    
  done
}

# Configure DNS settings
configure_dns() {
  # uci set dhcp.@dnsmasq[0].port='54'
  uci add_list dhcp.@dnsmasq[0].server='8.8.8.8'
  uci add_list dhcp.@dnsmasq[0].server='8.8.4.4'
  uci add_list dhcp.@dnsmasq[0].server='1.1.1.1'
  uci add_list dhcp.@dnsmasq[0].server='1.0.0.1'
  uci commit dhcp
}

# Configure DHCP for specific interfaces
configure_dhcp() {
  echo "$INTERFACES" | while IFS="|" read -r INTERFACE_NAME INTERFACE_IP INTERFACE_NETMASK VLAN_ID; do
    # Calculate DHCP range based on IP and netmask
    dhcp_range=$(calculate_dhcp_range $INTERFACE_IP $INTERFACE_NETMASK)
    dhcp_start=$(echo $dhcp_range | cut -d' ' -f1)
    dhcp_limit=$(echo $dhcp_range | cut -d' ' -f2)

    if [ "$INTERFACE_NAME" = "operations" ]; then
      echo -e "\nConfigure DHCP on interface $INTERFACE_NAME ..."
      uci set dhcp.$INTERFACE_NAME=dhcp
      uci set dhcp.$INTERFACE_NAME.interface=$INTERFACE_NAME
      uci set dhcp.$INTERFACE_NAME.start=$dhcp_start
      uci set dhcp.$INTERFACE_NAME.limit=$dhcp_limit
      uci set dhcp.$INTERFACE_NAME.netmask=$INTERFACE_NETMASK
      uci add_list dhcp.$INTERFACE_NAME.dhcp_option="6,$DNS_SERVER"
      uci set dhcp.$INTERFACE_NAME.leasetime='24h'
      uci set dhcp.$INTERFACE_NAME.force_link='1'
      uci set dhcp.$INTERFACE_NAME.defaultroute='0'

      uci commit dhcp
    elif [ "$INTERFACE_NAME" = "pod_network" ] || [ "$INTERFACE_NAME" = "service_network" ]; then
      echo -e "\nConfigure DHCP on interface $INTERFACE_NAME ..."
      uci set dhcp.$INTERFACE_NAME=dhcp
      uci set dhcp.$INTERFACE_NAME.interface=$INTERFACE_NAME
      uci set dhcp.$INTERFACE_NAME.start=$dhcp_start
      uci set dhcp.$INTERFACE_NAME.limit=$dhcp_limit
      uci set dhcp.$INTERFACE_NAME.netmask=$INTERFACE_NETMASK
      uci add_list dhcp.$INTERFACE_NAME.dhcp_option="6,$DNS_SERVER"
      uci set dhcp.$INTERFACE_NAME.leasetime='24h'
      uci set dhcp.$INTERFACE_NAME.force_link='1'
      uci set dhcp.$INTERFACE_NAME.defaultroute='0'

      uci commit dhcp
    fi
  done
}

# Configure Wi-Fi
configure_wifi() {
  echo -e "\nConfigure Wi-Fi use VLAN ID: $WIFI_VLAN_ID ..."
  uci del wireless.default_radio1
  uci del wireless.default_radio0
  uci commit wireless

  uci set wireless.radio0.disabled='0'
  uci set wireless.radio0.channel='36'
  uci set wireless.radio0.htmode='HE160'
  uci set wireless.radio0.hwmode='11a'
  uci set wireless.radio0.txpower='30'
  uci set wireless.radio0.country='US'
  uci set wireless.radio0.cell_density='1'

  uci set wireless.wifinet1=wifi-iface
  uci set wireless.wifinet1.device='radio0'
  uci set wireless.wifinet1.mode='ap'
  uci set wireless.wifinet1.ssid='us-lab'
  uci set wireless.wifinet1.encryption='sae-mixed'
  uci set wireless.wifinet1.key='WPWebs@us-lab'
  uci set wireless.wifinet1.network="$WIFI_INTERFACE"

  uci set wireless.wifinet1.disabled='0'
  
  uci set wireless.radio1.disabled='1'
  uci commit wireless
}

# Configure routing
configure_routing() {
  echo "$INTERFACES" | while IFS="|" read -r INTERFACE_NAME INTERFACE_IP INTERFACE_NETMASK VLAN_ID; do
    echo -e "\nConfigure routing for interface $INTERFACE_NAME route to ${INTERFACE_IP%.*}.0 via gateway $GATEWAY ..."
    uci add network route
    uci set network.@route[-1].interface=$INTERFACE_NAME
    uci set network.@route[-1].target="${INTERFACE_IP%.*}.0"
    uci set network.@route[-1].netmask=$INTERFACE_NETMASK
    uci set network.@route[-1].gateway=$GATEWAY  
    uci commit network
  done
}

# Disable IP forwarding to improve security
disable_ip_forwarding() {
  echo "Disabling IP forwarding to improve security ..."
  echo "0" > /proc/sys/net/ipv4/ip_forward

  cat >> /etc/sysctl.conf << EOF
net.ipv4.ip_forward=0
EOF
}

# Main Function
main() {
  echo "Configuring router management ..."
  configure_management
  echo "Setting up LAN interface ..."
  set_lan_interface
  echo "Creating interfaces ..."
  create_interfaces
  echo "Configuring DNS ..."
  configure_dns
  echo "Configuring DHCP ..."
  configure_dhcp
  echo "Configuring Wi-Fi ..."
  configure_wifi
  echo "Configuring routing ..."
  configure_routing
  # echo "Disabling IP forwarding ..."
  # disable_ip_forwarding

  echo "Configuration applied successfully."

  echo "Restarting firewall ..."
  service firewall restart

  echo "Restarting dnsmasq ..."
  service dnsmasq restart

  echo "Restarting network ..."
  echo "Rebooting the router ..."
  service network restart
  reboot
}

# Execute main function
main
