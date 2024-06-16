# 1 - Prepare Network
### 1. Config on Router
```sh
# add KUBEZONE on Router
uci add firewall zone 
uci set firewall.@zone[-1].name='KUBEZONE'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci commit

# Add VLANs on Router
uci add network bridge-vlan
uci set network.@bridge-vlan[-1].device='br-lan'
uci set network.@bridge-vlan[-1].vlan='172'
uci add_list network.@bridge-vlan[-1].ports='eth2:t'
uci add_list network.@bridge-vlan[-1].ports='eth3:t'
uci add_list network.@bridge-vlan[-1].ports='eth4:t'
uci add_list network.@bridge-vlan[-1].ports='eth5:t'
uci commit

# Create Interface on Router
# /etc/config/dhcp
uci set dhcp.KUBE=dhcp
uci set dhcp.KUBE.interface='KUBE'
uci set dhcp.KUBE.start='100'
uci set dhcp.KUBE.limit='150'
uci set dhcp.KUBE.leasetime='72h'
# /etc/config/network
uci set network.KUBE=interface
uci set network.KUBE.proto='static'
uci set network.KUBE.device='br-lan.172'
uci set network.KUBE.ipaddr='172.16.0.1'
uci set network.KUBE.netmask='255.255.255.0'
uci set network.KUBE.dns='172.16.0.1'
uci add_list network.KUBE.dns='fdbd:58fb:3b1f::1'
uci add_list network.KUBE.dns='2601:646:8600:b9::1'
uci add_list dhcp.KUBE.dhcp_option='6,172.16.0.1'

# /etc/config/firewall
uci add_list firewall.$(uci show firewall | grep -B1 "name='KUBEZONE'" | grep -oE '@zone\[[0-9]+\]' | head -n 1).network='KUBE'
uci commit

service network restart

# CONFIG FIREWALL ZONES
# KUBEZONE access to WAN and all other Zones
uci add firewall forwarding 
uci set firewall.@forwarding[-1].src='KUBEZONE'
uci set firewall.@forwarding[-1].dest='HOMEZONE'
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='KUBEZONE'
uci set firewall.@forwarding[-1].dest='IOTZONE'
uci add firewall forwarding 
uci set firewall.@forwarding[-1].src='KUBEZONE'
uci set firewall.@forwarding[-1].dest='wan'
uci commit

```

### 2. Config on other Managed switch, if needed
```sh
uci add network bridge-vlan
uci set network.@bridge-vlan[-1].device='switch'
uci set network.@bridge-vlan[-1].vlan='172'
uci add_list network.@bridge-vlan[6].ports='lan1:t' 
uci add_list network.@bridge-vlan[6].ports='lan2:t' 
uci add_list network.@bridge-vlan[6].ports='lan3:t' 
uci add_list network.@bridge-vlan[6].ports='lan4:t' 
uci add_list network.@bridge-vlan[6].ports='lan5:t' 
uci add_list network.@bridge-vlan[6].ports='lan7:t' 
uci add_list network.@bridge-vlan[6].ports='lan8:t' 
uci add_list network.@bridge-vlan[6].ports='lan9:t' 
uci add_list network.@bridge-vlan[6].ports='lan10:t' 
uci add_list network.@bridge-vlan[6].ports='lan11:t' 
uci add_list network.@bridge-vlan[6].ports='lan12:t' 
uci add_list network.@bridge-vlan[6].ports='lan13:t' 
uci add_list network.@bridge-vlan[6].ports='lan14:t' 
uci add_list network.@bridge-vlan[6].ports='lan15:t' 
uci add_list network.@bridge-vlan[6].ports='lan16:t' 
uci add_list network.@bridge-vlan[6].ports='lan17:t' 
uci add_list network.@bridge-vlan[6].ports='lan18:t' 
uci add_list network.@bridge-vlan[6].ports='lan19:t' 
uci add_list network.@bridge-vlan[6].ports='lan20:t' 
uci add_list network.@bridge-vlan[6].ports='lan21:t' 
uci add_list network.@bridge-vlan[6].ports='lan22:t' 
uci add_list network.@bridge-vlan[6].ports='lan23:t' 
uci add_list network.@bridge-vlan[6].ports='lan24:t'
uci commit
service network restart
```

