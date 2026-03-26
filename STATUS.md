# VM Lab Status Report

**Date:** 2026-03-26

## Running Domains

None currently running. All VMs have been shut down/destroyed.

## DHCP Leases (stale)

| MAC | IP | Hostname |
|-----|----|----------|
| 52:54:00:67:30:e5 | 192.168.122.44 | - |
| 52:54:00:67:30:e5 | 192.168.122.45 | - |
| 52:54:00:df:f2:65 | 192.168.122.69 | debian-on-defiance |

## Local Disk Images (project dir)

| File | Size | Notes |
|------|------|-------|
| `debian-cloud.qcow2` | 414 MB | Debian 13 cloud image copy (cloud-init) |
| `debian-seed.img` | 370 KB | Cloud-init seed ISO for debian-cloud |
| `debian.qcow2` | 11 GB | Debian 13 installed from netinst ISO (owned by root) |
| `another-debian.qcow2` | 16 MB | CoW clone of debian.qcow2 |

## Images in ~/images

| File | Size | Type |
|------|------|------|
| `alpine-standard-3.23.2-x86_64.iso` | 345 MB | Installer ISO |
| `archlinux-2026.03.01-x86_64.iso` | 1.5 GB | Installer ISO |
| `Arch-Linux-x86_64-basic-20260315.500742.qcow2` | 481 MB | Cloud image (no cloud-init) |
| `Arch-Linux-x86_64-cloudimg-20260315.500742.qcow2` | 519 MB | Cloud image (with cloud-init) |
| `debian-13.4.0-amd64-netinst.iso` | 754 MB | Installer ISO |
| `debian-13-generic-amd64-20260112-2355.qcow2` | 414 MB | Cloud image (with cloud-init) |
| `gparted-live-1.8.1-2-amd64.iso` | 617 MB | Live utility ISO |
| `systemrescue-12.03-amd64.iso` | 1.2 GB | Live utility ISO |
| `ubuntu-24.04.4-live-server-amd64.iso` | 3.2 GB | Installer ISO |
| `ubuntu-minimal-26.04-amd64.qcow2` | 406 MB | Cloud image (with cloud-init) |

## Recipe Status

| Recipe | Method | Console | Status |
|--------|--------|---------|--------|
| `ubuntu` | Cloud image + seed ISO | SSH | Not working (network issue) |
| `ubuntu-server` | ISO installer | Curses | Hangs (installer needs framebuffer) |
| `debian-cloud` | Cloud image + seed ISO | SSH | SSH key not accepted, no DHCP lease |
| `debian` | netinst ISO | Serial | Working |
| `debian-clone` | CoW clone of installed debian | Serial | Working |
| `arch-curses` | ISO installer | Curses | Untested (curses unsupported on this host) |
| `arch-qemu` | ISO + raw QEMU | nographic | Working |
| `arch-virsh-gui` | ISO + SPICE | GUI | Untested |

## Known Issues

- **Cloud images**: cloud-init seed ISO approach not reliably injecting SSH keys or configuring network. Ubuntu cloud image failed to get DHCP. Debian cloud image got DHCP on some VMs but SSH key auth was rejected.
- **Ubuntu server ISO**: subiquity installer requires graphical framebuffer, does not work with `--graphics none` or serial/curses console.
- **Curses console**: `--console type=curses` is unsupported on this libvirt/QEMU build (`unsupported configuration: unknown type presented to host for character device: curses`).
- **`debian.qcow2` owned by root**: created by libvirt in `/var/lib/libvirt/images/`, then referenced locally. Clone overlay (`another-debian.qcow2`) is user-owned.
