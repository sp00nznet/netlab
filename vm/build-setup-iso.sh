#!/bin/sh
# Build the Windows setup ISO on the Proxmox host: the virtio drivers plus a
# copy of your autounattend.xml, adjusted by mkunattend.py so nothing depends
# on drive letters. Windows Setup finds autounattend.xml at the root of any
# CD, so this one ISO carries both.
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/lab.env"

scp -q "$NETLAB/vm/mkunattend.py" "$PVE_HOST:/tmp/netlab-mkunattend.py"
ssh "$PVE_HOST" sh -s <<EOF
set -e
I=$ISO_DIR
W=\$(mktemp -d); A=\$(mktemp -d); V=\$(mktemp -d)
mount -o loop,ro \$I/$AUTOUNATTEND \$A
mount -o loop,ro \$I/$VIRTIO_ISO \$V
cp -a \$V/. \$W/
python3 /tmp/netlab-mkunattend.py \$A/autounattend.xml \$W/autounattend.xml
umount \$A \$V; rmdir \$A \$V
genisoimage -quiet -J -R -V NETLABSETUP -o \$I/$SETUP_ISO \$W
rm -rf \$W /tmp/netlab-mkunattend.py
ls -la \$I/$SETUP_ISO
EOF
