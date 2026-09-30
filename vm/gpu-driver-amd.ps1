# Install AMD's display driver on the test box, for the passed-through card.
# Run it on the box (over SSH):
#   scp vm/gpu-driver-amd.ps1 Admin@box:C:/netlab/
#   ssh Admin@box "powershell -ExecutionPolicy Bypass -File C:/netlab/gpu-driver-amd.ps1 -Url <driver .exe URL>"
#
# The URL is the full Adrenalin package from AMD's release notes, e.g.
#   https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.7.1-win11-c.exe
# AMD's server wants an amd.com Referer. The package is only extracted, and
# the display driver installed with pnputil: AMD's installer isn't needed.
#
# AMD's consumer driver installs on desktop Windows only. On Windows Server
# its INF never matches (every model section is for the workstation product
# type), which is why the test box runs Windows 10/11.
param([Parameter(Mandatory)] [string] $Url)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$card = Get-PnpDevice -PresentOnly | ? { $_.InstanceId -like 'PCI\VEN_1002*' -and $_.Class -eq 'Display' } | Select -First 1
if (-not $card) { throw 'no AMD display adapter present' }
$dev = [regex]::Match($card.InstanceId, 'DEV_[0-9A-F]{4}').Value

$exe = "$env:TEMP\amd-driver.exe"
Invoke-WebRequest -Uri $Url -OutFile $exe -Headers @{ Referer = 'https://www.amd.com/' } -UserAgent 'Mozilla/5.0'
$sig = Get-AuthenticodeSignature $exe
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Advanced Micro Devices') {
    throw "the download isn't signed by AMD ($($sig.Status))"
}

$p = Start-Process $exe -ArgumentList '/S' -PassThru          # extracts to C:\AMD
if (-not $p.WaitForExit(900000)) { $p | Stop-Process -Force; throw 'extracting timed out' }
$inf = Get-ChildItem C:\AMD -Recurse -Filter *.inf | ? { Select-String -Path $_.FullName -Pattern $dev -Quiet } | Select -First 1
if (-not $inf) { throw "no INF in the package lists $dev" }
pnputil /add-driver $inf.FullName /install | Select -Last 3

Start-Sleep 10
Remove-Item -Recurse -Force C:\AMD, $exe -EA 0
Optimize-Volume -DriveLetter C -ReTrim                        # hand the freed space back to thin storage
Get-CimInstance Win32_VideoController | Select Name, DriverVersion, Status | Format-Table -AutoSize | Out-String
