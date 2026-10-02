#!/bin/sh
# Create a clang-cl builder: a Debian 13 LXC with clang-cl + lld-link and an
# xwin splat of the MSVC CRT and Windows SDK (x86 and x64), so MSVC-ABI
# Windows hosts build on Linux. Builds go through builders/clangcl.cmake:
#
#   cmake -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/clangcl.cmake \
#         -DXWIN_ARCH=x86|x86_64 -DCMAKE_BUILD_TYPE=RelWithDebInfo
#
# usage: builders/create-clangcl.sh <pve-host> <vmid> <storage> [cores] [mem-MB]
#   e.g. builders/create-clangcl.sh root@192.0.2.10 140 fast 16 32768
# Running xwin accepts the Microsoft CRT/SDK license (--accept-license).
# SHARE=<host path> bind-mounts it at /share, where farm/build.sh drops builds:
#   /mnt/pve/scratch/work on pve-a, /tank/scratch/work on pve-b.
# Its owner must be 100000 (the container's root). Then add the builder to
# farm/builders as root@builder-clangcl-<vmid>.
set -e
NETLAB=$(cd "$(dirname "$0")/.." && pwd)
PVE=$1 ID=$2 STORE=$3 CORES=${4:-16} MEM=${5:-32768}
[ -n "$STORE" ] || { echo "usage: $0 <pve-host> <vmid> <storage> [cores] [mem-MB]" >&2; exit 2; }
XWIN=0.10.0

ssh "$PVE" sh -s <<END
set -e
pct create $ID local:vztmpl/debian-13-standard_13.0-0_amd64.tar.zst \
  --hostname builder-clangcl-$ID --cores $CORES --memory $MEM --swap 4096 \
  --rootfs $STORE:64 --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --nameserver "192.0.2.1 1.1.1.1" --unprivileged 1 --features nesting=1 \
  --ssh-public-keys /root/.ssh/authorized_keys \
  --description "build farm: clang-cl + xwin (builders/create-clangcl.sh)" \
  ${SHARE:+--mp0 $SHARE,mp=/share}
pct start $ID
sleep 8
END
scp -q "$NETLAB/builders/clangcl.cmake" "$PVE:/tmp/clangcl-$ID.cmake"
ssh "$PVE" "pct push $ID /tmp/clangcl-$ID.cmake /opt/clangcl.cmake && rm /tmp/clangcl-$ID.cmake"
ssh "$PVE" pct exec "$ID" -- sh -s <<END
set -e
export LC_ALL=C DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq clang lld llvm cmake ninja-build python3 git curl ca-certificates rsync time >/dev/null
ln -sf clang-cl-19 /usr/bin/clang-cl
cd /tmp
curl -fsSL https://github.com/Jake-Shadle/xwin/releases/download/$XWIN/xwin-$XWIN-x86_64-unknown-linux-musl.tar.gz | tar xz
install xwin-$XWIN-x86_64-unknown-linux-musl/xwin /usr/local/bin/xwin
xwin --accept-license --arch x86,x86_64 --cache-dir /opt/xwin-cache splat --output /opt/xwin
rm -rf /opt/xwin-cache xwin-$XWIN-*
ip -4 -br a show eth0
END
