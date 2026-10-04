#!/bin/sh
# Pass the GPU through to the VM, after the install (vm/create-vm.sh): shut
# it down, attach every function of the card as PCIe, drop the install CDs,
# boot from the disk. The virtual display stays the primary one, so the
# Proxmox console keeps working and no dummy HDMI plug is needed; games
# render on the passed-through card and Windows composites onto the virtual
# display.
#
# Don't try to "fix" a stuck card with a PCI remove/rescan on the host: it can
# drop off the bus entirely. Use vm/vfio-host.sh and reboot the host instead.
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/lab.env"

ssh "$PVE_HOST" sh -s <<EOF
set -e
qm shutdown $VMID --timeout 240 || qm stop $VMID
qm set $VMID --hostpci0 $GPU,pcie=1 --boot order=sata0 >/dev/null
qm set $VMID --delete ide0,ide1,ide2 >/dev/null 2>&1 || true
qm start $VMID
for i in \$(seq 60); do qm agent $VMID ping >/dev/null 2>&1 && { echo "up, with $GPU"; exit 0; }; sleep 5; done
echo "no agent after 5 minutes"; exit 1
EOF
