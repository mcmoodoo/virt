default:
    @just --list

# list all system domains
list:
    virsh -c qemu:///system list --all

# destroy and undefine a VM by name
destroy-vm name="nixos-cloud" seed="nixos-seed":
    -virsh -c qemu:///system destroy {{name}}
    -virsh -c qemu:///system undefine {{name}} --nvram
    -rm {{name}}.qcow2 {{seed}}.img -f

connect-console vm="deb":
  virsh -c qemu:///system console {{vm}}

# SSH into a running VM
connect-ssh vm="nixos-cloud" user="nixos":
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(virsh -c qemu:///system domifaddr {{vm}} 2>/dev/null | grep -oP '(\d+\.){3}\d+')
    if [ -z "${ip:-}" ]; then
      echo "Could not get VM IP. Is {{vm}} running?"
      exit 1
    fi
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/local_vm "{{user}}@$ip"

# spin up Debian cloud image, then SSH in (login: debian/debian)
create-debian-cloud img="~/images/debian-13-generic-amd64-20260112-2355.qcow2" pubkey="~/.ssh/id_ed25519.pub":
    #!/usr/bin/env bash
    set -euo pipefail
    img_path="{{img}}"
    img_path="${img_path/#\~/$HOME}"
    pubkey_path="{{pubkey}}"
    pubkey_path="${pubkey_path/#\~/$HOME}"
    if [ ! -f debian-cloud.qcow2 ]; then
      cp "$img_path" debian-cloud.qcow2
      qemu-img resize debian-cloud.qcow2 20G
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
      --ram 8192 \
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

# build NixOS 25.11 qcow2 image, import into libvirt, and SSH in
create-nixos:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f nixos-cloud.qcow2 ]; then
      echo "Building NixOS qcow2 image (first build may take a few minutes)..."
      nix build .#nixosConfigurations.nixos-vm.config.system.build.qcow2 --no-link --print-out-paths \
        | xargs -I{} cp {}/nixos.qcow2 nixos-cloud.qcow2
      chmod 644 nixos-cloud.qcow2
    fi
    virt-install \
      --connect qemu:///system \
      --name nixos-cloud \
      --ram 8192 \
      --vcpus 2 \
      --import \
      --disk path=nixos-cloud.qcow2,format=qcow2 \
      --os-variant nixos-unstable \
      --network network=default \
      --graphics none \
      --video virtio \
      --noautoconsole
    echo "Waiting for VM to get an IP..."
    for i in $(seq 1 30); do
      ip=$(virsh -c qemu:///system domifaddr nixos-cloud 2>/dev/null | grep -oP '(\d+\.){3}\d+') && break
      sleep 2
    done
    if [ -z "${ip:-}" ]; then
      echo "Could not get VM IP. Try: virsh -c qemu:///system console nixos-cloud"
      exit 1
    fi
    echo "Connecting to nixos@$ip ..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "nixos@$ip"

# rebuild NixOS qcow2 image from scratch
rebuild-nixos:
    rm -f nixos-cloud.qcow2 result
    echo "Building NixOS qcow2 image..."
    nix build .#nixosConfigurations.nixos-vm.config.system.build.qcow2 --no-link --print-out-paths \
      | xargs -I{} cp {}/nixos.qcow2 nixos-cloud.qcow2
    chmod 644 nixos-cloud.qcow2
    echo "Done. Run 'just destroy nixos-cloud nixos-seed && just create-nixos' to re-create the VM."
