#!/bin/sh
# Create the Windows test VM and let the unattended install run: q35, UEFI,
# a thin SATA disk (it needs no driver during setup), virtio network, the
# Windows ISO and the setup ISO (vm/build-setup-iso.sh) as CDs, and the
# guest agent enabled. Returns when the agent answers, i.e. Windows finished
# installing and ran its first-logon commands (15-45 minutes).
#
# The GPU is attached afterwards (vm/attach-gpu.sh): an install with it
# passed through gains nothing and can hang on the card.
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/lab.env"

ssh "$PVE_HOST" sh -s <<EOF
set -e
if qm status $VMID >/dev/null 2>&1 || pvesh get /cluster/resources --type vm --output-format json | grep -q '"vmid":$VMID,'; then
  echo "VMID $VMID is taken"; exit 1
fi
qm create $VMID --name $VM_NAME --ostype win10 --machine q35 --bios ovmf \
  --efidisk0 $VM_STORAGE:1,efitype=4m,pre-enrolled-keys=1 \
  --cpu host --cores $VM_CORES --memory $VM_MEMORY \
  --sata0 $VM_STORAGE:$VM_DISK_GB,cache=writeback,discard=on \
  --net0 virtio,bridge=$LAN_BRIDGE \
  --ide2 $ISO_STORAGE:iso/$WIN_ISO,media=cdrom \
  --ide0 $ISO_STORAGE:iso/$SETUP_ISO,media=cdrom \
  --boot "order=ide2;sata0" --agent enabled=1 --vga virtio \
  --tags "netlab;windows" --description "netlab test box" >/dev/null
qm start $VMID
# UEFI shows "Press any key to boot from CD": press it.
for i in \$(seq 20); do sleep 1; qm sendkey $VMID ret 2>/dev/null || true; done
echo "installing; waiting for the guest agent"
for i in \$(seq 540); do qm agent $VMID ping >/dev/null 2>&1 && { echo "agent up"; exit 0; }; sleep 5; done
echo "no agent after 45 minutes: look at the VM console"; exit 1
EOF
