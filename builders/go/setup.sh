# Go builder: Debian's Go toolchain (servers like psnr; CGO off, so the
# binaries are static and run on any Linux host). Small enough to share a
# container with another kind: list it as "node,go" in farm/builders.
set -e
apt-get update -qq
apt-get install -y -qq golang-go git ca-certificates time >/dev/null
echo "$(go version)"