# 2 - Prepare VM
| IP Address        | Hostname  | Role                  |
| :---------------- | :------:  | :----                 |
| 172.16.0.10        |   lb1     | Keepalived & HAproxy |
| 172.16.0.20        |   lb2     | Keepalived & HAproxy |
| 172.16.0.11        |  master1  | master, etcd         |
| 172.16.0.21        |  master2  | master, etcd         |
| 172.16.0.31        |  master3  | master, etcd         |
| 172.16.0.12        |  worker1  | worker               |
| 172.16.0.22        |  worker2  | worker               |
| 172.16.0.32        |  worker3  | worker               |
| 172.16.0.99        |           | Virtual IP address   |
| 172.16.0.88        |  monitor  | monitor              |


# 3 - Configure Load Balancing
### install Keepalived and HAproxy
```sh
#  install Keepalived and HAproxy
sudo apt update && sudo apt install keepalived haproxy psmisc -y
```
### Configuration HAproxy
```sh
# configuration of HAproxy is exactly the same on the two machines for load balancing
sudo tee /etc/haproxy/haproxy.cfg <<EOL 
global
    log /dev/log  local0 warning
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

   stats socket /var/lib/haproxy/stats

defaults
  log global
  option  httplog
  option  dontlognull
        timeout connect 5000
        timeout client 50000
        timeout server 50000

frontend kube-apiserver
  bind *:6443
  mode tcp
  option tcplog
  default_backend kube-apiserver

backend kube-apiserver
    mode tcp
    option tcplog
    option tcp-check
    balance roundrobin
    default-server inter 10s downinter 5s rise 2 fall 2 slowstart 60s maxconn 250 maxqueue 256 weight 100
    server kube-apiserver-1 172.16.0.11:6443 check # master1
    server kube-apiserver-2 172.16.0.21:6443 check # master2

EOL

# restart HAproxy
sudo systemctl restart haproxy
# Make it persist through reboots
sudo systemctl enable haproxy
```
### Configuration HKeepalived on load balancing 1

```sh
# configuration of Keepalived for load balancing - lb1
sudo tee /etc/keepalived/keepalived.conf <<EOL 
global_defs {
  notification_email {
  }
  router_id LVS_DEVEL
  vrrp_skip_check_adv_addr
  vrrp_garp_interval 0
  vrrp_gna_interval 0
}

vrrp_script chk_haproxy {
  script "killall -0 haproxy"
  interval 2
  weight 2
}

vrrp_instance haproxy-vip {
  state BACKUP
  priority 100
  interface eth0                       # Network card
  virtual_router_id 60
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass 1111
  }
  unicast_src_ip 172.16.0.10      # The IP address of this machine
  unicast_peer {
    172.16.0.20                   # The IP address of peer machines
  }

  virtual_ipaddress {
    172.16.0.99/24                # The Virtual IP address
  }

  track_script {
    chk_haproxy
  }
}

EOL
```
### Configuration of Keepalived on load balancing 2
```sh
# configuration of Keepalived for load balancing - lb2
sudo tee /etc/keepalived/keepalived.conf <<EOL 
global_defs {
  notification_email {
  }
  router_id LVS_DEVEL
  vrrp_skip_check_adv_addr
  vrrp_garp_interval 0
  vrrp_gna_interval 0
}

vrrp_script chk_haproxy {
  script "killall -0 haproxy"
  interval 2
  weight 2
}

vrrp_instance haproxy-vip {
  state BACKUP
  priority 100
  interface eth0                       # Network card
  virtual_router_id 60
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass 1111
  }
  unicast_src_ip 172.16.0.20      # The IP address of this machine
  unicast_peer {
    172.16.0.10                   # The IP address of peer machines
  }

  virtual_ipaddress {
    172.16.0.99/24                # The Virtual IP address
  }

  track_script {
    chk_haproxy
  }
}

EOL

# restart Keepalived
sudo systemctl restart keepalived

# Make it persist through reboots
sudo systemctl enable keepalived

```
# Verify High Availability
```sh
# On the machine lb1, run the following command:
ip a s # on lb1
# the result show the virtual IP address is successfully added
# Simulate a failure on this node:
sudo systemctl stop haproxy
# Check the floating IP address again and you can see it disappear on lb1
ip a s # on lb1 after stop haproxy as simulate a failure on this node
# the virtual IP will be failed over to the other machine (lb2) if the configuration is successful. On lb2, run the following command and here is the expected output:
ip a s # on lb2
```

