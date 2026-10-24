# An Ubuntu 22.04 root (glibc 2.35, gcc 11, CMake 3.22) on a clangcl builder, so
# native Linux builds run on Ubuntu 22.04 / Mint 21 and newer, not just on what
# the builder itself runs (Debian 13, glibc 2.41). Run once per builder:
#   ssh root@builder-clangcl-140 sh -s < builders/clangcl/jammy.sh
# Then a recipe builds inside it with:   BUILD='jammy sh tools/build_unix.sh'
# The container can't make device nodes, so /dev/null and friends are bind
# mounts of the real ones, set up again by `jammy` on every run (idempotent).
set -e
R=/opt/jammy
PKGS="build-essential cmake ninja-build git xz-utils libx11-dev libxext-dev libxrandr-dev
libxcursor-dev libxfixes-dev libxi-dev libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev
wayland-protocols libegl-dev libgl-dev libdrm-dev libgbm-dev libasound2-dev libpulse-dev
libpipewire-0.3-dev libdbus-1-dev libudev-dev"

cat > /usr/local/bin/jammy <<'EOF'
#!/bin/sh
# jammy <command...>: run it in /opt/jammy (Ubuntu 22.04), in the same /work folder.
set -e
R=/opt/jammy
mnt() { mountpoint -q "$2" || mount --bind "$1" "$2"; }
mkdir -p "$R/work"; mnt /work "$R/work"
mountpoint -q "$R/proc" || mount -t proc proc "$R/proc"
for f in null zero random urandom; do [ -e "$R/dev/$f" ] || touch "$R/dev/$f"; mnt "/dev/$f" "$R/dev/$f"; done
cp /etc/resolv.conf "$R/etc/resolv.conf"
exec chroot "$R" /usr/bin/env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/root sh -c "cd '$PWD' && $*"
EOF
chmod +x /usr/local/bin/jammy

if [ ! -x "$R/usr/bin/gcc" ]; then
  apt-get install -y -qq debootstrap ubuntu-keyring >/dev/null
  rm -rf "$R"
  debootstrap --variant=minbase --include=gpgv,ca-certificates --components=main,universe \
    jammy "$R" http://archive.ubuntu.com/ubuntu >/dev/null
  printf 'deb http://archive.ubuntu.com/ubuntu jammy main universe\ndeb http://archive.ubuntu.com/ubuntu jammy-updates main universe\n' \
    > "$R/etc/apt/sources.list"
  mkdir -p /work
  jammy "DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends $(echo $PKGS) >/dev/null"
fi
jammy 'ldd --version | head -1'
