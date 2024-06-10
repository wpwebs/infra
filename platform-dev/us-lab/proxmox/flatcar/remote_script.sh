pvesh create /nodes/pve1/qemu   -vmid 19000   -name flatcar-template   -memory 2048   -sockets 1   -cores 2   -net0 virtio,bridge=vmbr0,tag=172   -scsihw virtio-scsi-pci

pvesh set /nodes/pve1/qemu/19000/config -scsi0 local-lvm:10
pvesh set /nodes/pve1/qemu/19000/config -scsi1 ssd-storage:50
pvesh set /nodes/pve1/qemu/19000/config -ide2 local:iso/,media=cdrom
pvesh set /nodes/pve1/qemu/19000/config -boot order="scsi0;ide2"
pvesh set /nodes/pve1/qemu/19000/config -serial0 socket
pvesh set /nodes/pve1/qemu/19000/config -onboot 1
pvesh set /nodes/pve1/qemu/19000/config -args "-fw_cfg name=opt/org.flatcar-linux/config,file=/var/lib/vz/template/iso/ignition-config.json"

pvesh create /nodes/pve1/qemu/19000/status/start

