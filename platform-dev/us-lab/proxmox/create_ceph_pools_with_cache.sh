#!/bin/bash

# Define variables
PRIMARY_NODE="pve11"
NODES=("pve11" "pve12" "pve13")
IPS=("192.168.0.131" "192.168.0.132" "192.168.0.133")
SSD_DISK="/dev/vdb" # Disk for SSD storage
SAS_DISK="/dev/vdc" # Disk for SAS storage
CACHE_SSD_RBD="/dev/vda4" # Disk for cache for RBD pool
CACHE_SSD_RGW="/dev/vda5" # Disk for cache for RGW pool

# Cache parameters
CACHE_TARGET_DIRTY_RATIO=0.4
CACHE_TARGET_FULL_RATIO=0.8
CACHE_MIN_FLUSH_AGE=600
CACHE_MIN_EVICT_AGE=1800
HIT_SET_PERIOD=3600
HIT_SET_COUNT=2
TARGET_MAX_BYTES=10737418240 # 10GB
TARGET_MAX_OBJECTS=10000

# Function to create OSDs and get their IDs
create_osds() {
    local node=$1
    local ip=$2
    local disk=$3
    local device_class=$4
    local cache_disk=$5

    # Create OSD
    ssh root@$ip <<EOF
    ceph-volume lvm create --data $disk --block.db $cache_disk
EOF

    # Get the OSD ID
    osd_id=$(ssh root@$ip "ceph-volume lvm list | grep 'osd id' | grep -oP '(?<=osd id )\d+' | tail -1")

    # Tag the OSD with the device class
    ssh root@$ip "ceph osd crush set-device-class $device_class $osd_id"
    
    echo $osd_id
}

# Arrays to store OSD IDs
SSD_OSDS=()
SAS_OSDS=()

# Create OSDs and tag them with the appropriate device class
for i in "${!NODES[@]}"; do
    ssd_osd_id=$(create_osds "${NODES[$i]}" "${IPS[$i]}" "$SSD_DISK" "ssd" "$CACHE_SSD_RBD")
    sas_osd_id=$(create_osds "${NODES[$i]}" "${IPS[$i]}" "$SAS_DISK" "sas" "$CACHE_SSD_RGW")
    SSD_OSDS+=($ssd_osd_id)
    SAS_OSDS+=($sas_osd_id)
done

# Function to create and set pools
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

ssh root@$PRIMARY_NODE <<EOF
$(declare -f create_pool)
create_pool "rbd-pool" $PG_NUM "rbd" "ssd"
create_pool ".rgw.root" $PG_NUM "rgw" "sas"
create_pool "default.rgw.control" $PG_NUM "rgw" "sas"
create_pool "default.rgw.meta" $PG_NUM "rgw" "sas"
create_pool "default.rgw.log" $PG_NUM "rgw" "sas"
create_pool "default.rgw.buckets.index" $PG_NUM "rgw" "sas"
create_pool "default.rgw.buckets.data" $PG_NUM "rgw" "sas"
EOF

# Function to configure cache tiers
configure_cache_tier() {
    local base_pool=$1
    local cache_pool=$2
    local app_name=$3

    # Create the cache pool
    ceph osd pool create $cache_pool 128
    ceph osd pool application enable $cache_pool $app_name

    # Attach the cache pool to the base pool
    ceph osd tier add $base_pool $cache_pool
    ceph osd tier cache-mode $cache_pool writeback
    ceph osd tier set-overlay $base_pool $cache_pool

    # Set cache parameters
    ceph osd pool set $cache_pool hit_set_type bloom
    ceph osd pool set $cache_pool hit_set_period $HIT_SET_PERIOD
    ceph osd pool set $cache_pool hit_set_count $HIT_SET_COUNT
    ceph osd pool set $cache_pool target_max_bytes $TARGET_MAX_BYTES
    ceph osd pool set $cache_pool target_max_objects $TARGET_MAX_OBJECTS
    ceph osd pool set $cache_pool cache_target_dirty_ratio $CACHE_TARGET_DIRTY_RATIO
    ceph osd pool set $cache_pool cache_target_full_ratio $CACHE_TARGET_FULL_RATIO
    ceph osd pool set $cache_pool cache_min_flush_age $CACHE_MIN_FLUSH_AGE
    ceph osd pool set $cache_pool cache_min_evict_age $CACHE_MIN_EVICT_AGE
}

# Configure cache tiers for RBD and RGW pools
ssh root@$PRIMARY_NODE <<EOF
$(declare -f configure_cache_tier)
configure_cache_tier "rbd-pool" "rbd-cache" "rbd"
configure_cache_tier ".rgw.root" "rgw-cache" "rgw"
EOF

# Install Ceph RGW package and configure RGW daemon on each node
for i in "${!NODES[@]}"; do
    node=${NODES[$i]}
    ip=${IPS[$i]}
    ssh root@$ip <<EOF
    apt-get update
    apt-get install -y ceph-radosgw

    cat <<EOC >> /etc/ceph/ceph.conf
[client.rgw.$node]
host = $node
rgw frontends = civetweb port=7480
keyring = /var/lib/ceph/radosgw/ceph-rgw.$node/keyring
EOC

    mkdir -p /var/lib/ceph/radosgw/ceph-rgw.$node
    ceph auth get-or-create client.rgw.$node osd 'allow rwx' mon 'allow rw' -o /var/lib/ceph/radosgw/ceph-rgw.$node/keyring

    systemctl enable ceph-radosgw@rgw.$node
    systemctl start ceph-radosgw@rgw.$node

    systemctl status ceph-radosgw@rgw.$node
EOF
done

echo "Ceph RBD and RGW pools with cache tiers created and configured successfully on all nodes."
