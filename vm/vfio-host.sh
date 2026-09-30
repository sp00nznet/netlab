#!/bin/sh
# Give the GPU to vfio-pci from boot, on the Proxmox host. Then the host
# driver never initializes it, and every VM start finds it in a clean state.
# RX 6000 cards in particular often can't be reset once the host driver has
# used them: the VM's second start crashes QEMU, and the card can drop off the
# PCI bus until the host reboots.
#
#   vm/vfio-host.sh           # show what would change
#   vm/vfio-host.sh --apply   # write it and rebuild the initramfs; then reboot the host
#
# The card is then the VM's alone: containers using it through /dev/dri or
# /dev/kfd lose it. Revert with vm/vfio-host.sh --revert (and reboot).
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/lab.env"

ssh "$PVE_HOST" MODE="${1:-show}" IDS="$GPU_IDS" sh -s <<'EOF'
set -e
CONF=/etc/modprobe.d/netlab-vfio.conf
users=$(grep -lE "/dev/dri|/dev/kfd" /etc/pve/lxc/*.conf 2>/dev/null | xargs -r -n1 basename | sed 's/.conf$//' | tr '\n' ' ')
[ -n "$users" ] && echo "containers that use a GPU through the host driver: $users"
case $MODE in
--apply)
  cat > $CONF <<CONF
# recomp-netlab: the passthrough GPU belongs to vfio-pci from boot.
# Remove this file, run update-initramfs -u -k all, and reboot to undo.
options vfio-pci ids=$IDS disable_vga=1
softdep amdgpu pre: vfio-pci
softdep nouveau pre: vfio-pci
softdep snd_hda_intel pre: vfio-pci
CONF
  update-initramfs -u -k all >/dev/null
  echo "written $CONF; reboot the host to apply"
  ;;
--revert)
  rm -f $CONF
  update-initramfs -u -k all >/dev/null
  echo "removed $CONF; reboot the host to apply"
  ;;
*)
  echo "would write $CONF: vfio-pci ids=$IDS, loaded before the host GPU drivers"
  grep -o "amd_iommu=on\|intel_iommu=on" /proc/cmdline >/dev/null || echo "note: IOMMU isn't enabled on the kernel command line"
  ;;
esac
EOF