# 4 - Kubernetes Cluster

### 1) Set Host Name and Update Hosts File
```sh
# Run on Monitor node
sudo hostnamectl set-hostname "monitor.thesimonus.local"

# Run on Load Balancer 1 node
sudo hostnamectl set-hostname "lb1.thesimonus.local"

# Run on Load Balancer 2 node
sudo hostnamectl set-hostname "lb2.thesimonus.local"

# Run on 1st master node
sudo hostnamectl set-hostname "master1.thesimonus.local"

# Run on 2nd master node
sudo hostnamectl set-hostname "master2.thesimonus.local"

# Run on 3rd master node
sudo hostnamectl set-hostname "master3.thesimonus.local" 

# Run on 1st worker node
sudo hostnamectl set-hostname "worker1.thesimonus.local"

# Run on 2nd worker node
sudo hostnamectl set-hostname "worker2.thesimonus.local"

# Run on 3rd worker node
sudo hostnamectl set-hostname "worker3.thesimonus.local"
```

```sh
# Run on all nodes
sudo tee -a /etc/hosts <<EOF

172.16.0.88 monitor.thesimonus.local    monitor
172.16.0.99 k8s.thesimonus.local    k8s

172.16.0.10 lb1.thesimonus.local    lb1
172.16.0.20 lb2.thesimonus.local    lb2

172.16.0.11 master1.thesimonus.local    master1
172.16.0.21 master2.thesimonus.local    master2
172.16.0.31 master3.thesimonus.local    master3

172.16.0.12 worker1.thesimonus.local    worker1
172.16.0.22 worker2.thesimonus.local    worker2
172.16.0.32 worker3.thesimonus.local    worker3

EOF
```

### 2) Disable Swap on All Nodes
```sh
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
```

### 3) Add Firewall Rules for Kubernetes Cluster
```sh
# Note: If firewall is disabled on your Debian 12 systems, then you can skip this step.
# On Master node:
sudo ufw allow 6443/tcp
sudo ufw allow 2379/tcp
sudo ufw allow 2380/tcp
sudo ufw allow 10250/tcp
sudo ufw allow 10251/tcp
sudo ufw allow 10252/tcp
sudo ufw allow 10255/tcp
sudo ufw reload

# On Worker Nodes:
sudo ufw allow 10250/tcp
sudo ufw allow 30000:32767/tcp
sudo ufw reload
```
### 4) Install Containerd Run time on All Nodes
```sh
sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay 
br_netfilter
EOF

sudo modprobe overlay 
sudo modprobe br_netfilter

sudo tee /etc/sysctl.d/99-kubernetes-k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1 
net.bridge.bridge-nf-call-ip6tables = 1 
EOF

# To make above changes into the effect, run
sudo sysctl --system

# Now, install conatinerd by running following apt command on all the nodes.
sudo apt update && sudo apt -y install containerd

# Next, configure containerd so that it works with Kubernetes, run beneath command on all the nodes
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1

# Set cgroupdriver to systemd on all the nodes,
sudo sed -i 's/SystemdCgroup\s*=\s*false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart and enable containerd service on all the nodes,
sudo systemctl restart containerd
sudo systemctl enable containerd
```
### 5) Add Kubernetes Apt Repository
```sh
# Install GPG if needed
sudo apt update && sudo apt install -y gnupg

sudo mkdir -p /etc/apt/keyrings
sudo chmod 755 /etc/apt/keyrings

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```

