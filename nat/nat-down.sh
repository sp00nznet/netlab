#!/bin/sh
# Undo nat/nat-up.sh: every "netlab-nat" rule and the bridge. Move the VM
# back to the LAN first (nat/vm-to-lan.sh), or it's left without a network.
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/lab.env"

ssh "$PVE_HOST" sh -s <<EOF
for t in nat filter; do
  iptables-save -t \$t | grep -- '--comment netlab-nat' | sed 's/^-A /-D /' | while read -r rule; do
    eval iptables -t \$t \$rule
  done
done
ip link show $NAT_BRIDGE >/dev/null 2>&1 && ip link del $NAT_BRIDGE
echo "rules left: \$(iptables-save | grep -c netlab-nat)"
EOF
