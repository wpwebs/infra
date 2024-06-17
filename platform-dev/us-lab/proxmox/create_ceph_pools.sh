#!/bin/bash

# Define variables
PRIMARY_NODE="192.168.0.131"
NODES=("192.168.0.131" "192.168.0.132" "192.168.0.133")
HOSTNAMES=("pve11" "pve12" "pve13")
SSD_DISK="/dev/vdb" # SSD Disk for block storage (ceph RBD)
SAS_DISK="/dev/vdc" # SAS Disk for object storage (ceph RGW)
LOCAL_KEYRING_PATH="/etc/ceph/ceph.client.bootstrap-osd.keyring"
REMOTE_KEYRING_PATH="/var/lib/ceph/bootstrap-osd/ceph.keyring"
CRUSH_SSD_RULE="ssd_rule"
CRUSH_SAS_RULE="sas_rule"

# Function to ensure Ceph client utilities are installed on remote nodes
ensure_ceph_client() {
    local ip=$1
    ssh -t root@$ip "if ! command -v ceph &> /dev/null; then
        echo 'Ceph client utilities not found. Installing...'
        apt-get update
        apt-get install -y ceph || { echo 'Failed to install Ceph client utilities on $ip'; exit 1; }
    fi"
}

# Function to create the bootstrap OSD keyring on the primary node if it doesn't exist
create_bootstrap_keyring() {
    ssh -t root@$PRIMARY_NODE "if [[ ! -f $LOCAL_KEYRING_PATH ]]; then
        echo 'Creating bootstrap OSD keyring'
        ceph auth get-or-create client.bootstrap-osd mon 'allow profile bootstrap-osd' -o $LOCAL_KEYRING_PATH
        if [[ $? -ne 0 ]]; then
            echo 'Failed to create bootstrap OSD keyring'
            exit 1
        fi
    fi"
}

# Function to ensure keyrings are present on remote nodes
ensure_keyring() {
    local ip=$1
    echo "Checking keyring on node with IP $ip"
    ssh -t root@$ip "[[ -f $REMOTE_KEYRING_PATH ]]"
    if [[ $? -ne 0 ]]; then
        echo "Keyring not found on $ip. Copying keyring..."
        ssh -t root@$ip "mkdir -p $(dirname $REMOTE_KEYRING_PATH)"
        scp root@$PRIMARY_NODE:$LOCAL_KEYRING_PATH root@$ip:$REMOTE_KEYRING_PATH
        if [[ $? -ne 0 ]]; then
            echo "Failed to copy keyring to $ip"
            return 1
        fi
    fi
    return 0
}

# Function to create crush rules if they don't exist
create_crush_rule() {
    local rule_name=$1
    ssh -t root@$PRIMARY_NODE "if ! ceph osd crush rule dump $rule_name &>/dev/null; then
        ceph osd crush rule create-replicated $rule_name default host || { echo 'Failed to create CRUSH rule'; exit 1; }
    fi"
}

# Ensure Ceph client utilities are installed on the primary node
ensure_ceph_client $PRIMARY_NODE

# Create the bootstrap OSD keyring on the primary node if needed
create_bootstrap_keyring

# Create crush rules if they don't exist
create_crush_rule $CRUSH_SSD_RULE
create_crush_rule $CRUSH_SAS_RULE

# Function to create OSDs and get their IDs on remote nodes
create_osds() {
    local hostname=$1
    local ip=$2
    local disk=$3
    local device_class=$4

    echo "Creating OSD on node $hostname with IP $ip for $device_class on disk $disk"
    ssh -t root@$ip "ceph-volume lvm create --data $disk"
    if [[ $? -ne 0 ]]; then
        echo "Failed to create OSD on $ip"
        return 1
    fi

    local osd_id=$(ssh -t root@$ip "ceph-volume lvm list | grep 'osd id' | grep -oP '(?<=osd id )\d+' | tail -1")
    if [[ -z "$osd_id" ]]; then
        echo "Failed to retrieve OSD ID on $ip"
        return 1
    fi

    echo "Tagging OSD $osd_id on $ip as $device_class"
    ssh -t root@$ip "ceph osd crush set-device-class $device_class $osd_id"
    if [[ $? -ne 0 ]]; then
        echo "Failed to tag OSD $osd_id on $ip"
        return 1
    fi

    echo $osd_id
}

# Arrays to store OSD IDs
SSD_OSDS=()
SAS_OSDS=()

# Ensure keyrings are present and create OSDs on each node
for i in "${!NODES[@]}"; do
    ensure_ceph_client "${NODES[$i]}"
    ensure_keyring "${NODES[$i]}"
    if [[ $? -ne 0 ]]; then
        echo "Failed to ensure keyring on node ${NODES[$i]}"
        continue
    fi

    # Check if the devices are already prepared
    if ssh -t root@${NODES[$i]} "ceph-volume lvm list | grep -q $SSD_DISK"; then
        echo "--> Device $SSD_DISK is already prepared on ${NODES[$i]}"
    else
        ssd_osd_id=$(create_osds "${HOSTNAMES[$i]}" "${NODES[$i]}" "$SSD_DISK" "ssd")
        if [[ $? -eq 0 ]]; then
            SSD_OSDS+=($ssd_osd_id)
        else
            echo "Failed to create SSD OSD on node ${HOSTNAMES[$i]}"
        fi
    fi

    if ssh -t root@${NODES[$i]} "ceph-volume lvm list | grep -q $SAS_DISK"; then
        echo "--> Device $SAS_DISK is already prepared on ${NODES[$i]}"
    else
        sas_osd_id=$(create_osds "${HOSTNAMES[$i]}" "${NODES[$i]}" "$SAS_DISK" "sas")
        if [[ $? -eq 0 ]]; then
            SAS_OSDS+=($sas_osd_id)
        else
            echo "Failed to create SAS OSD on node ${HOSTNAMES[$i]}"
        fi
    fi
