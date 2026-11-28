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
# address for local/machines/<name>.env (KIND=linux, SSH=netlab@<address>,
# VMID=<id> for netlab console).
#
# Flags win over lab.env, for a second VM that isn't the Linux test box:
#   --no-desktop       console only: no Xfce, LightDM, xdotool or ImageMagick;
#                      boots to multi-user.target (its own cloud-init snippet)
#   --name N  --vmid N|next  --cores N  --memory MB
#   --vga TYPE         std (the default), virtio, qxl...
#   --audio DEV        a sound card with no host backend (ich9-intel-hda)
# e.g. vm/create-linux-vm.sh --no-desktop --name fpsos-vm --vmid next \
#        --vga virtio --cores 4 --memory 4096 --audio ich9-intel-hda
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/lab.env"
ID=${LINUX_VMID:-next}
NAME=${LINUX_VM_NAME:-netlab-linux}
CORES=${LINUX_CORES:-4} MEMORY=${LINUX_MEMORY:-8192}
VGA=std AUDIO= DESKTOP=1
while [ $# -gt 0 ]; do
  case $1 in
    --no-desktop) DESKTOP=; shift ;;
    --name)   NAME=$2; shift 2 ;;
    --vmid)   ID=$2; shift 2 ;;
    --cores)  CORES=$2; shift 2 ;;
    --memory) MEMORY=$2; shift 2 ;;
    --vga)    VGA=$2; shift 2 ;;
    --audio)  AUDIO=$2; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done
# Everything below lands in a root shell on the Proxmox host: plain values only.
for v in "$NAME" "$ID" "$CORES" "$MEMORY" "$VGA" "$AUDIO"; do
  case $v in *[!A-Za-z0-9._-]*) echo "bad value: $v" >&2; exit 2 ;; esac
done
[ "$ID" != next ] || ID=$(ssh "$PVE_HOST" pvesh get /cluster/nextid)
STORE=${LINUX_STORAGE:-$VM_STORAGE}
IMG=https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2
SNIPPET=netlab-linux.yaml
[ -n "$DESKTOP" ] || SNIPPET=netlab-linux-console.yaml

# cloud-init vendor data: the part Proxmox's own cloud-init settings don't cover.
if [ -z "$DESKTOP" ]; then
# Console only: the guest agent (the wait below pings it) and nothing else.
ssh "$PVE_HOST" "mkdir -p /var/lib/vz/snippets && cat > /var/lib/vz/snippets/$SNIPPET" <<'EOF'
#cloud-config
package_update: true
packages:
  - qemu-guest-agent
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent || (sleep 5; systemctl start qemu-guest-agent)
  - systemctl set-default multi-user.target
EOF
else
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
fi

ssh "$PVE_HOST" sh -s <<EOF
set -e
if qm status $ID >/dev/null 2>&1 || pvesh get /cluster/resources --type vm --output-format json | grep -q '"vmid":$ID,'; then
  echo "VMID $ID is taken"; exit 1
fi
img=/var/lib/vz/template/cache/debian-13-generic-amd64.qcow2
[ -f \$img ] || curl -fsSL -o \$img $IMG
qm create $ID --name $NAME --ostype l26 --machine q35 --cpu host \
  --cores $CORES --memory $MEMORY ${AUDIO:+--audio0 device=$AUDIO,driver=none} \
  --scsihw virtio-scsi-single --scsi0 $STORE:0,import-from=\$img,discard=on \
  --ide2 $STORE:cloudinit --boot order=scsi0 \
  --net0 virtio,bridge=${LAN_BRIDGE:-vmbr0} --vga $VGA --agent enabled=1 \
  --ciuser netlab --sshkeys /root/.ssh/authorized_keys --ipconfig0 ip=dhcp \
  --cicustom vendor=local:snippets/$SNIPPET \
  --tags "netlab;linux" --description "netlab Linux test box" >/dev/null
qm disk resize $ID scsi0 ${LINUX_DISK_GB:-40}G >/dev/null
qm start $ID
echo "VMID $ID ($NAME). first boot: cloud-init installs ${DESKTOP:+the desktop and }the guest agent (5-15 minutes)"
for i in \$(seq 180); do qm agent $ID ping >/dev/null 2>&1 && break; sleep 5; done
ip=\$(qm agent $ID network-get-interfaces | grep -o '"ip-address" *: *"[0-9.]*"' | grep -v '127.0.0.1' | head -1 | grep -o '[0-9.]*\$')
echo "address: \$ip"
EOF
