# First setup of a fresh Windows test VM, run through the guest agent:
#   vm/guest-exec.sh vm/first-boot.ps1 PubKey="$(cat ~/.ssh/id_rsa.pub)"
# - OpenSSH server with your key for administrators, PowerShell as its shell;
# - the network marked Private (a home LAN; firewall rules scoped to Private
#   otherwise don't apply);
# - no hibernation file and no automatic Windows Update, so the thin disk
#   doesn't quietly grow by several GB;
# - Setup's copies of the answer file deleted (they hold the password);
# - scripts allowed (RemoteSigned): Windows 10 refuses to run any by default,
#   including the ones the lab copies over.
$ErrorActionPreference = 'Stop'
if (-not $PubKey) { throw 'PubKey= is required' }

$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
if ($cap.State -ne 'Installed') { Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
$keys = 'C:\ProgramData\ssh\administrators_authorized_keys'
New-Item -ItemType Directory -Force C:\ProgramData\ssh | Out-Null
Set-Content -Path $keys -Value $PubKey -Encoding ascii
icacls $keys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Force -PropertyType String `
    -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' | Out-Null
Set-Service sshd -StartupType Automatic
Start-Service sshd
if (Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -EA 0) {
    Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Enabled True -Profile Any
} else {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True `
        -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any | Out-Null
}
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private

# Setup keeps copies of the answer file, password and all.
Remove-Item -Force -EA 0 C:\Windows\Panther\unattend.xml, C:\Windows\Panther\autounattend.xml, C:\Windows\System32\Sysprep\unattend.xml

Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
powercfg /h off
$wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
New-Item -Path $wu -Force | Out-Null
Set-ItemProperty -Path $wu -Name NoAutoUpdate -Value 1 -Type DWord

"sshd: $((Get-Service sshd).Status); address: " +
    ((Get-NetIPAddress -AddressFamily IPv4 | ? IPAddress -notlike '127.*' | ? IPAddress -notlike '169.254*').IPAddress -join ', ')
