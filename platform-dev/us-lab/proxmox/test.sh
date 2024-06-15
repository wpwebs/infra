NODES=("pve11" "pve12" "pve13")
IPS=("192.168.0.131" "192.168.0.132" "192.168.0.133")


for i in "${!IPS[@]}"; do
    node_ip="${IPS[$i]}"
    node_name="${NODES[$i]}"
    echo "$node_ip $node_name" 
    # grep -q "$node_ip $node_name" /etc/hosts || echo "$node_ip $node_name" >> /etc/hosts
done