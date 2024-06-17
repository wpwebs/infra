#!/bin/bash

# Variables
NODES=("pve11" "pve12" "pve13")
IPS=("192.168.0.131" "192.168.0.132" "192.168.0.133")
CLUSTER_NAME="us-lab"
SSH_KEY_FILE="id_uslab"
PROXMOX_KEY_FILE="id_rsa"
SSH_KEY="$HOME/.ssh/${SSH_KEY_FILE}"
SSH_KEY_PUB="$SSH_KEY.pub"
NTP_SERVER="pool.ntp.org" # You can change this to your preferred NTP server
TIMEZONE="America/Los_Angeles" # Time zone for PDT

# Function to generate SSH key if not present
generate_ssh_key() {
    if [ ! -f "$SSH_KEY" ]; then
        echo "Generating SSH ed25519 key pair..."
        ssh-keygen -t ed25519 -f $SSH_KEY -N "" || { echo "Failed to generate SSH key"; exit 1; }
    else
        echo "SSH ed25519 key pair already exists."
    fi
}

# Function to upload SSH key to all nodes
upload_ssh_key() {
    ip=$1
    echo "Uploading SSH key $SSH_KEY $SSH_KEY_PUB to $ip"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@$ip "mkdir -p /root/.ssh && chmod 700 /root/.ssh"
    scp $SSH_KEY $SSH_KEY_PUB root@$ip:/root/.ssh/
    if [ $? -ne 0 ]; then
        echo "Failed to upload SSH key to $ip"
        exit 1
    fi
}

# Function to configure each node
configure_node() {
    local node="$1"
    local ip="$2"

    ssh root@$ip "bash -s" <<EOM
    set -e

    # Set hostname
    echo "Setting hostname to $node"
    hostnamectl set-hostname $node

    # Update /etc/hosts
    cp /etc/hosts /etc/hosts.bak
    $(for i in "${!IPS[@]}"; do
        echo "node_ip=${IPS[$i]}"
        echo "node_name=${NODES[$i]}"
        echo "grep -q \"\$node_ip \$node_name\" /etc/hosts || echo \"\$node_ip \$node_name\" >> /etc/hosts"
    done)

    # Set time zone
    echo "Setting time zone to $TIMEZONE"
    timedatectl set-timezone $TIMEZONE
    timedatectl

    # Install and configure chrony
    echo "Installing and configuring chrony"
    apt-get update && apt-get upgrade -y
    apt-get install -y chrony

    cp /etc/chrony/chrony.conf /etc/chrony/chrony.conf.bak
    sed -i 's/^pool .*/pool $NTP_SERVER iburst/' /etc/chrony/chrony.conf
    systemctl restart chrony
    systemctl enable chrony
    chronyc tracking

    # Force time synchronization
    echo "Forcing time synchronization"
    chronyc -a makestep
    
    # Add cron job to force sync time daily
    (crontab -l 2>/dev/null; echo "0 3 * * * /usr/sbin/chronyc -a 'burst 4/4'") | crontab -
EOM

    if [ $? -ne 0 ]; then
        echo "Failed to configure node $node ($ip)"
        exit 1
    fi

    echo "Node $node ($ip) configured successfully."
}

# Function to retrieve the public key of each node and add it to the authorized_keys of all other nodes
distribute_node_ssh_keys() {
    for i in "${!IPS[@]}"; do
        node_ip=${IPS[$i]}
        node_name=${NODES[$i]}
        echo "Retrieving SSH public key from $node_name ($node_ip)"
        node_pub_key=$(ssh root@$node_ip "cat /root/.ssh/${PROXMOX_KEY_FILE}.pub")
        
        if [ -z "$node_pub_key" ]; then
            echo "Failed to retrieve SSH public key from $node_name ($node_ip)"
            exit 1
        fi

        for j in "${!IPS[@]}"; do
            if [ "$i" != "$j" ]; then
                other_node_ip=${IPS[$j]}
                other_node_name=${NODES[$j]}
                echo "Adding SSH public key of $node_name to $other_node_name ($other_node_ip)"
                
                # Add the public key to the authorized_keys if not already present
                ssh root@$other_node_ip "grep -qxF \"$node_pub_key\" /root/.ssh/authorized_keys || echo \"$node_pub_key\" >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys"
                
                # Check if the host is already present in known_hosts on the remote node
                echo "Adding other nodes to $node_name known_hosts file..."
                ssh root@$node_ip "if ! ssh-keygen -F $other_node_ip &>/dev/null; then ssh-keyscan -H $other_node_ip >> ~/.ssh/known_hosts; fi"
                ssh root@$node_ip "if ! ssh-keygen -F $other_node_name &>/dev/null; then ssh-keyscan -H $other_node_name >> ~/.ssh/known_hosts; fi"

                # Verify if the key was added successfully
                ssh root@$other_node_ip "grep -qxF \"$node_pub_key\" /root/.ssh/authorized_keys"
                if [ $? -ne 0 ]; then
                    echo "Failed to add SSH public key of $node_name to $other_node_name ($other_node_ip)"
                    exit 1
                fi
                
                # Verify if the known_hosts entry was added successfully
                ssh-keygen -F $other_node_ip &>/dev/null
                if [ $? -ne 0 ]; then
                    echo "Failed to add $other_node_ip to known_hosts of $node_name ($node_ip)"
                    exit 1
                fi
            fi
        done
    done
}

