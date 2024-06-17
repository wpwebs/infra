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
    node=$1
    ip=$2

    echo -e "\nCreating $CEPHADM_USER user on node $node ($ip)..."

    ssh $SSH_USER@$ip <<EOM
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
EOM

    if [ $? -ne 0 ]; then
        echo "Failed to create $CEPHADM_USER user on $ip"
        exit 1
    fi
}

# Function to install cephadm and required packages
install_cephadm() {
    node=$1
    ip=$2
    echo -e "\nInstalling cephadm on node $node ($ip)..."

    ssh $SSH_USER@$ip <<EOM
    set -e
    apt-get update && apt-get install -y curl gnupg lsb-release sudo
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y cephadm
EOM

    if [ $? -ne 0 ]; then
        echo "Failed to install cephadm on $ip"
        exit 1
    fi
}

# Function to set up SSH keys manually
setup_ssh_keys() {
    node=$1
    ip=$2
    echo -e "\nSetting up SSH keys on node $node ($ip) ..."

    ssh $SSH_USER@$ip <<EOM
    set -e
    if [ ! -f /etc/ceph/ceph.pub ]; then
        ssh-keygen -t ed25519 -N "" -f /etc/ceph/ceph
    fi
    PUB_KEY=\$(cat /etc/ceph/ceph.pub)
    if ! grep -q "\$PUB_KEY" /root/.ssh/authorized_keys; then
        echo "\$PUB_KEY" >> /root/.ssh/authorized_keys
    fi
    chmod 600 /root/.ssh/authorized_keys
EOM

    if [ $? -ne 0 ]; then
        echo "Failed to set up SSH keys on $ip"
        exit 1
    fi
}


# Function to ensure port 3300 is free
ensure_port_free() {
    node=$1
    ip=$2
    echo -e "\nEnsuring port 3300 is free on node $node ($ip)..."

    ssh $SSH_USER@$ip <<EOM
    set -e
    # Check if the port is in use and terminate the process using it
    PIDS=$(pgrep -f "lsof -i:3300 -t")

    if [ -n "$PIDS" ]; then
        echo "Port 3300 is in use. Attempting to free it..."
        for PID in $PIDS; do
            kill -SIGTERM $PID
            echo "Sent SIGTERM to PID $PID"
        done
        echo "Port 3300 is free."
    else
        echo "Failed to terminate process using port 3300."
    fi
EOM

    if [ $? -ne 0 ]; then
        echo "Failed to ensure port 3300 is free on $ip"
        exit 1
    fi
}


# Function to bootstrap the Ceph cluster
bootstrap_ceph_cluster() {
    echo -e "\nBootstrapping Ceph cluster on $MASTER_IP"

    ssh $SSH_USER@$MASTER_IP <<EOM
    set -e
    sudo cephadm bootstrap --mon-ip $MASTER_IP --initial-dashboard-user admin --initial-dashboard-password admin --allow-overwrite --skip-dashboard
    sleep 10
EOM

    if [ $? -ne 0 ]; then
        echo "Failed to bootstrap Ceph cluster on $MASTER_IP"
        return 1
    fi
    return 0
}

# Function to add nodes to the Ceph cluster
add_nodes_to_cluster() {
    for ip in "${IPS[@]:1}"; do
        echo "Adding node $ip to the Ceph cluster"

        ssh $SSH_USER@$MASTER_IP <<EOM
        set -e
        ceph orch host add $ip
        sudo cephadm install ceph-common --hosts $ip
EOM

        if [ $? -ne 0 ]; then
            echo "Failed to add node $ip to the Ceph cluster"
            exit 1
        fi
    done
}

# Main script execution
for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    ip="${IPS[$i]}"
    echo -e "\nConfiguring node $node ($ip) ..."
    echo -e "Uploading local public key to node $node"

    create_cephadm_user "$node" "$ip"
    install_cephadm "$node" "$ip"
    setup_ssh_keys "$node" "$ip"
    ensure_port_free "$node" "$ip"
done

# Creating a new Ceph cluster on master node
if bootstrap_ceph_cluster; then
    # Add nodes to the Ceph cluster only if bootstrap is successful
    add_nodes_to_cluster
else
    echo "Ceph cluster bootstrap failed on master node. Nodes will not be added to the cluster."
    exit 1
fi

echo "Ceph cluster setup completed on all nodes."