### 6) Install Kubernetes Tools
```sh
sudo apt update && sudo apt install kubelet kubeadm kubectl -y
sudo apt-mark hold kubelet kubeadm kubectl
```
### 7) Install Kubernetes Cluster with Kubeadm (on 1st master node only)
```sh
# create a configuration file

tee kubelet.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "1.28.0" # Replace with your desired version
controlPlaneEndpoint: "k8s-master"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
EOF

# Now, we are all set to initialize Kubernetes cluster, run following command only from master node,
# sudo kubeadm init --config kubelet.yaml
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --control-plane-endpoint="172.16.0.99:6443" --upload-certs
```
### Use the results to join nodes to the Cluster
```sh
# To start interacting with cluster, run following commands on master node,

# Your Kubernetes control-plane has initialized successfully!
# To start using your cluster, you need to run the following as a regular user:

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# You can now join any number of control-plane nodes by copying certificate authorities
# and service account keys on each node and then running the following as root:
sudo kubeadm join 172.16.0.99:6443 --token g8o8qk.s54ai7l61vnl0tz4 \
    --discovery-token-ca-cert-hash sha256:ac80c97d9e47659260bb610286080e653a6c412aca161aaa8d1eacdf85e9f1b5 \
    --control-plane --certificate-key ffba10b726423d1fcdeb5268a300846623686d49086a9cf2aa2c31c75dd6f11f

# Then you can join any number of worker nodes by running the following on each as root:
sudo kubeadm join 172.16.0.99:6443 --token g8o8qk.s54ai7l61vnl0tz4 \
    --discovery-token-ca-cert-hash sha256:ac80c97d9e47659260bb610286080e653a6c412aca161aaa8d1eacdf85e9f1b5 
```
### Double check the result
```sh
# Run following kubectl command to get nodes and cluster information,
kubectl get nodes
kubectl cluster-info
```

### 8) Setup Pod Network Using Calico 
```sh
# On master node only
# kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# Allow Calico ports in OS firewall, run beneath ufw commands on all the nodes, if the firewall is enabled
sudo ufw allow 179/tcp
sudo ufw allow 4789/udp
sudo ufw allow 51820/udp
sudo ufw allow 51821/udp
sudo ufw reload

# Verify the status of Calico pods, run
kubectl get pods -n kube-system
```
### 9) Test Kubernetes Cluster Installation
```sh
# In order validate and test Kubernetes cluster installation, let’s try to deploy nginx based application via deployment. Run beneath commands,
kubectl create deployment nginx-app --image=nginx --replicas 2
kubectl expose deployment nginx-app --name=nginx-web-svc --type NodePort --port 80 --target-port 80
kubectl describe svc nginx-web-svc
# Try to access the nginx based application using following curl command along with the nodeport 32283.
curl http://worker1:32310
curl http://172.16.0.12:32310
```
172.16.0.12 worker1.thesimonus.local    worker1

```sh

service_account_name=default
namespace=default
# Create the Service Account:
kubectl create serviceaccount $service_account_name --namespace $namespace

# Verify the Service Account Exists
kubectl get serviceaccount "$service_account_name" --namespace "$namespace"

# Create a Role or ClusterRole
kubectl apply -f role-definition.yaml
# Bind the Role to the Service Account
kubectl apply -f rolebinding-definition.yaml

# Get the Secret Name
secret_name=$(kubectl get serviceaccount "$service_account_name" --namespace "$namespace" -o jsonpath='{.secrets[0].name}')

# Debug the Secret Name
echo "Secret name: $secret_name"
# Retrieve the Token

token=$(kubectl get secret "$secret_name" --namespace "$namespace" -o jsonpath='{.data.token}' | base64 --decode)
echo "$token"

#  set the credentials in your kubeconfig to to use the token with kubectl to Authenticate with the Kubernetes API
kubectl config set-credentials $service_account_name --token=$token
# Then, set the context to use these credentials:
kubectl config set-context --current --user=$service_account_name 

# delete a service account in Kubernetes
kubectl delete serviceaccount $service_account_name --namespace $namespace



# Get the Service Account Token
kubectl create serviceaccount $service_account_name --namespace $namespace
kubectl get serviceaccount $service_account_name -o jsonpath="{.secrets[0].name}" --namespace $namespace




```