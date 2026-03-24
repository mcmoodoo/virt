default:
    @just --list

# spin up Alpine
alpine iso= "~/Downloads/alpine-standard-3.22.1-x86_64.iso":
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

# spin up Arch
arch iso="/mnt/arch-root/home/mcmoodoo/Downloads/archlinux-2025.09.01-x86_64.iso":
    virt-install \
      --connect qemu:///system \
      --name arch-minimal \
      --ram 1024 \
      --vcpus 2 \
      --disk size=5 \
      --cdrom {{iso}} \
      --os-variant generic \
      --network network=default \
      --graphics none \
      --console pty,target_type=serial

arch-curses iso="/mnt/arch-root/home/mcmoodoo/Downloads/archlinux-2025.09.01-x86_64.iso":
    virt-install \
      --connect qemu:///system \
      --name arch-curses \
      --ram 1024 \
      --vcpus 2 \
      --disk size=5 \
      --cdrom /mnt/arch-root/home/mcmoodoo/Downloads/archlinux-2025.09.01-x86_64.iso \
      --os-variant generic \
      --network network=default \
      --graphics none \
      --console type=curses

arch-qemu qcow2="/home/mcmoodoo/vms/arch-minimal.qcow2":
    # create a disk for the VM
    mkdir -p ~/vms
    qemu-img create -f qcow2 {{qcow2}} 5G

    # run the VM headless, interactive text-mode
    qemu-system-x86_64 \
      -enable-kvm \
      -cpu host \
      -m 1024 \
      -smp 2 \
      -drive file={{qcow2}},if=virtio,format=qcow2 \
      -cdrom /mnt/arch-root/home/mcmoodoo/Downloads/archlinux-2025.09.01-x86_64.iso \
      -boot d \
      -netdev user,id=net0,hostfwd=tcp::2222-:22 \
      -device virtio-net-pci,netdev=net0 \
      -serial mon:stdio \
      -append "console=ttyS0, 115200n8"

arch-virsh-gui:
    virt-install \
      --name arch-gui \
      --ram 1024 \
      --vcpus 2 \
      --disk path=/home/mcmoodoo/vms/arch-minimal.qcow2,size=5,format=qcow2 \
      --cdrom /mnt/arch-root/home/mcmoodoo/Downloads/archlinux-2025.09.01-x86_64.iso \
      --os-variant archlinux \
      --network network=default \
      --graphics spice \
      --video qxl \
      --boot cdrom,hd

