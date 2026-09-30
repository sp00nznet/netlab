#!/bin/sh
# Bring the test VM back from the NAT bridge to the LAN: its card moves to
# LAN_BRIDGE and Windows goes back to DHCP (guest agent). Prints its new
# address.
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/lab.env"

ssh "$PVE_HOST" "MAC=\$(grep '^net0:' /etc/pve/qemu-server/$VMID.conf | grep -oE '([0-9A-F]{2}:){5}[0-9A-F]{2}'); \
                 qm set $VMID --net0 virtio=\$MAC,bridge=$LAN_BRIDGE >/dev/null && echo moved to $LAN_BRIDGE"

cat > "${TMPDIR:-/tmp}/netlab-dhcp.ps1" <<'EOF'
$if = (Get-NetAdapter | ? Status -eq 'Up' | Select -First 1).ifIndex
Get-NetRoute -InterfaceIndex $if -DestinationPrefix 0.0.0.0/0 -EA 0 | Remove-NetRoute -Confirm:$false -EA 0
Get-NetIPAddress -InterfaceIndex $if -AddressFamily IPv4 -EA 0 | Remove-NetIPAddress -Confirm:$false -EA 0
Set-NetIPInterface -InterfaceIndex $if -Dhcp Enabled
Set-DnsClientServerAddress -InterfaceIndex $if -ResetServerAddresses
ipconfig /renew | Out-Null
Start-Sleep 5
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -EA 0
"now at " + ((Get-NetIPAddress -InterfaceIndex $if -AddressFamily IPv4).IPAddress -join ', ')
EOF
"$NETLAB/vm/guest-exec.sh" "${TMPDIR:-/tmp}/netlab-dhcp.ps1"
