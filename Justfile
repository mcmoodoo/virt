default:
    @just --list

# list all system domains
list:
    virsh -c qemu:///system list --all

# destroy and undefine a VM by name
destroy name="ubuntu-minimal":
    -virsh -c qemu:///system destroy {{name}}
    -virsh -c qemu:///system undefine {{name}} --nvram
    -rm ubuntu-minimal.qcow2 seed.img


# spin up Ubuntu minimal cloud image, then SSH in
ubuntu img="~/images/ubuntu-minimal-26.04-amd64.qcow2" pubkey="~/.ssh/id_ed25519.pub":
    #!/usr/bin/env bash
    set -euo pipefail
    img_path="{{img}}"
    img_path="${img_path/#\~/$HOME}"
    pubkey_path="{{pubkey}}"
    pubkey_path="${pubkey_path/#\~/$HOME}"
    if [ ! -f ubuntu-minimal.qcow2 ]; then
      cp "$img_path" ubuntu-minimal.qcow2
      qemu-img resize ubuntu-minimal.qcow2 5G
    fi
    if [ ! -f seed.img ]; then
      tmpdir=$(mktemp -d)
      cat > "$tmpdir/user-data" <<USERDATA
    #cloud-config
    users:
      - name: ubuntu
        lock_passwd: false
        passwd: \$6\$7KKWkLbaakpgFZiT\$PyP4fg3MVEzVvyUrcuM7.Ywenu0Ikjv2gTDQIias6dyENt4cWyZSOQ76s0I7ab4q4RRstjPs0Cq3a2uE6bRKq.
        ssh_authorized_keys:
          - $(cat "$pubkey_path")
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
    ssh_pwauth: true
    USERDATA
      cat > "$tmpdir/meta-data" <<METADATA
    instance-id: ubuntu-minimal
    local-hostname: ubuntu-minimal
    METADATA
      cat > "$tmpdir/network-config" <<NETCFG
    version: 2
    ethernets:
      all:
        match:
          name: "*"
        dhcp4: true
    NETCFG
      xorriso -as genisoimage -output seed.img \
        -volid cidata -joliet -rock \
        "$tmpdir/user-data" "$tmpdir/meta-data" "$tmpdir/network-config"
      rm -rf "$tmpdir"
    fi
    virt-install \
      --connect qemu:///system \
      --name ubuntu-minimal \
      --ram 2048 \
      --vcpus 1 \
      --import \
      --disk path=ubuntu-minimal.qcow2,format=qcow2 \
      --disk path=seed.img,device=cdrom \
      --boot uefi \
      --os-variant ubuntujammy \
      --network network=default \
      --graphics none \
      --noautoconsole
    echo "Waiting for VM to get an IP..."
    for i in $(seq 1 30); do
      ip=$(virsh -c qemu:///system domifaddr ubuntu-minimal 2>/dev/null | grep -oP '(\d+\.){3}\d+') && break
      sleep 2
    done
    if [ -z "${ip:-}" ]; then
      echo "Could not get VM IP. Check: virsh -c qemu:///system domifaddr ubuntu-minimal"
      exit 1
    fi
    echo "Connecting to ubuntu@$ip ..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "ubuntu@$ip"

# SSH into a running Ubuntu VM
ubuntu-ssh:
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(virsh -c qemu:///system domifaddr ubuntu-minimal 2>/dev/null | grep -oP '(\d+\.){3}\d+')
    if [ -z "${ip:-}" ]; then
      echo "Could not get VM IP. Is ubuntu-minimal running?"
      exit 1
    fi
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "ubuntu@$ip"

# spin up Ubuntu server from ISO (curses console)
ubuntu-server iso="~/images/ubuntu-24.04.4-live-server-amd64.iso":
    virt-install \
      --connect qemu:///system \
      --name ubuntu-server \
      --ram 4096 \
      --vcpus 2 \
      --disk size=10 \
      --cdrom {{iso}} \
      --os-variant ubuntu24.04 \
      --network network=default \
      --graphics none \
      --console type=curses

# spin up Debian cloud image, then SSH in (login: debian/debian)
debian-cloud img="~/images/debian-13-generic-amd64-20260112-2355.qcow2" pubkey="~/.ssh/id_ed25519.pub":
    #!/usr/bin/env bash
    set -euo pipefail
    img_path="{{img}}"
    img_path="${img_path/#\~/$HOME}"
    pubkey_path="{{pubkey}}"
    pubkey_path="${pubkey_path/#\~/$HOME}"
    if [ ! -f debian-cloud.qcow2 ]; then
      cp "$img_path" debian-cloud.qcow2
      qemu-img resize debian-cloud.qcow2 10G
    fi
    if [ ! -f debian-seed.img ]; then
      tmpdir=$(mktemp -d)
      cat > "$tmpdir/user-data" <<USERDATA
    #cloud-config
    users:
      - name: debian
        lock_passwd: false
        passwd: \$6\$7KKWkLbaakpgFZiT\$PyP4fg3MVEzVvyUrcuM7.Ywenu0Ikjv2gTDQIias6dyENt4cWyZSOQ76s0I7ab4q4RRstjPs0Cq3a2uE6bRKq.
        ssh_authorized_keys:
          - $(cat "$pubkey_path")
        sudo: ALL=(ALL) NOPASSWD:ALL
        shell: /bin/bash
    ssh_pwauth: true
    USERDATA
      cat > "$tmpdir/meta-data" <<METADATA
    instance-id: debian-cloud
    local-hostname: debian-cloud
    METADATA
      xorriso -as genisoimage -output debian-seed.img \
        -volid cidata -joliet -rock \
        "$tmpdir/user-data" "$tmpdir/meta-data"
      rm -rf "$tmpdir"
    fi
    virt-install \
      --connect qemu:///system \
      --name debian-cloud \
      --ram 2048 \
      --vcpus 2 \
      --import \
      --disk path=debian-cloud.qcow2,format=qcow2 \
      --disk path=debian-seed.img,device=cdrom \
      --os-variant debian12 \
      --network network=default \
      --graphics none \
      --noautoconsole
    echo "Waiting for VM to get an IP..."
    for i in $(seq 1 30); do
      ip=$(virsh -c qemu:///system domifaddr debian-cloud 2>/dev/null | grep -oP '(\d+\.){3}\d+') && break
      sleep 2
    done
    if [ -z "${ip:-}" ]; then
      echo "Could not get VM IP. Try: virsh -c qemu:///system console debian-cloud (login: debian/debian)"
      exit 1
    fi
    echo "Connecting to debian@$ip ..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "debian@$ip"

# spin up Debian from netinst ISO (serial console)
debian iso="~/images/debian-13.4.0-amd64-netinst.iso":
    virt-install \
      --connect qemu:///system \
      --name debian \
      --ram 2048 \
      --vcpus 2 \
      --disk size=10 \
      --location {{iso}} \
      --os-variant debian12 \
      --network network=default \
      --graphics none \
      --console pty,target_type=serial \
      --extra-args "console=ttyS0,115200n8"

# clone Debian base image and spin up a new VM (serial console)
debian-clone name base="/var/lib/libvirt/images/debian.qcow2":
    #!/usr/bin/env bash
    set -euo pipefail
    disk="{{name}}.qcow2"
    if [ ! -f "$disk" ]; then
      qemu-img create -f qcow2 -b "{{base}}" -F qcow2 "$disk"
    fi
    virt-install \
      --connect qemu:///system \
      --name "{{name}}" \
      --ram 2048 \
      --vcpus 2 \
      --import \
      --disk path="$disk",format=qcow2 \
      --os-variant debian12 \
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

connect vm="ubuntu-minimal":
  virsh -c qemu:///system console {{vm}}