done

# Function to create and set pools on the primary node
create_pool() {
    local pool_name=$1
    local pg_num=$2
    local app_name=$3
    local rule_name=$4

    ceph osd pool create "$pool_name" "$pg_num"
    ceph osd pool application enable "$pool_name" "$app_name"
    ceph osd pool set "$pool_name" crush_rule "$rule_name"
}

# Calculate the number of placement groups (PGs)
calculate_pg_num() {
    local osd_count=$1
    local pool_count=$2
    local target_pgs_per_osd=100

    local total_pgs=$((osd_count * target_pgs_per_osd))
    local pg_num=$((total_pgs / pool_count))

    echo $pg_num
}

# Get the total OSD count
OSD_COUNT=${#SSD_OSDS[@]} # Assuming the same number of SSD and SAS OSDs

# Create pools for RBD (SSD) and RGW (SAS) on the primary node
PG_NUM=$(calculate_pg_num $OSD_COUNT 6)

# Create pools on the primary node
ssh -t root@$PRIMARY_NODE <<EOF
$(declare -f create_pool)
create_pool "rbd-pool" $PG_NUM "rbd" "$CRUSH_SSD_RULE"
create_pool "rgw.root" $PG_NUM "rgw" "$CRUSH_SAS_RULE"
create_pool "default.rgw.control" $PG_NUM "rgw" "$CRUSH_SAS_RULE"
create_pool "default.rgw.meta" $PG_NUM "rgw" "$CRUSH_SAS_RULE"
create_pool "default.rgw.log" $PG_NUM "rgw" "$CRUSH_SAS_RULE"
create_pool "default.rgw.buckets.index" $PG_NUM "rgw" "$CRUSH_SAS_RULE"
create_pool "default.rgw.buckets.data" $PG_NUM "rgw" "$CRUSH_SAS_RULE"
EOF

# Install Ceph RGW package and configure RGW daemon on each node
install_ceph_radosgw() {
    local ip=$1
    local hostname=$2

    echo "Configuring RGW on node $hostname with IP $ip"
    ssh -t root@$ip <<EOF
    apt-get update
    apt-get install -y radosgw || {
        echo "ceph-radosgw not found. Adding repository and updating."
        echo "deb http://download.proxmox.com/debian/ceph-reef bookworm main" > /etc/apt/sources.list.d/ceph.list
        wget -q -O- 'https://download.proxmox.com/debian/proxmox-ve-release-6.x.gpg' | apt-key add -
        apt-get update
        apt-get install -y radosgw || { echo "Failed to install ceph-radosgw on $ip"; exit 1; }
    }

    cat <<EOC >> /etc/ceph/ceph.conf
[client.rgw.$hostname]
host = $hostname
rgw frontends = civetweb port=7480
keyring = /var/lib/ceph/radosgw/ceph-rgw.$hostname/keyring
EOC

    mkdir -p /var/lib/ceph/radosgw/ceph-rgw.$hostname
    ceph auth get-or-create client.rgw.$hostname osd 'allow rwx' mon 'allow rw' -o /var/lib/ceph/radosgw/ceph-rgw.$hostname/keyring || { echo "Failed to create keyring for $hostname"; exit 1; }

    systemctl enable ceph-radosgw@rgw.$hostname
    systemctl start ceph-radosgw@rgw.$hostname || { echo "Failed to start ceph-radosgw@rgw.$hostname on $ip"; exit 1; }
EOF
}

for i in "${!NODES[@]}"; do
    install_ceph_radosgw "${NODES[$i]}" "${HOSTNAMES[$i]}"
    ssh -t root@${NODES[$i]} "SYSTEMD_PAGER= systemctl status ceph-radosgw@rgw.${HOSTNAMES[$i]}" || echo "Failed to start ceph-radosgw@rgw.${HOSTNAMES[$i]}"
done

echo -e "\nCeph RGW and RBD pools created and configured successfully on all nodes."

# Add RBD and RGW storage to Proxmox
add_proxmox_storage() {
    local storage_name=$1
    local storage_type=$2
    local content=$3
    local pool=$4

    ssh -t root@$PRIMARY_NODE "pvesh create /storage -storage $storage_name -type $storage_type -content $content -pool $pool"
    echo "Ceph RBD storage name $storage_name added to Proxmox cluster."
}

# Adding RBD and RGW storage to Proxmox
add_proxmox_storage "block-storage" "rbd" "images,rootdir" "rbd-pool"

# add_proxmox_storage "object-storage" "radosgw" "backup" "default.rgw.buckets.data"

echo "Ceph RGW and RBD pools created and configured successfully on all nodes and added to Proxmox cluster."
