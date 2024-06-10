#!/bin/bash

# Explanation
# 1. Install Dependencies: The install_dependencies function installs Docker, kubelet, kubeadm, kubectl, and Ansible on each node.
# 2. Load Balancer Configuration: Sets up Keepalived and HAProxy on two load balancers for high availability.
# 3. Kubernetes Master and Worker Nodes: Initializes the Kubernetes master node and joins additional master and worker nodes.
# 4. Networking: Uses Flannel as the pod network add-on.
# 5. Load Balancer for Services: Installs MetalLB for service load balancing.
# 6. Storage with Rook and Ceph: Clones the Rook repository, deploys the Rook operator, and sets up a Ceph cluster for storage.
# 7. StorageClass and PVC: Creates a StorageClass for Rook Ceph and a PersistentVolumeClaim to verify the setup.

# Conclusion
# This script provides a comprehensive setup for a high-availability Kubernetes platform with robust storage capabilities, suitable for hosting WordPress, while also installing Ansible on all nodes for future maintenance tasks. Customize the configuration files and variables according to your environment and requirements.


# Variables
LOAD_BALANCER_IPS=("192.168.1.200" "192.168.1.201")
VIRTUAL_IP="192.168.1.202"
MASTER_IPS=("192.168.1.100" "192.168.1.101" "192.168.1.102")
WORKER_IPS=("192.168.1.103" "192.168.1.104" "192.168.1.105")
STORAGE_IPS=("192.168.1.106" "192.168.1.107" "192.168.1.108")
ALL_NODES=("${LOAD_BALANCER_IPS[@]}" "${MASTER_IPS[@]}" "${WORKER_IPS[@]}" "${STORAGE_IPS[@]}")
KUBERNETES_VERSION="1.23.0"
POD_NETWORK_CIDR="10.244.0.0/16"
METALLB_IP_RANGE="192.168.1.210-192.168.1.220"
SSH_USER="your_ssh_user"
ROOK_VERSION="v1.7.9"

# Function to install dependencies on Debian 12 nodes
install_dependencies() {
  ssh $SSH_USER@$1 <<EOF
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
sudo apt-get update
sudo apt-get install -y docker-ce
sudo systemctl start docker
sudo systemctl enable docker
curl -LO https://storage.googleapis.com/kubernetes-release/release/v$KUBERNETES_VERSION/bin/linux/amd64/kubectl
sudo mv kubectl /usr/local/bin/
sudo chmod +x /usr/local/bin/kubectl
curl -LO https://storage.googleapis.com/kubernetes-release/release/v$KUBERNETES_VERSION/bin/linux/amd64/kubelet
sudo mv kubelet /usr/local/bin/
sudo chmod +x /usr/local/bin/kubelet
curl -LO https://storage.googleapis.com/kubernetes-release/release/v$KUBERNETES_VERSION/bin/linux/amd64/kubeadm
sudo mv kubeadm /usr/local/bin/
sudo chmod +x /usr/local/bin/kubeadm
sudo apt-get install -y python3 python3-pip
sudo pip3 install ansible
EOF
}

# Install dependencies on all nodes
for node in "${ALL_NODES[@]}"; do
  install_dependencies $node
done

# Install and configure Keepalived and HAProxy on load balancers
for i in ${!LOAD_BALANCER_IPS[@]}; do
  lb_ip=${LOAD_BALANCER_IPS[$i]}
  priority=$((101 - $i))

  ssh $SSH_USER@$lb_ip <<EOF
sudo apt-get install -y keepalived haproxy

# Configure HAProxy
sudo bash -c 'cat > /etc/haproxy/haproxy.cfg' <<EOL
global
    log /dev/log    local0
    log /dev/log    local1 notice
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

frontend kubernetes-frontend
    bind $VIRTUAL_IP:6443
    mode tcp
    option tcplog
    default_backend kubernetes-backend

backend kubernetes-backend
    mode tcp
    balance roundrobin
    option tcp-check
$(for master_ip in "${MASTER_IPS[@]}"; do echo "    server master-$master_ip $master_ip:6443 check"; done)
EOL

