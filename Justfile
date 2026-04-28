default:
    @just --list

# list all system domains
list:
    virsh -c qemu:///system list --all

dom vm="nixos-cloud":
  virsh -c qemu:///system domifaddr {{vm}}

# destroy and undefine a VM by name
destroy-vm name="nixos-cloud" seed="nixos-seed":
    -virsh -c qemu:///system destroy {{name}}
    -virsh -c qemu:///system undefine {{name}} --nvram
    -rm {{name}}.qcow2 {{seed}}.img -f

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

# import existing <name>.qcow2 into libvirt and SSH in (create disk with rebuild-nixos / cp / nix build first)
create-nixos name="nixos-cloud":
    #!/usr/bin/env bash
    set -euo pipefail
    disk="{{name}}.qcow2"
    if [ ! -f "$disk" ]; then
      echo "Missing disk: $disk"
      exit 1
    fi
    virt-install \
      --connect qemu:///system \
      --name "{{name}}" \
      --ram 8192 \
      --vcpus 2 \
      --import \
      --disk path="$disk",format=qcow2 \
      --os-variant nixos-unstable \
      --network network=default \
      --graphics none \
      --video virtio \
      --noautoconsole
    echo "Waiting for VM to get an IP..."
    for i in $(seq 1 30); do
      ip=$(virsh -c qemu:///system domifaddr "{{name}}" 2>/dev/null | grep -oP '(\d+\.){3}\d+') && break
      sleep 2
    done
    if [ -z "${ip:-}" ]; then
      echo "Could not get VM IP. Try: virsh -c qemu:///system console {{name}}"
      exit 1
    fi
    echo "Connecting to nixos@$ip ..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/local_vm "nixos@$ip"

# rebuild NixOS qcow2 image from scratch
rebuild-nixos:
    rm -f nixos-cloud.qcow2 result
    echo "Building NixOS qcow2 image..."
    nix build .#nixosConfigurations.nixos-vm.config.system.build.qcow2 --no-link --print-out-paths \
      | xargs -I{} cp {}/nixos.qcow2 nixos-cloud.qcow2
    chmod 644 nixos-cloud.qcow2
    echo "Done. Run 'just destroy-vm && just create-nixos' to re-create the VM."

# destroy, rebuild image, and re-create the VM in one step
recreate-nixos:
    just destroy-vm
    just rebuild-nixos
    just create-nixos

# apply config changes to the running VM over SSH (no image rebuild)
update-nixos vm="nixos-cloud" user="nixos":
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(virsh -c qemu:///system domifaddr {{vm}} 2>/dev/null | grep -oP '(\d+\.){3}\d+')
    if [ -z "${ip:-}" ]; then
      echo "Could not get VM IP. Is {{vm}} running?"
      exit 1
    fi
    NIX_SSHOPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/local_vm" \
      nixos-rebuild switch --flake .#nixos-vm \
      --target-host "{{user}}@$ip" \
      --sudo

