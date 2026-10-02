# Godot builder: headless Godot editors with their Windows and Linux export
# templates, one per minor version, as godot-<major.minor> (godot-4.6, ...).
# A recipe exports with e.g.
#   godot-4.6 --headless --path . --import
#   godot-4.6 --headless --path . --export-release "Windows Desktop" build/Game.exe
# GODOT_VERSIONS picks the releases (the newest patch of each minor you use).
set -e
GODOT_VERSIONS=${GODOT_VERSIONS:-"4.3-stable 4.6.3-stable 4.7.2-stable"}
apt-get update -qq
apt-get install -y -qq curl unzip ca-certificates git git-lfs time fontconfig libfontconfig1 >/dev/null
for v in $GODOT_VERSIONS; do
  num=${v%-stable}; minor=$(echo "$num" | cut -d. -f1-2)
  d=/opt/godot/$num
  url=https://github.com/godotengine/godot/releases/download/$v
  mkdir -p "$d" && cd "$d"
  curl -fsSL -o g.zip "$url/Godot_v${v}_linux.x86_64.zip" && unzip -oq g.zip && rm g.zip
  ln -sf "$d/Godot_v${v}_linux.x86_64" "/usr/local/bin/godot-$minor"
  # Templates go where the editor looks: <version>.stable under the user's data dir.
  t=/root/.local/share/godot/export_templates/$num.stable
  mkdir -p "$t"
  curl -fsSL -o t.tpz "$url/Godot_v${v}_export_templates.tpz"
  unzip -oq -j t.tpz 'templates/windows_*x86_64*' 'templates/linux_*x86_64' 'templates/version.txt' -d "$t"
  rm t.tpz
  echo "godot-$minor: $("/usr/local/bin/godot-$minor" --headless --version 2>/dev/null | tail -1)"
done
