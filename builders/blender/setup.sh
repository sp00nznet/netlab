# Blender builder: headless Blender for batch renders and scripted asset work,
# as blender-<major.minor> (blender-5.0, ...). No GPU: EEVEE runs on Mesa's
# llvmpipe through EGL, so give it cores. A recipe renders with e.g.
#   blender-5.0 -b --python-exit-code 1 -P tools/render.py -- out/
# BLENDER_VERSIONS picks the releases (the exact patch your files are made with).
set -e
BLENDER_VERSIONS=${BLENDER_VERSIONS:-"5.0.1"}
apt-get update -qq
apt-get install -y -qq curl xz-utils ca-certificates git time python3 python3-numpy python3-pil \
  libegl1 libegl-mesa0 libgl1 libglx-mesa0 libgl1-mesa-dri libgbm1 \
  libx11-6 libxi6 libxxf86vm1 libxfixes3 libxrender1 libxkbcommon0 libsm6 libice6 libxext6 libdbus-1-3 >/dev/null
for v in $BLENDER_VERSIONS; do
  minor=$(echo "$v" | cut -d. -f1-2)
  mkdir -p /opt/blender && cd /opt/blender
  curl -fsSL "https://download.blender.org/release/Blender$minor/blender-$v-linux-x64.tar.xz" | tar -xJ
  ln -sf "/opt/blender/blender-$v-linux-x64/blender" "/usr/local/bin/blender-$minor"
  echo "blender-$minor: $("/usr/local/bin/blender-$minor" -b --version 2>/dev/null | head -1)"
done
