#!/bin/sh
# Create the Linux test VM: Debian 13 from the "generic" cloud image (the
# "genericcloud" one has no graphics drivers, so no screen), with a desktop
# that logs its user on by itself (Xfce on LightDM), so programs started over
# SSH have a screen to draw on. cloud-init does all of it on the first boot:
# your SSH keys (the Proxmox host's root keys), the guest agent, the desktop,
# xdotool and ImageMagick (netlab play and snap), and FUSE for AppImages.
# No GPU: Mesa renders in software, which is enough for apps and 2D/light 3D.
#
# Reads LINUX_* from lab.env. Returns when the desktop is up, and prints the
# address for local/machines/<name>.env (KIND=linux, SSH=netlab@<address>).
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/lab.env"
ID=${LINUX_VMID:?set LINUX_VMID in lab.env}
NAME=${LINUX_VM_NAME:-netlab-linux}
STORE=${LINUX_STORAGE:-$VM_STORAGE}
IMG=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2

# cloud-init vendor data: the part Proxmox's own cloud-init settings don't cover.
ssh "$PVE_HOST" "mkdir -p /var/lib/vz/snippets && cat > /var/lib/vz/snippets/netlab-linux.yaml" <<'EOF'
#cloud-config
package_update: true
packages:
  - qemu-guest-agent
  - xfce4
  - xfce4-terminal
  - lightdm
  - xserver-xorg-video-all
  - dbus-x11
  - x11-utils
  - x11-xserver-utils
  - xdotool
  - wmctrl
  - imagemagick
  - mesa-utils
  - libfuse2t64
  - fuse3
write_files:
  - path: /etc/lightdm/lightdm.conf.d/50-netlab.conf
    content: |
      [Seat:*]
      autologin-user=netlab
      autologin-user-timeout=0
      autologin-session=xfce
  # A test box never blanks or locks its screen.
  - path: /etc/xdg/autostart/netlab-noblank.desktop
    content: |
      [Desktop Entry]
      Type=Application
      Name=netlab: no blanking
      Exec=xset s off -dpms
runcmd:
  - apt-get remove -y light-locker xfce4-screensaver || true
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent || (sleep 5; systemctl start qemu-guest-agent)
  - systemctl set-default graphical.target
  - systemctl isolate graphical.target
EOF

ssh "$PVE_HOST" sh -s <<EOF
set -e
if qm status $ID >/dev/null 2>&1 || pvesh get /cluster/resources --type vm --output-format json | grep -q '"vmid":$ID,'; then
  echo "VMID $ID is taken"; exit 1
fi
img=/var/lib/vz/template/cache/debian-13-generic-amd64.qcow2
[ -f \$img ] || curl -fsSL -o \$img $IMG
qm create $ID --name $NAME --ostype l26 --machine q35 --cpu host \
  --cores ${LINUX_CORES:-4} --memory ${LINUX_MEMORY:-8192} \
  --scsihw virtio-scsi-single --scsi0 $STORE:0,import-from=\$img,discard=on \
  --ide2 $STORE:cloudinit --boot order=scsi0 \
  --net0 virtio,bridge=${LAN_BRIDGE:-vmbr0} --vga std --agent enabled=1 \
  --ciuser netlab --sshkeys /root/.ssh/authorized_keys --ipconfig0 ip=dhcp \
  --cicustom vendor=local:snippets/netlab-linux.yaml \
  --tags "netlab;linux" --description "recomp-netlab Linux test box" >/dev/null
qm disk resize $ID scsi0 ${LINUX_DISK_GB:-40}G >/dev/null
qm start $ID
echo "first boot: cloud-init installs the desktop (5-15 minutes)"
for i in \$(seq 180); do qm agent $ID ping >/dev/null 2>&1 && break; sleep 5; done
ip=\$(qm agent $ID network-get-interfaces | grep -o '"ip-address" *: *"[0-9.]*"' | grep -v '127.0.0.1' | head -1 | grep -o '[0-9.]*\$')
echo "address: \$ip"
EOF
