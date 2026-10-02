# Node builder: Node 20 (electron-builder's native modules break on newer),
# with what electron-builder needs for Linux AppImage and deb packages.
set -e
NODE=${NODE:-20}
apt-get update -qq
apt-get install -y -qq curl ca-certificates git build-essential python3 time \
  libfuse2t64 fakeroot dpkg rpm xz-utils libsecret-1-dev libudev-dev >/dev/null
curl -fsSL "https://deb.nodesource.com/setup_$NODE.x" | bash - >/dev/null
apt-get install -y -qq nodejs >/dev/null
echo "node $(node --version), npm $(npm --version)"
