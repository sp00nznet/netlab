#!/bin/bash
# The Windows test VM, start to finish. Asks a few questions, then:
#   - checks SSH to the Proxmox host (and puts your key there if it isn't);
#   - uploads your Windows ISO if it's on this PC, and gets the virtio
#     drivers onto the host (asks before downloading them);
#   - makes an answer file (vm/autounattend.xml) with a random password, on
#     a small CD of its own;
#   - creates the VM and waits out the unattended install (vm/create-vm.sh);
#   - sets up SSH with your key and the VC++ runtime, through the guest agent;
#   - writes local/machines/<name>.env, so `netlab run ... --on <name>` works;
#   - optionally passes a GPU through.
# Every answer is kept in lab.env, and offered as the default next time.
#
#   vm/setup-windows.sh
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
ENV=$NETLAB/lab.env
[ -f "$ENV" ] || cp "$NETLAB/lab.env.example" "$ENV"
. "$ENV"

die() { echo "setup: $*" >&2; exit 1; }
ask() { local a; read -r -p "$2 [$3]: " a || true; a=${a#[\"\']}; a=${a%[\"\']}; printf -v "$1" '%s' "${a:-$3}"; }
confirm() {   # confirm <question> <y|n default>
  local a; read -r -p "$1 [$([ "$2" = y ] && echo Y/n || echo y/N)]: " a || true
  case ${a:-$2} in [yY]*) return 0 ;; *) return 1 ;; esac
}
# Plain bash on purpose: Git Bash rewrites /var/... into C:/Program Files/Git/var/...
# in arguments and environment it hands to a Windows program like python.
setvar() {    # setvar KEY: keep its value in lab.env
  local k=$1 v=${!1} line l
  [[ $v =~ ^[A-Za-z0-9_@.:/,+-]*$ ]] && line="$k=$v" || line="$k='$v'"
  if grep -q "^$k=" "$ENV"; then
    while IFS= read -r l || [ -n "$l" ]; do
      [[ $l == "$k="* ]] && printf '%s\n' "$line" || printf '%s\n' "$l"
    done < "$ENV" > "$ENV.new" && mv "$ENV.new" "$ENV"
  else
    printf '%s\n' "$line" >> "$ENV"
  fi
}
pve() { ssh -n -o BatchMode=yes -o ConnectTimeout=10 "$PVE_HOST" "$@"; }
# A path pasted from Windows (D:\isos\win.iso) as Git Bash sees it.
localpath() { command -v cygpath >/dev/null && cygpath -u "$1" || echo "$1"; }

echo "netlab: the Windows test VM. Enter keeps the [default]."
echo