# Function to test SSH access from each node to all other nodes
test_ssh_access() {
    for i in "${!IPS[@]}"; do
        for j in "${!IPS[@]}"; do
            if [ "$i" != "$j" ]; then
                echo "Testing SSH access from ${NODES[$i]} to ${NODES[$j]}"
                ssh -o BatchMode=yes root@${IPS[$i]} "ssh -o BatchMode=yes root@${IPS[$j]} 'echo SSH access successful'"
                if [ $? -ne 0 ]; then
                    echo "SSH access from ${NODES[$i]} to ${NODES[$j]} failed"
                    exit 1
                fi
            fi
        done
    done
}

# Function to install dependencies for Proxmox cluster setup
install_proxmox_dependencies() {
    for i in "${!NODES[@]}"; do
        local node="${NODES[$i]}"
        local ip="${IPS[$i]}"
        echo "Installing dependencies on $node ($ip) for Proxmox cluster setup"
        ssh root@$ip "apt-get update && apt-get upgrade -y && apt-get install -y sshpass"
        if [ $? -ne 0 ]; then
            echo "Failed to install dependencies on $node ($ip) for Proxmox cluster setup"
            exit 1
        fi
    done
}

# Function to check if the cluster already exists
cluster_exists() {
    local master_ip=$1
    ssh root@$master_ip "pvecm status" &>/dev/null
    return $?
}

# Function to retry adding a node to the cluster
retry_add_node() {
    local node=$1
    local ip=$2
    local master_ip=$3
    local attempts=5

    for attempt in $(seq 1 $attempts); do
        echo "Attempt $attempt to add $node ($ip) to the cluster"
        ssh root@$ip "pvecm add $master_ip --force --use_ssh"
        if [ $? -eq 0 ]; then
            echo "Successfully added $node to the cluster"
            return 0
        else
            echo "Failed to add $node to the cluster on attempt $attempt"
            sleep 10
        fi
    done

    return 1
}

# Function to verify node is in the cluster
verify_node_in_cluster() {
    local node=$1
    local master_ip=$2
    ssh root@$master_ip "pvecm nodes" | grep -q "$node"
    return $?
}

# Function to setup Proxmox cluster
setup_proxmox_cluster() {
    install_proxmox_dependencies

    local master_node="${NODES[0]}"
    local master_ip="${IPS[0]}"

    if cluster_exists $master_ip; then
        echo "Proxmox cluster already exists on $master_node"
    else
        echo "Creating Proxmox cluster on $master_node with IP $master_ip"
        ssh root@$master_ip "pvecm create $CLUSTER_NAME" || { echo "Failed to create Proxmox cluster on $master_node"; exit 1; }
        # Wait for the cluster to stabilize
        echo -e "Proxmox cluster on $master_node"
        echo -e "\nWait for the cluster to stabilize"
        sleep 30
    fi

    for i in "${!NODES[@]}"; do
        if [ "${NODES[$i]}" != "$master_node" ]; then
            echo "Checking if ${NODES[$i]} is already part of the cluster"
            if ! verify_node_in_cluster "${NODES[$i]}" "$master_ip"; then
                echo "Adding ${NODES[$i]} to the cluster"
                retry_add_node "${NODES[$i]}" "${IPS[$i]}" "$master_ip"
                if ! verify_node_in_cluster "${NODES[$i]}" "$master_ip"; then
                    echo "Failed to add ${NODES[$i]} to the cluster after multiple attempts"
                    exit 1
                fi
            else
                echo "${NODES[$i]} is already part of the cluster"
            fi
        fi
    done
}

# Main script execution
generate_ssh_key

for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    ip="${IPS[$i]}"
    echo -e "\nConfigure node $node $ip ..."
    echo -e "Uploading local pubic key to node $node"
    upload_ssh_key $ip
    ssh-keyscan -H $ip >> ~/.ssh/known_hosts

    configure_node "$node" "$ip"
done

distribute_node_ssh_keys

test_ssh_access

setup_proxmox_cluster
echo "Proxmox cluster setup completed on all nodes."
