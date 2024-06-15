#!/bin/sh

# scp -O upgrade_packages.sh root@192.168.1.254:
service adguardhome stop

uci set dhcp.@dnsmasq[0].port='53'
service dnsmasq restart

# Step 1: Update the package list
echo "Updating package list..."
opkg update

# Step 2: List and upgrade all upgradable packages
echo "Upgrading all packages..."
opkg list-upgradable | cut -f 1 -d ' ' | xargs -r opkg upgrade

uci set dhcp.@dnsmasq[0].port='54'
service dnsmasq restart
service adguardhome enable
service adguardhome start

echo "Package upgrade completed."