# --- The Proxmox host ------------------------------------------------------
h=${PVE_HOST#*@}; u=${PVE_HOST%@*}; [ "$u" = "$PVE_HOST" ] && u=root
ask h "Proxmox host (name or address)" "$h"
ask u "SSH user on it" "$u"
PVE_HOST=$u@$h
[ "$u" = root ] || echo "note: the VM scripts call qm and pvesm, which need root on the host."

KEY=$(ls ~/.ssh/id_ed25519.pub ~/.ssh/id_ecdsa.pub ~/.ssh/id_rsa.pub 2>/dev/null | head -1)
if [ -z "$KEY" ]; then
  confirm "You have no SSH key. Make one (~/.ssh/id_ed25519)?" y || die "an SSH key is needed"
  ssh-keygen -q -t ed25519 -N "" -f ~/.ssh/id_ed25519
  KEY=~/.ssh/id_ed25519.pub
fi
if ! pve true 2>/dev/null; then
  echo "Your key isn't on $h yet. Adding it: $u's password, once."
  ssh -o StrictHostKeyChecking=accept-new "$PVE_HOST" 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys' < "$KEY"
  pve true || die "still can't log on to $PVE_HOST with your key"
fi
pve 'command -v qm' >/dev/null || die "$h has no qm: is it a Proxmox host?"
setvar PVE_HOST

# --- The VM ------------------------------------------------------------------
echo
ask VMID "VM ID" "$(pve pvesh get /cluster/nextid)"
ask VM_NAME "VM name" "${VM_NAME:-netlab-win}"
echo "Storages for its disk (thin ones only use what Windows writes, ~25 GB):"
pve "pvesm status --content images --enabled 1" | awk 'NR > 1 { printf "  %-16s %s, %d GB free\n", $1, $2, $6 / 1048576 }'
s=$(pve "pvesm status --content images --enabled 1" | awk -v s="$VM_STORAGE" 'NR > 1 && $1 == s { print $1 }')
ask VM_STORAGE "Storage" "${s:-$(pve "pvesm status --content images --enabled 1" | awk 'NR == 2 { print $1 }')}"
ask VM_CORES "Cores" "${VM_CORES:-8}"
ask VM_MEMORY "Memory (MB)" "${VM_MEMORY:-16384}"
ask VM_DISK_GB "Disk (GB)" "${VM_DISK_GB:-80}"
ask LAN_BRIDGE "Network bridge" "${LAN_BRIDGE:-vmbr0}"

# --- ISOs --------------------------------------------------------------------
echo
s=$(pve "pvesm status --content iso --enabled 1" | awk -v s="$ISO_STORAGE" 'NR > 1 && $1 == s { print $1 }')
ISO_STORAGE=${s:-$(pve "pvesm status --content iso --enabled 1" | awk 'NR == 2 { print $1 }')}
[ -n "$ISO_STORAGE" ] || die "$h has no storage for ISOs"
ISO_DIR=$(dirname "$(pve "pvesm path $ISO_STORAGE:iso/x.iso")")
# upload <local file>: put it in ISO_DIR, unless a file of that name is there
upload() {
  if pve "test -f '$ISO_DIR/$(basename "$1")'"; then echo "$(basename "$1") is already on $h"
  else echo "uploading $(basename "$1") to $h:$ISO_DIR"; scp "$1" "$PVE_HOST:$ISO_DIR/"; fi
}

wins=$(pve "ls '$ISO_DIR'" | grep -i 'win.*\.iso$' | grep -vi 'virtio\|netlab\|unattend\|setup' || true)
[ -n "$wins" ] && { echo "Windows ISOs on $h ($ISO_STORAGE):"; echo "$wins" | sed 's/^/  /'; }
echo "Windows 10 or 11, desktop edition (not Server): a name from the list, or a path on this PC."
echo "$wins" | grep -qxF "$WIN_ISO" || WIN_ISO=$(echo "$wins" | head -1)
ask iso "Windows ISO" "$WIN_ISO"
if [ -f "$(localpath "$iso")" ]; then upload "$(localpath "$iso")"; WIN_ISO=$(basename "$(localpath "$iso")")
else pve "test -f '$ISO_DIR/$iso'" || die "no $iso on $h, and no such file here"; WIN_ISO=$iso; fi

v=$(pve "ls -t '$ISO_DIR'" | grep -i '^virtio-win.*\.iso$' | head -1 || true)
if [ -n "$v" ]; then
  echo "virtio drivers: $v, on $h"; VIRTIO_ISO=$v
elif confirm "No virtio drivers on $h. Download the stable virtio-win ISO there (~750 MB, from fedorapeople.org)?" y; then
  pve "curl -fL -o '$ISO_DIR/virtio-win.iso' https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
  VIRTIO_ISO=virtio-win.iso
else
  ask v "virtio-win ISO on this PC" ""
  [ -f "$(localpath "$v")" ] || die "no file $v"
  upload "$(localpath "$v")"; VIRTIO_ISO=$(basename "$(localpath "$v")")
fi

# --- The account ---------------------------------------------------------------
echo
ask VM_USER "Windows account (an administrator, logged on at every boot)" "${VM_USER:-netlab}"
[[ $VM_USER =~ ^[A-Za-z][A-Za-z0-9_-]{0,19}$ ]] || die "an account name is letters, digits, - and _, at most 20"
[ "${VM_USER,,}" != administrator ] || die "Administrator is Windows' own account; pick another name"
PASSWORD=$(python -c '
import secrets, string
a = string.ascii_letters + string.digits
while True:
    p = "".join(secrets.choice(a) for _ in range(16))
    if any(c.islower() for c in p) and any(c.isupper() for c in p) and any(c.isdigit() for c in p):
        print(p); break')

echo
echo "About to create VM $VMID ($VM_NAME) on $h: $VM_CORES cores, $VM_MEMORY MB, $VM_DISK_GB GB on $VM_STORAGE,"
echo "from $WIN_ISO, with $VIRTIO_ISO, account $VM_USER. The install takes 15-45 minutes."
confirm "Go ahead?" y || exit 0

ANSWER_ISO=netlab-answer-$VMID.iso
for k in VMID VM_NAME VM_STORAGE VM_CORES VM_MEMORY VM_DISK_GB LAN_BRIDGE ISO_STORAGE ISO_DIR WIN_ISO VIRTIO_ISO VM_USER ANSWER_ISO; do setvar $k; done

# --- The answer CD -------------------------------------------------------------
pve 'command -v genisoimage >/dev/null' || { echo "installing genisoimage on $h"; pve 'apt-get install -y -qq genisoimage >/dev/null'; }
host=$(echo "$VM_NAME" | tr -cd 'A-Za-z0-9-' | cut -c1-15)
sed -e "s/@USER@/$VM_USER/g" -e "s/@PASSWORD@/$PASSWORD/g" -e "s/@NAME@/${host:-NETLAB-WIN}/g" "$NETLAB/vm/autounattend.xml" |
  ssh -o BatchMode=yes "$PVE_HOST" "d=\$(mktemp -d) && cat > \$d/autounattend.xml && genisoimage -quiet -J -R -V NETLABANSWER -o '$ISO_DIR/$ANSWER_ISO' \$d/autounattend.xml && rm -rf \$d"

# --- Install -------------------------------------------------------------------
"$NETLAB/vm/create-vm.sh" || die "the install didn't finish: look at VM $VMID's console in Proxmox"
# The answer file holds the password: out of the drive, off the host.
pve "qm set $VMID --ide1 none,media=cdrom >/dev/null; rm -f '$ISO_DIR/$ANSWER_ISO'"

echo "setting up SSH and the VC++ runtime"
"$NETLAB/vm/guest-exec.sh" "$NETLAB/vm/first-boot.ps1" PubKey="$(cat "$KEY")"
"$NETLAB/vm/guest-exec.sh" "$NETLAB/vm/prepare-game-box.ps1"
ip=$(pve "qm agent $VMID network-get-interfaces" | python -c '
import json, sys
for i in json.load(sys.stdin):
    for a in i.get("ip-addresses", []):
        ip = a["ip-address"]
        if a["ip-address-type"] == "ipv4" and not ip.startswith(("127.", "169.254.")):
            print(ip); sys.exit()')
[ -n "$ip" ] || die "the VM has no address: is $LAN_BRIDGE on a network with DHCP?"

# --- netlab's machine file -----------------------------------------------------
echo
ask m "Its name in netlab (--on <name>)" testbox
f=$NETLAB/local/machines/$m.env
if [ ! -f "$f" ] || confirm "$f exists. Replace it?" n; then
  mkdir -p "$(dirname "$f")"
  printf '# %s, made by vm/setup-windows.sh\nKIND=remote\nSSH=%s@%s\nDIR=C:/netlab\n' "$VM_NAME (VM $VMID)" "$VM_USER" "$ip" > "$f"
fi
ssh -n -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$VM_USER@$ip" hostname >/dev/null && echo "SSH to $VM_USER@$ip works"
mkdir -p "$NETLAB/local/secrets"
printf '%s\n' "$PASSWORD" > "$NETLAB/local/secrets/$VM_NAME.password" && chmod 600 "$NETLAB/local/secrets/$VM_NAME.password"

# --- A GPU, optionally ---------------------------------------------------------
echo
if confirm "Pass a GPU through to it (IOMMU on, and a card the host doesn't display on)?" n; then
  pve "lspci -Dnn" | grep -E 'VGA|3D controller|Display' | nl -w2 -s') '
  ask n "Which one" 1
  GPU=$(pve "lspci -Dnn" | grep -E 'VGA|3D controller|Display' | sed -n "${n}p" | cut -d' ' -f1)
  GPU=${GPU%.*}
  [ -n "$GPU" ] || die "no GPU $n"
  GPU_IDS=$(pve "lspci -nn -s $GPU" | grep -o '\[[0-9a-f]\{4\}:[0-9a-f]\{4\}\]' | tr -d '[]' | paste -sd, -)
  setvar GPU; setvar GPU_IDS
  if pve "lspci -k -s $GPU.0" | grep -q 'in use: vfio-pci'; then
    "$NETLAB/vm/attach-gpu.sh"
    case $GPU_IDS in
    1002:*)
      echo "AMD's driver: the full Adrenalin package URL from AMD's release notes (Enter skips)."
      ask url "Driver URL" ""
      if [ -n "$url" ]; then
        scp -q "$NETLAB/vm/gpu-driver-amd.ps1" "$VM_USER@$ip:C:/netlab/"
        ssh -n "$VM_USER@$ip" "powershell -ExecutionPolicy Bypass -File C:/netlab/gpu-driver-amd.ps1 -Url '$url'"
      fi ;;
    *) echo "Install the card's driver on the VM yourself (its installer, over RDP or SSH)." ;;
    esac
  else
    echo "The host's own driver still has $GPU. Run vm/vfio-host.sh --apply, reboot $h,"
    echo "then vm/attach-gpu.sh (and the driver, see vm/README.md)."
  fi
fi

cat <<EOF

Done. VM $VMID ($VM_NAME) at $ip, logged on as $VM_USER.
  password: $PASSWORD   (also in local/secrets/$VM_NAME.password; git-ignored)
  try it:   ./netlab run opennote --on $m
EOF
