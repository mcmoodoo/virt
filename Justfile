default:
    @just --list

# list all system domains
list:
    virsh -c qemu:///system list --all

# destroy and undefine a VM by name
destroy name="debian-cloud":
    -virsh -c qemu:///system destroy {{name}}
    -virsh -c qemu:///system undefine {{name}} --nvram
    -rm {{name}}.qcow2 seed.img

connect-console vm="deb":
  virsh -c qemu:///system console {{vm}}

# SSH into a running Ubuntu VM
connect-ssh vm="debian-cloud" user="debian":
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(virsh -c qemu:///system domifaddr {{vm}} 2>/dev/null | grep -oP '(\d+\.){3}\d+')
    if [ -z "${ip:-}" ]; then
      echo "Could not get VM IP. Is {{vm}} running?"
      exit 1
    fi
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "{{user}}@$ip"

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
      cat > "$tmpdir/network-config" <<NETCFG
    version: 2
    ethernets:
      all:
        match:
          name: "*"
        dhcp4: true
    NETCFG
      xorriso -as genisoimage -output debian-seed.img \
        -volid cidata -joliet -rock \
        "$tmpdir/user-data" "$tmpdir/meta-data" "$tmpdir/network-config"
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
      --video virtio \
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
