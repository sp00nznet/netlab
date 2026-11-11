# Make the test box ready to run games for driving. Run it on the box (over
# SSH) once, after first-boot.ps1:
# - the Visual C++ 2015-2022 runtime (recompiled games link against it);
# - C:\netlab, where the driving mailbox, log and frames live.
# Then run things on it with netlab (--on <machine>).
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Both: x86 recomps (XWIN_ARCH=x86) need the x86 one, and without it they
# die at load with 0xC0000135 (exit 53 from cmd), before printing anything.
foreach ($arch in 'x64', 'x86') {
    $vc = "$env:TEMP\vc_redist.$arch.exe"
    Invoke-WebRequest https://aka.ms/vs/17/release/vc_redist.$arch.exe -OutFile $vc
    $sig = Get-AuthenticodeSignature $vc
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft Corporation') {
        throw "vc_redist.$arch isn't signed by Microsoft ($($sig.Status))"
    }
    $p = Start-Process $vc -ArgumentList '/install', '/quiet', '/norestart' -Wait -PassThru
    Remove-Item $vc
    "vc_redist.${arch}: exit $($p.ExitCode)"
}

New-Item -ItemType Directory -Force C:\netlab, C:\netlab\frames | Out-Null
"logged on: " + ((query user 2>$null) -join ' ')
