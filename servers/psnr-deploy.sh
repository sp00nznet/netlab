#!/bin/sh
# psnr-deploy.sh <psnr checkout> <user@linux-host> [psnr flags...]
# Build psnr (https://github.com/sp00nznet/psnr) for Linux and run it on a
# lab host, in the background, replacing one already running there:
#
#   servers/psnr-deploy.sh ~/src/psnr root@<lab-host> -relay
#
# Put it where both sides of a test can reach it: for a player behind the
# NAT bridge, a host on the LAN, not the NAT host itself. Status page:
# ssh -L 36101:127.0.0.1:36101 <host>, then http://127.0.0.1:36101/.
set -e
src=$1 host=$2
[ -n "$src" ] && [ -n "$host" ] || { sed -n '2,11p' "$0"; exit 2; }
shift 2

out=${TMPDIR:-/tmp}/psnr-linux
(cd "$src/server" && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o "$out" .)
ssh "$host" 'mkdir -p /root/psnr'
scp -q "$out" "$host:/root/psnr/psnr.new"
# pkill -x matches the process name only: -f would also match this command.
ssh "$host" "pkill -x psnr; sleep 1; cd /root/psnr && mv psnr.new psnr && chmod +x psnr && \
             (nohup ./psnr -v -http 127.0.0.1:36101 $* > psnr.log 2>&1 < /dev/null &) ; sleep 1; cat psnr.log"
