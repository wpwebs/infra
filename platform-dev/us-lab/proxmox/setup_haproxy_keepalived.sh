#!/bin/bash

# Define variables
VIRTUAL_IP="192.168.0.130/25"
NODES=("192.168.0.131" "192.168.0.132" "192.168.0.133")
INTERFACE="enp0s5"

# Function to install packages on nodes
install_packages() {
    local node=$1
    echo "Installing HAProxy and Keepalived on $node..."
    ssh root@$node "apt-get update && apt-get install -y haproxy keepalived"
}

# Function to enable IP forwarding on nodes
enable_ip_forwarding() {
    local node=$1
    echo "Enabling IP forwarding on $node..."
    ssh root@$node "sysctl -w net.ipv4.ip_forward=1 && echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf"
}

# Function to generate HAProxy backend configuration
generate_haproxy_backend() {
    local backend_config="backend rgw_backend\n    balance roundrobin\n"
    for i in "${!NODES[@]}"; do
        backend_config+="    server rgw$((i+1)) ${NODES[$i]}:7480 check\n"
    done
    echo -e "$backend_config"
}

# Function to configure HAProxy on nodes
configure_haproxy() {
    local node=$1
    local backend_config=$(generate_haproxy_backend)
    echo "Configuring HAProxy on $node..."
    ssh root@$node "cat > /etc/haproxy/haproxy.cfg <<EOL
global
    log /dev/log local0
    log /dev/log local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode http
    option httplog
    option dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

frontend rgw_frontend
    bind *:7480
    default_backend rgw_backend

$backend_config
EOL
    systemctl restart haproxy"
}

# Function to configure Keepalived on nodes
configure_keepalived() {
    local node=$1
    local state=$2
    local priority=$3
    local unicast_src_ip=$node
    local unicast_peers=""

    for peer in "${NODES[@]}"; do
        if [[ "$peer" != "$node" ]]; then
            unicast_peers+="    $peer\n"
        fi
    done

    echo "Configuring Keepalived on $node with state $state and priority $priority..."
    ssh root@$node "cat > /etc/keepalived/keepalived.conf <<EOL
global_defs {
  notification_email {
  }
  router_id LVS_DEVEL
  vrrp_skip_check_adv_addr
  vrrp_garp_interval 0
  vrrp_gna_interval 0
}

vrrp_script chk_haproxy {
  script \"killall -0 haproxy\"
  interval 2
  weight 2
}

vrrp_instance haproxy-vip {
  state $state
  priority $priority
  interface $INTERFACE
  virtual_router_id 60
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass 1111
  }
  unicast_src_ip $unicast_src_ip
  unicast_peer {
$unicast_peers  }
  virtual_ipaddress {
    ${VIRTUAL_IP%/*}
  }
  track_script {
    chk_haproxy
  }
}
EOL
    systemctl restart keepalived"
}

# Function to check VIP assignment
check_vip() {
    local node=$1
    echo "Checking VIP assignment on $node..."
    ssh root@$node "ip addr show $INTERFACE | grep ${VIRTUAL_IP%/*}"
}

# Function to enable and start HAProxy and Keepalived services
enable_services() {
    local node=$1
    echo "Enabling and starting HAProxy and Keepalived on $node..."
    ssh root@$node "systemctl enable haproxy keepalived && systemctl start haproxy keepalived"
}

# Main script execution
for node in "${NODES[@]}"; do
    install_packages "$node"
    enable_ip_forwarding "$node"
done

for node in "${NODES[@]}"; do
    configure_haproxy "$node"
done

configure_keepalived "${NODES[0]}" "MASTER" 100
for ((i=1; i<${#NODES[@]}; i++)); do
    configure_keepalived "${NODES[$i]}" "BACKUP" $((100-i))
done

for node in "${NODES[@]}"; do
    enable_services "$node"
done

# Check VIP assignment on all nodes
for node in "${NODES[@]}"; do
    check_vip "$node"
done

# Debugging information
echo "IP Forwarding status:"
for node in "${NODES[@]}"; do
    echo "Node $node:"
    ssh root@$node "sysctl net.ipv4.ip_forward"
done

echo "Keepalived status:"
for node in "${NODES[@]}"; do
    echo "Node $node:"
    ssh root@$node "systemctl status keepalived"
done

echo "HAProxy status:"
for node in "${NODES[@]}"; do
    echo "Node $node:"
    ssh root@$node "systemctl status haproxy"
done

echo "HAProxy and Keepalived have been installed and configured on all nodes with IP forwarding enabled."
