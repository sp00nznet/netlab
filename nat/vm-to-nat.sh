#!/bin/sh
# Put the test VM behind the NAT bridge (nat/nat-up.sh first): its network
# card moves to NAT_BRIDGE (same MAC), and Windows gets NAT_VM_IP through the
# guest agent, since the bridge runs no DHCP. From your workstation it's then
# reachable only through the host:
#   ssh -J $PVE_HOST $VM_USER@$NAT_VM_IP
# so set JUMP in its local/machines/<name>.env.
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/lab.env"

ssh "$PVE_HOST" "MAC=\$(grep '^net0:' /etc/pve/qemu-server/$VMID.conf | grep -oE '([0-9A-F]{2}:){5}[0-9A-F]{2}'); \
                 qm set $VMID --net0 virtio=\$MAC,bridge=$NAT_BRIDGE >/dev/null && echo moved to $NAT_BRIDGE"

cat > "${TMPDIR:-/tmp}/netlab-ip.ps1" <<'EOF'
$if = (Get-NetAdapter | ? Status -eq 'Up' | Select -First 1).ifIndex
Get-NetIPAddress -InterfaceIndex $if -AddressFamily IPv4 -EA 0 | Remove-NetIPAddress -Confirm:$false -EA 0
Get-NetRoute -InterfaceIndex $if -DestinationPrefix 0.0.0.0/0 -EA 0 | Remove-NetRoute -Confirm:$false -EA 0
Set-NetIPInterface -InterfaceIndex $if -Dhcp Disabled
New-NetIPAddress -InterfaceIndex $if -IPAddress $Ip -PrefixLength $Prefix -DefaultGateway $Gw | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $if -ServerAddresses $Dns
Start-Sleep 3
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -EA 0
"now at $Ip, gateway $Gw"
EOF
"$NETLAB/vm/guest-exec.sh" "${TMPDIR:-/tmp}/netlab-ip.ps1" Ip="$NAT_VM_IP" Prefix="$NAT_PREFIX" Gw="$NAT_GW" Dns="$NAT_DNS"
