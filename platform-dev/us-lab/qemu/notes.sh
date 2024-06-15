linux /boot/linux26 ro ramdisk_size=16777216 rw splash=verbose proxdebug set gfxpayload=800x600x16,800x600 loglevel=7 console=ttyS0


pve11.lan
enp0s4
192.168.0.11/25
192.168.0.1


cat  /etc/network/interfaces

auto lo
iface lo inet loopback

iface enp0s4 inet manual

auto vmbr0
iface vmbr0 inet static
	address 192.168.0.131/25
	gateway 192.168.0.129
	bridge-ports enp0s4
	bridge-stp off
	bridge-fd 0


source /etc/network/interfaces.d/*


/etc/network/interfaces

auto eth0
iface eth0 inet static
  address 192.168.0.${NODE}
  netmask 255.255.255.0
  gateway 192.168.0.1
  vlan-raw-device eth0
  vlan-id 110


# Inside the VM

cat  /etc/network/interfaces



sudo ifconfig bridge100 inet 192.168.0.129 netmask 255.255.255.128 up
sudo ifconfig bridge100 addm vlan1

sudo ifconfig vlan1 inet -alias
sudo ifconfig bridge100 inet 192.168.0.135 -alias


VLAN_ID=110
DEVICE_NAME=$(networksetup -listnetworkserviceorder | grep -A 1 "VLAN${VLAN_ID} Configuration" | grep -o 'Device: [^)]*' | awk '{print $2}')
NETWORK_SERVICE="VLAN$VLAN_ID Configuration"
sudo networksetup -setnetworkserviceenabled $NETWORK_SERVICE on
sudo networksetup -setnetworkserviceenabled $NETWORK_SERVICE off
sudo networksetup -setmanual $NETWORK_SERVICE 192.168.0.130 255.255.255.128 192.168.0.129




BRIDGE_NAME=bridge100
sudo ifconfig $BRIDGE_NAME addm $DEVICE_NAME

sudo ifconfig $BRIDGE_NAME inet 192.168.0.132 netmask 255.255.255.128 up

sudo ifconfig $BRIDGE_NAME inet -alias

sudo ifconfig $BRIDGE_NAME down >/dev/null
sudo ifconfig $BRIDGE_NAME destroy >/dev/null



# Check ARP Tables

# On macOS:
arp -a

# On Proxmox VM:
ip neigh

# Full Configuration Script
# Here’s a comprehensive script to configure the network on macOS and the VM:
# On macOS:

# Create and configure VLAN
sudo ifconfig vlan1 create
sudo ifconfig vlan1 vlan 110 vlandev en0
sudo ifconfig vlan1 inet 192.168.0.130 netmask 255.255.255.128 up

# Create and configure bridge
sudo ifconfig bridge100 create
sudo ifconfig bridge100 addm vlan1
sudo ifconfig bridge100 up

# Enable IP forwarding
sudo sysctl -w net.inet.ip.forwarding=1
echo "net.inet.ip.forwarding=1" | sudo tee -a /etc/sysctl.conf

# Configure NAT with PF
echo "
nat on en0 from 192.168.0.128/25 to any -> (en0)
" | sudo tee /etc/pf.conf

sudo pfctl -f /etc/pf.conf
sudo pfctl -e


# On Proxmox VM:

tee /etc/network/interfaces > /dev/null <<EOL
auto lo
iface lo inet loopback

iface enp0s4 inet manual

auto vmbr0
iface vmbr0 inet manual
    bridge_ports enp0s4
    bridge_stp off
    bridge_fd 0
    bridge_vlan_aware yes

auto vlan110
iface vlan110 inet static
    address 192.168.0.131/25
    gateway 192.168.0.129
    vlan-raw-device enp0s4
    vlan-id 110
EOL
systemctl restart networking

# Set DHCP client
tee /etc/network/interfaces > /dev/null <<EOL
auto lo
iface lo inet loopback

iface enp0s4 inet manual

auto vmbr0
iface vmbr0 inet manual
    bridge_ports enp0s4
    bridge_stp off
    bridge_fd 0
    bridge_vlan_aware yes

auto vlan110
iface vlan110 inet dhcp
    vlan-raw-device enp0s4
    vlan-id 110
EOL

# Restart networking to apply changes
systemctl restart networking



