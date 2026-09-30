#!/bin/sh
# guest-exec.sh <script.ps1> [Name=value ...]
# Run a PowerShell script inside the VM through the QEMU guest agent, as
# SYSTEM. No network or login needed, so it works before SSH is set up and
# while the VM's network is being changed. Name=value pairs become
# $Name = 'value' lines ahead of the script.
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
. "$NETLAB/lab.env"
script=$1; shift

enc=$(python - "$script" "$@" <<'EOF'
import base64, sys
path, params = sys.argv[1], sys.argv[2:]
head = ''.join("$%s = '%s'\n" % (p.split('=', 1)[0], p.split('=', 1)[1].replace("'", "''")) for p in params)
body = open(path, encoding='utf-8').read()
print(base64.b64encode((head + body).encode('utf-16-le')).decode())
EOF
)
ssh "$PVE_HOST" "qm guest exec $VMID --timeout 1800 -- powershell -NoProfile -EncodedCommand $enc" |
  python -c "import json,sys; d=json.load(sys.stdin); sys.stdout.write(d.get('out-data','')); sys.stderr.write(d.get('err-data','') if d.get('exitcode') else ''); sys.exit(d.get('exitcode') or 0)"
