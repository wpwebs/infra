# VLAN and Routing Configuration for us-lab Region

## VLAN and Subnet Allocation for `us-lab`

- **Proxmox Server**: VLAN 192, Subnet 192.0.0.0/24
- **Networking Devices**: VLAN 1281, Subnet 128.0.1.0/24
- **Load Balancers**: VLAN 1282, Subnet 128.0.2.0/24
- **Master Nodes**: VLAN 1283, Subnet 128.0.3.0/24
- **Worker Nodes**: VLAN 1284, Subnet 128.0.4.0/24
- **Storage Nodes**: VLAN 1285, Subnet 128.0.5.0/24
- **Backup Nodes**: VLAN 1286, Subnet 128.0.6.0/24
- **Management**: VLAN 1287, Subnet 128.0.7.0/24
- **Operations Team**: VLAN 1288, Subnet 128.0.8.0/24
- **Pod Network CIDR**: VLAN 172, Subnet 172.0.0.0/16
- **Service Network CIDR**: VLAN 10, Subnet 10.0.0.0/16

## Step-by-Step Guide

### Step 1: Configure VLANs on Proxmox

1. **Install VLAN Support on Proxmox**

    ```bash
    apt-get update
    apt-get install -y vlan
    modprobe 8021q
    ```

2. **Configure Network Interfaces with VLANs**

    Edit the network configuration file \`/etc/network/interfaces\` to set up VLANs:

    ```bash
    nano /etc/network/interfaces
    ```

    Add the following configurations for each VLAN:

    ```plaintext
    auto vmbr0
    iface vmbr0 inet static
        address 192.0.0.2
        netmask 255.255.255.0
        gateway 192.0.0.1
        bridge_ports eth0
        bridge_stp off
        bridge_fd 0

    # Networking Devices VLAN
    auto vmbr0.1281
    iface vmbr0.1281 inet static
        address 128.0.1.2
        netmask 255.255.255.0
        vlan-raw-device vmbr0

    # Load Balancers VLAN
    auto vmbr0.1282
    iface vmbr0.1282 inet static
        address 128.0.2.2
        netmask 255.255.255.0
        vlan-raw-device vmbr0

    # Master Nodes VLAN
    auto vmbr0.1283
    iface vmbr0.1283 inet static
        address 128.0.3.2
        netmask 255.255.255.0
        vlan-raw-device vmbr0

    # Worker Nodes VLAN
    auto vmbr0.1284
    iface vmbr0.1284 inet static
        address 128.0.4.2
        netmask 255.255.255.0
        vlan-raw-device vmbr0

    # Storage Nodes VLAN
    auto vmbr0.1285
    iface vmbr0.1285 inet static
        address 128.0.5.2
        netmask 255.255.255.0
        vlan-raw-device vmbr0

    # Backup Nodes VLAN
    auto vmbr0.1286
    iface vmbr0.1286 inet static
        address 128.0.6.2
        netmask 255.255.255.0
        vlan-raw-device vmbr0

    # Management VLAN
    auto vmbr0.1287
    iface vmbr0.1287 inet static
        address 128.0.7.2
        netmask 255.255.255.0
        vlan-raw-device vmbr0

    # Operations Team VLAN
    auto vmbr0.1288
    iface vmbr0.1288 inet static
        address 128.0.8.2
        netmask 255.255.255.0
        vlan-raw-device vmbr0

    # Pod Network CIDR
    auto vmbr0.172
    iface vmbr0.172 inet static
        address 172.0.0.2
        netmask 255.255.0.0
        vlan-raw-device vmbr0

    # Service Network CIDR
    auto vmbr0.10
    iface vmbr0.10 inet static
        address 10.0.0.2
        netmask 255.255.0.0
        vlan-raw-device vmbr0
    ```

3. **Restart Networking Service**

    ```bash
    systemctl restart networking
    ```

### Step 2: Configure VLANs and Routing on the Router

1. **Create VLANs on the Router**

    Depending on your router, the configuration might vary. Here's an example for a typical Cisco router:

    ```plaintext
    interface GigabitEthernet0/0
    switchport trunk encapsulation dot1q
    switchport mode trunk

    interface GigabitEthernet0/0.192
    encapsulation dot1q 192
    ip address 192.0.0.1 255.255.255.0

    interface GigabitEthernet0/0.1281
    encapsulation dot1q 1281
    ip address 128.0.1.1 255.255.255.0

    interface GigabitEthernet0/0.1282
    encapsulation dot1q 1282
    ip address 128.0.2.1 255.255.255.0

    interface GigabitEthernet0/0.1283
    encapsulation dot1q 1283
    ip address 128.0.3.1 255.255.255.0

    interface GigabitEthernet0/0.1284
    encapsulation dot1q 1284
    ip address 128.0.4.1 255.255.255.0

    interface GigabitEthernet0/0.1285
    encapsulation dot1q 1285
    ip address 128.0.5.1 255.255.255.0

    interface GigabitEthernet0/0.1286
    encapsulation dot1q 1286
    ip address 128.0.6.1 255.255.255.0

    interface GigabitEthernet0/0.1287
    encapsulation dot1q 1287
    ip address 128.0.7.1 255.255.255.0

    interface GigabitEthernet0/0.1288
    encapsulation dot1q 1288
    ip address 128.0.8.1 255.255.255.0

    interface GigabitEthernet0/0.172
    encapsulation dot1q 172
    ip address 172.0.0.1 255.255.0.0

    interface GigabitEthernet0/0.10
    encapsulation dot1q 10
    ip address 10.0.0.1 255.255.0.0
    ```

2. **Enable IP Routing**

    ```plaintext
    ip routing
    ```

3. **Add Static Routes if Necessary**

    Add static routes if there are other networks or regions to communicate with:

    ```plaintext
    ip route 192.1.0.0 255.255.255.0 128.0.0.1
    ip route 128.1.0.0 255.255.255.0 128.0.0.1
    ip route 128.2.0.0 255.255.255.0 128.0.0.1
    ip route 128.3.0.0 255.255.255.0 128.0.0.1
    ip route 128.4.0.0 255.255.255.0 128.0.0.1
    ip route 128.5.0.0 255.255.255.0 128.0.0.1
    ip route 128.6.0.0 255.255.255.0 128.0.0.1
    ip route 128.7.0.0 255.255.255.0 128.0.0.1
    ip route 128.8.0.0 255.255.255.0 128.0.0.1
    ip route 172.0.0.0 255.255.0.0 128.0.0.1
    ip route 10.0.0.0 255.255.0.0 128.0.0.1
    ```

## Summary

By following these steps, you create VLANs on Proxmox and configure routing on the router to ensure proper network segmentation and communication for the `us-lab` region. This setup ensures a clear and structured network hierarchy, making it easier to manage and troubleshoot. Each VLAN corresponds to a specific subnet, providing logical separation and enhanced security for different types of devices and traffic.