# Configure Keepalived
sudo bash -c 'cat > /etc/keepalived/keepalived.conf' <<EOL
vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority $priority
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass 1234
    }

    virtual_ipaddress {
        $VIRTUAL_IP
    }

    track_script {
        chk_haproxy
    }
}

vrrp_script chk_haproxy {
    script "pidof haproxy"
    interval 2
    weight 2
}
EOL

sudo systemctl restart haproxy
sudo systemctl enable haproxy
sudo systemctl restart keepalived
sudo systemctl enable keepalived
EOF
done

# Initialize Kubernetes master node
ssh $SSH_USER@${MASTER_IPS[0]} "sudo kubeadm init --control-plane-endpoint=$VIRTUAL_IP:6443 --upload-certs --pod-network-cidr=$POD_NETWORK_CIDR"
INIT_OUTPUT=$(ssh $SSH_USER@${MASTER_IPS[0]} "sudo kubeadm init --control-plane-endpoint=$VIRTUAL_IP:6443 --upload-certs --pod-network-cidr=$POD_NETWORK_CIDR")
JOIN_CMD=$(echo "$INIT_OUTPUT" | grep -A 1 "kubeadm join")

# Set up kubeconfig for the user on the first master
ssh $SSH_USER@${MASTER_IPS[0]} "mkdir -p \$HOME/.kube && sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config && sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"

# Install a pod network add-on (flannel in this case)
ssh $SSH_USER@${MASTER_IPS[0]} "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"

# Join the other master nodes to the cluster
for master in "${MASTER_IPS[@]:1}"; do
  ssh $SSH_USER@$master "sudo $JOIN_CMD --control-plane --certificate-key $(echo "$INIT_OUTPUT" | grep 'certificate-key' | awk '{print $3}')"
done

# Join worker nodes to the cluster
for worker in "${WORKER_IPS[@]}"; do
  ssh $SSH_USER@$worker "sudo $JOIN_CMD"
done

# Install MetalLB for LoadBalancer services
ssh $SSH_USER@${MASTER_IPS[0]} <<EOF
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/metallb.yaml

cat <<EOL | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - $METALLB_IP_RANGE
EOL
EOF

# Clone Rook repository on the first storage node and copy to others
ssh $SSH_USER@${STORAGE_IPS[0]} "git clone --single-branch --branch $ROOK_VERSION https://github.com/rook/rook.git"
for node in "${STORAGE_IPS[@]:1}"; do
  ssh $SSH_USER@${STORAGE_IPS[0]} "scp -r rook $SSH_USER@$node:/home/$SSH_USER/"
done

# Deploy Rook operator
ssh $SSH_USER@${MASTER_IPS[0]} "kubectl apply -f rook/cluster/examples/kubernetes/ceph/crds.yaml -f rook/cluster/examples/kubernetes/ceph/common.yaml -f rook/cluster/examples/kubernetes/ceph/operator.yaml"

# Deploy Ceph cluster
ssh $SSH_USER@${MASTER_IPS[0]} "kubectl apply -f rook/cluster/examples/kubernetes/ceph/cluster.yaml"

# Monitor deployment
ssh $SSH_USER@${MASTER_IPS[0]} "kubectl -n rook-ceph get pods -w"

# Create StorageClass
cat <<EOL | ssh $SSH_USER@${MASTER_IPS[0]} "kubectl apply -f -"
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-ceph-block
provisioner: rook-ceph.rbd.csi.ceph.com
parameters:
  clusterID: rook-ceph
  pool: replicapool
  imageFormat: "2"
  imageFeatures: "layering"
reclaimPolicy: Delete
allowVolumeExpansion: true
EOL

# Create PVC
cat <<EOL | ssh $SSH_USER@${MASTER_IPS[0]} "kubectl apply -f -"
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ceph-pvc
spec:
  storageClassName: rook-ceph-block
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOL

# Verify PVC
ssh $SSH_USER@${MASTER_IPS[0]} "kubectl get pvc ceph-pvc"
ssh $SSH_USER@${MASTER_IPS[0]} "kubectl get pv"

echo "Comprehensive Kubernetes platform for WordPress hosting is set up."
