#!/bin/bash

# Variables
NODES=("pve11" "pve12" "pve13")
IPS=("192.168.0.131" "192.168.0.132" "192.168.0.133")
SSD_DISK="/dev/vdb" # Disk for SSD storage
SAS_DISK="/dev/vdc" # Disk for SAS storage
MASTER_IP="${IPS[0]}"
SSH_USER="root"
CEPHADM_USER="cephadm"
CEPHADM_PASS="password"

# Function to create the cephadm user and home directory
create_cephadm_user() {
    for ip in "${IPS[@]}"; do
        echo "Creating cephadm user on $ip"

        ssh $SSH_USER@$ip <<EOF
        set -e
        if ! getent group $CEPHADM_USER > /dev/null 2>&1; then
            groupadd $CEPHADM_USER
        fi
        if ! id -u $CEPHADM_USER > /dev/null 2>&1; then
            useradd -m -d /home/$CEPHADM_USER -s /bin/bash -g $CEPHADM_USER $CEPHADM_USER
            echo "$CEPHADM_USER:$CEPHADM_PASS" | chpasswd
        fi
        mkdir -p /home/$CEPHADM_USER/.ssh
        chown -R $CEPHADM_USER:$CEPHADM_USER /home/$CEPHADM_USER
        echo "$CEPHADM_USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$CEPHADM_USER
        chmod 0440 /etc/sudoers.d/$CEPHADM_USER
EOF

        if [ $? -ne 0 ]; then
            echo "Failed to create cephadm user on $ip"
            exit 1
        fi
    done
}

# Function to install cephadm and required packages
install_cephadm() {
    for ip in "${IPS[@]}"; do
        echo "Installing cephadm on $ip"

        ssh $SSH_USER@$ip <<EOF
        set -e
        apt-get update && apt-get install -y curl gnupg lsb-release sudo
        curl --silent --remote-name --location https://github.com/ceph/ceph/raw/pacific/src/cephadm/cephadm
        chmod +x cephadm
        mv cephadm /usr/local/bin/
        chown -R $CEPHADM_USER:$CEPHADM_USER /usr/bin/ceph
        echo "deb https://download.ceph.com/debian-pacific bullseye main" > /etc/apt/sources.list.d/ceph.list
        curl --silent https://download.ceph.com/keys/release.asc | apt-key add -
        apt-get update

        # Install cephadm package
        DEBIAN_FRONTEND=noninteractive apt-get install -y cephadm
EOF

        if [ $? -ne 0 ]; then
            echo "Failed to install cephadm on $ip"
            exit 1
        fi
    done
}

# Function to set up SSH keys manually
setup_ssh_keys() {
    for ip in "${IPS[@]}"; do
        echo "Setting up SSH keys on $ip"

        ssh $SSH_USER@$ip <<EOF
        set -e
        if [ ! -f /etc/ceph/ceph.pub ]; then
            ssh-keygen -t ed25519 -N "" -f /etc/ceph/ceph
        fi
        PUB_KEY=\$(cat /etc/ceph/ceph.pub)
        if ! grep -q "\$PUB_KEY" /root/.ssh/authorized_keys; then
            echo "\$PUB_KEY" >> /root/.ssh/authorized_keys
        fi
        chmod 600 /root/.ssh/authorized_keys
EOF

        if [ $? -ne 0 ]; then
            echo "Failed to set up SSH keys on $ip"
            exit 1
        fi
    done
}

# Function to ensure port 3300 is free
ensure_port_free() {
    for ip in "${IPS[@]}"; do
        echo "Ensuring port 3300 is free on $ip"

        ssh $SSH_USER@$ip <<EOF
        set -e
        if lsof -i:3300 -t >/dev/null 2>&1; then
            fuser -k 3300/tcp
        fi
EOF

        if [ $? -ne 0 ]; then
            echo "Failed to ensure port 3300 is free on $ip"
            exit 1
        fi
    done
}

# Function to bootstrap the Ceph cluster
bootstrap_ceph_cluster() {
    echo "Bootstrapping Ceph cluster on $MASTER_IP"

    ssh $SSH_USER@$MASTER_IP <<EOF
    set -e
    sudo cephadm bootstrap --mon-ip $MASTER_IP --initial-dashboard-user admin --initial-dashboard-password admin --allow-overwrite --skip-dashboard
    sleep 10
EOF

    if [ $? -ne 0 ]; then
        echo "Failed to bootstrap Ceph cluster on $MASTER_IP"
        exit 1
    fi
}

# Function to add nodes to the Ceph cluster
add_nodes_to_cluster() {
    for ip in "${IPS[@]:1}"; do
        echo "Adding node $ip to the Ceph cluster"

        ssh $SSH_USER@$MASTER_IP <<EOF
        set -e
        ceph orch host add $ip
        sudo cephadm install ceph-common --hosts $ip
EOF

        if [ $? -ne 0 ]; then
            echo "Failed to add node $ip to the Ceph cluster"
            exit 1
        fi
    done
}

# Main script execution
create_cephadm_user
install_cephadm
setup_ssh_keys
ensure_port_free
bootstrap_ceph_cluster
add_nodes_to_cluster

echo "Ceph cluster setup completed on all nodes."
