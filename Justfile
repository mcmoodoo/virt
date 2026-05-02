VM := "nixos-cloud"
KEY := "~/.ssh/local_vm"

default:
    @just --list

# === inspection ===

# list all libvirt domains
ls:
    virsh -c qemu:///system list --all

# show the VM's IP
ip name=VM:
    virsh -c qemu:///system domifaddr {{name}}

# ssh into the running VM
ssh name=VM user="mcmoodoo":
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(virsh -c qemu:///system domifaddr {{name}} 2>/dev/null | grep -oP '(\d+\.){3}\d+')
    if [ -z "${ip:-}" ]; then
      echo "Could not get VM IP. Is {{name}} running?"
      exit 1
    fi
    ssh -A -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i {{KEY}} "{{user}}@$ip"

# === image ===

# build the qcow2 from the flake
build name=VM:
    rm -f {{name}}.qcow2 result
    nix build .#nixosConfigurations.nixos-vm.config.system.build.qcow2 --no-link --print-out-paths \
      | xargs -I{} cp {}/nixos.qcow2 {{name}}.qcow2
    chmod 644 {{name}}.qcow2

# delete the local qcow2
clean name=VM:
    rm -f {{name}}.qcow2

# === domain ===

# define & start the VM from the existing qcow2 (run `just build` first if missing)
up name=VM:
    #!/usr/bin/env bash
    set -euo pipefail
    disk="{{name}}.qcow2"
    if [ ! -f "$disk" ]; then
      echo "Missing disk: $disk — run 'just build' first"
      exit 1
    fi
    virt-install \
      --connect qemu:///system \
      --name "{{name}}" \
      --ram 8192 --vcpus 2 \
      --import \
      --disk path="$disk",format=qcow2 \
      --os-variant nixos-unstable \
      --network network=default \
      --graphics none --video virtio \
      --noautoconsole

# graceful power-off (domain stays defined; use `start` to bring back)
stop name=VM:
    virsh -c qemu:///system shutdown {{name}}

# force power-off (domain stays defined)
kill name=VM:
    virsh -c qemu:///system destroy {{name}}

# power on a previously defined VM
start name=VM:
    virsh -c qemu:///system start {{name}}

# stop & undefine the VM (qcow2 stays)
down name=VM:
    -virsh -c qemu:///system destroy {{name}}
    -virsh -c qemu:///system undefine {{name}} --nvram

# down + delete the qcow2
nuke name=VM: (down name) (clean name)

# nuke + build + up — guaranteed clean slate
fresh name=VM: (nuke name) (build name) (up name)

# === day-2 ===

# apply config changes to the running VM in-place via SSH
switch name=VM user="mcmoodoo":
    #!/usr/bin/env bash
    set -euo pipefail
    ip=$(virsh -c qemu:///system domifaddr {{name}} 2>/dev/null | grep -oP '(\d+\.){3}\d+')
    if [ -z "${ip:-}" ]; then
      echo "Could not get VM IP. Is {{name}} running?"
      exit 1
    fi
    NIX_SSHOPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i {{KEY}}" \
      nixos-rebuild switch --flake .#nixos-vm \
      --target-host "{{user}}@$ip" \
      --sudo
