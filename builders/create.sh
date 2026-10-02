#!/bin/sh
# Create a farm builder: a Debian 13 LXC on a Proxmox node, provisioned for one
# kind of build by builders/<kind>/setup.sh. The kind's files are copied to
# /opt/farm-builder/ in the container first, and setup.sh runs from there.
#
# usage: builders/create.sh <kind> <pve-host> <vmid> <storage> [cores] [mem-MB]
#   e.g. builders/create.sh clangcl root@192.0.2.10 140 local-zfs 16 32768
#
# BRIDGE=<bridge>      the LAN bridge (default: LAN_BRIDGE from lab.env, else vmbr0)
# SHARE=<host path>    bind-mounted at /share, where farm/build.sh drops builds.
#                      Its owner must be 100000 (the container's root).
# Then add root@builder-<kind>-<vmid> to farm/builders; the name has to
# resolve from your workstation (the router's DHCP DNS usually does this).
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
[ -f "$NETLAB/lab.env" ] && . "$NETLAB/lab.env"
KIND=$1 PVE=$2 ID=$3 STORE=$4 CORES=${5:-16} MEM=${6:-32768}
[ -n "$STORE" ] && [ -f "$NETLAB/builders/$KIND/setup.sh" ] ||
  { echo "usage: $0 <kind> <pve-host> <vmid> <storage> [cores] [mem-MB]" >&2
    echo "kinds: $(cd "$NETLAB/builders" && ls -d */ | tr -d / | tr '\n' ' ')" >&2; exit 2; }
BRIDGE=${BRIDGE:-${LAN_BRIDGE:-vmbr0}}

ssh "$PVE" sh -s <<END
set -e
# Any Debian 13 template the node has; the newest one offered if it has none.
T=\$(pveam list local | awk '/debian-13-standard.*amd64/ { print \$1 }' | tail -1)
if [ -z "\$T" ]; then
  pveam update >/dev/null
  N=\$(pveam available --section system | awk '/debian-13-standard.*amd64/ { print \$2 }' | tail -1)
  pveam download local "\$N" >/dev/null
  T=local:vztmpl/\$N
fi
pct create $ID "\$T" \
  --hostname builder-$KIND-$ID --cores $CORES --memory $MEM --swap 4096 \
  --rootfs $STORE:64 --net0 name=eth0,bridge=$BRIDGE,ip=dhcp \
  --unprivileged 1 --features nesting=1 \
  --ssh-public-keys /root/.ssh/authorized_keys \
  --description "build farm: $KIND (builders/create.sh)" \
  ${SHARE:+--mp0 $SHARE,mp=/share}
pct start $ID
sleep 8
END
tar -cf - -C "$NETLAB/builders/$KIND" . |
  ssh "$PVE" "pct exec $ID -- sh -c 'mkdir -p /opt/farm-builder && tar --no-same-owner -xf - -C /opt/farm-builder'"
# pct exec's PATH has no /usr/local/bin; setup scripts call what they install there by full path.
ssh "$PVE" "pct exec $ID -- env LC_ALL=C DEBIAN_FRONTEND=noninteractive sh /opt/farm-builder/setup.sh"
ssh "$PVE" "pct exec $ID -- ip -4 -br a show eth0"
