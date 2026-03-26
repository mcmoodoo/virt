default:
    @just --list

# spin up Alpine
alpine iso="~/images/alpine-standard-3.23.2-x86_64.iso":
    virt-install \
      --connect qemu:///system \
      --name alpine-standard \
      --ram 1024 \
      --vcpus 1 \
      --disk size=3 \
      --cdrom {{iso}} \
      --os-variant generic \
      --network network=default \
      --graphics none \
      --console pty,target_type=serial

arch-curses iso="~/images/archlinux-2026.03.01-x86_64.iso":
    virt-install \
      --connect qemu:///system \
      --name arch-curses \
      --ram 1024 \
      --vcpus 2 \
      --disk size=5 \
      --cdrom {{iso}} \
      --os-variant generic \
      --network network=default \
      --graphics none \
      --console type=curses

arch-qemu iso="~/images/archlinux-2026.03.01-x86_64.iso" qcow2="arch-qemu.qcow2":
    #!/usr/bin/env bash
    if [ ! -f "{{qcow2}}" ]; then
      qemu-img create -f qcow2 "{{qcow2}}" 5G
    fi
    qemu-system-x86_64 \
      -enable-kvm \
      -cpu host \
      -m 1024 \
      -smp 2 \
      -drive file="{{qcow2}}",if=virtio,format=qcow2 \
      -cdrom "{{iso}}" \
      -boot d \
      -netdev user,id=net0,hostfwd=tcp::2222-:22 \
      -device virtio-net-pci,netdev=net0 \
      -nographic

arch-virsh-gui iso="~/images/archlinux-2026.03.01-x86_64.iso":
    virt-install \
      --connect qemu:///system \
      --name arch-gui \
      --ram 1024 \
      --vcpus 2 \
      --disk path=arch-gui.qcow2,size=5,format=qcow2 \
      --cdrom {{iso}} \
      --os-variant archlinux \
      --network network=default \
      --graphics spice \
      --video qxl \
      --boot cdrom,hd

