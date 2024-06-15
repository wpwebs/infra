#!/bin/bash

# Variables
NODES=("pve11" "pve12" "pve13")
IPS=("192.168.0.131" "192.168.0.132" "192.168.0.133")
NTP_SERVER="pool.ntp.org" # You can change this to your preferred NTP server
TIMEZONE="America/Los_Angeles" # Time zone for PDT

# Function to install and configure chrony for time synchronization
install_and_configure_chrony() {
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${IPS[$i]}"
        echo "Installing and configuring chrony on $node ($ip) for time synchronization"

        ssh root@$ip <<EOF
        set -e
        apt-get update && apt-get install -y chrony

        # Backup the original chrony configuration file
        cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak

        # Configure chrony to use the specified NTP server
        sed -i 's/^pool .*/pool $NTP_SERVER iburst/' /etc/chrony/chrony.conf

        # Restart the chrony service to apply the changes
        systemctl restart chrony

        # Enable the chrony service to start on boot
        systemctl enable chrony

        # Verify the time synchronization status
        chronyc tracking
EOF

        if [ $? -ne 0 ]; then
            echo "Failed to install and configure chrony on $node ($ip)"
            exit 1
        fi
    done
}

# Function to set the time zone on all nodes
set_time_zone() {
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${IPS[$i]}"
        echo "Setting time zone to $TIMEZONE on $node ($ip)"

        ssh root@$ip <<EOF
        set -e
        timedatectl set-timezone $TIMEZONE
        timedatectl
EOF

        if [ $? -ne 0 ]; then
            echo "Failed to set time zone on $node ($ip)"
            exit 1
        fi
    done
}

# Function to force time synchronization on all nodes
force_time_sync() {
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${IPS[$i]}"
        echo "Forcing time synchronization on $node ($ip)"

        ssh root@$ip <<EOF
        set -e
        chronyc -a makestep
EOF

        if [ $? -ne 0 ]; then
            echo "Failed to force time synchronization on $node ($ip)"
            exit 1
        fi
    done
}

# Main script execution
install_and_configure_chrony
set_time_zone
force_time_sync

echo "Time synchronization setup and time zone configuration completed on all nodes."
