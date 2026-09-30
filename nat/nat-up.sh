#!/bin/sh
# A home router on the Proxmox host: a bridge with no physical port
# (NAT_BRIDGE), masqueraded out LAN_BRIDGE, that drops unsolicited UDP on the
# game ports like a real home router does. Runtime only: gone on a host
# reboot, and nat/nat-down.sh removes it. Every rule carries the comment
# "netlab-nat" so it can be removed exactly.
#
# A VM moves behind it with nat/vm-to-nat.sh.
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/lab.env"

ssh "$PVE_HOST" sh -s <<EOF
set -e
C="-m comment --comment netlab-nat"
NET=\$(python3 -c "import ipaddress; print(ipaddress.ip_interface('$NAT_GW/$NAT_PREFIX').network)")
ip link show $NAT_BRIDGE >/dev/null 2>&1 || {
  ip link add $NAT_BRIDGE type bridge
  ip addr add $NAT_GW/$NAT_PREFIX dev $NAT_BRIDGE
  ip link set $NAT_BRIDGE up
}
sysctl -q net.ipv4.ip_forward=1
add() { t=\$1; shift; iptables -t \$t -C "\$@" \$C 2>/dev/null || iptables -t \$t -I "\$@" \$C; }
add nat POSTROUTING -s \$NET -o $LAN_BRIDGE -j MASQUERADE
# FORWARD often defaults to DROP (Docker sets that): let the home network out,
# and replies back in.
add filter FORWARD -i $NAT_BRIDGE -o $LAN_BRIDGE -j ACCEPT
add filter FORWARD -i $LAN_BRIDGE -o $NAT_BRIDGE -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
# A real router drops unsolicited traffic from outside. It matters: Linux
# only records a connection for a packet it accepts, and an accepted early
# punch from a peer holds the port, so the VM's own first packet out gets a
# different public port than the one psnr handed out.
add filter INPUT -i $LAN_BRIDGE -p udp --dport $UDP_DROP_PORTS -m conntrack --ctstate NEW -j DROP
iptables-save | grep -c netlab-nat | xargs echo "rules:"
EOF
