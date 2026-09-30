#!/usr/bin/env python3
# mkunattend.py <autounattend.xml> <out.xml>
# Copies an autounattend.xml, made independent of drive letters, for
# vm/build-setup-iso.sh. It expects the layout of a common Proxmox answer file
# (virtio driver paths and first-logon installers on E:):
# - the WinPE driver paths (E:\...) go: the VM installs to a SATA disk, which
#   needs no driver during setup;
# - the first-logon commands that run E:\virtio-win-guest-tools.exe and the
#   guest agent MSI look for them on D: through G: instead.
# The original file is only read.
import re, sys

src, dst = sys.argv[1], sys.argv[2]
x = open(src, encoding='utf-8').read()

# Drop the PnpCustomizationsWinPE component (the E:\ driver paths).
x, n = re.subn(r'<component name="Microsoft-Windows-PnpCustomizationsWinPE".*?</component>\s*', '', x, flags=re.S)
assert n == 1, 'driver-path component not found'

tools = 'cmd /c for %d in (D E F G) do if exist %d:\\virtio-win-guest-tools.exe %d:\\virtio-win-guest-tools.exe /S'
agent = 'cmd /c for %d in (D E F G) do if exist %d:\\guest-agent\\qemu-ga-x86_64.msi msiexec /i %d:\\guest-agent\\qemu-ga-x86_64.msi /qn'
old_tools = 'cmd /c if exist E:\\virtio-win-guest-tools.exe E:\\virtio-win-guest-tools.exe /S'
old_agent = 'cmd /c if exist E:\\guest-agent\\qemu-ga-x86_64.msi msiexec /i E:\\guest-agent\\qemu-ga-x86_64.msi /qn'
assert old_tools in x and old_agent in x, 'first-logon commands not found'
x = x.replace(old_tools, tools).replace(old_agent, agent)
assert 'E:\\' not in x, 'a drive-letter path is left'

open(dst, 'w', encoding='utf-8').write(x)
print('ok')
