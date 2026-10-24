# macOS builder: a Mac (or macOS VM) for native Mac builds, arm64 or x86_64.
# Not a container: builders/create.sh can't make one. Run this once on the Mac
# as the account farm/build.sh logs in as (an admin; sudo asks once):
#   scp builders/macos/setup.sh <user>@<mac>: && ssh -t <user>@<mac> sh setup.sh
# Then add "<user>@<mac> macos" to farm/builders and reboot the Mac once, so
# /work exists. Needs Xcode's command line tools (xcode-select --install).
set -e
xcode-select -p >/dev/null || { echo "Xcode's command line tools first: xcode-select --install" >&2; exit 1; }
BREW=/opt/homebrew/bin/brew; [ -x "$BREW" ] || BREW=/usr/local/bin/brew
[ -x "$BREW" ] || /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
[ -x /opt/homebrew/bin/brew ] && BREW=/opt/homebrew/bin/brew
# A farm job's ssh is a non-login zsh: Homebrew has to be on its PATH.
grep -q "brew shellenv" ~/.zshenv 2>/dev/null || echo "eval \"\$($BREW shellenv)\"   # netlab farm" >> ~/.zshenv
eval "$($BREW shellenv)"
# gnu-time: the toolsets time builds with GNU time's -f (gtime here).
HOMEBREW_NO_AUTO_UPDATE=1 brew install -q cmake ninja pkgconf sdl2 sdl2_ttf ffmpeg gnu-time
# The workspace is /work, and the system volume is read-only: a synthetic
# link to ~/work, which macOS makes at boot (hence the reboot).
mkdir -p ~/work
grep -q "^work" /etc/synthetic.conf 2>/dev/null ||
  printf 'work\t%s\n' "${HOME#/}/work" | sudo tee -a /etc/synthetic.conf >/dev/null
[ -d /work ] && echo "macos builder ready" || echo "macos builder ready after a reboot (/work)"
