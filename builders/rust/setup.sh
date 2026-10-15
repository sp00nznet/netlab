# Rust builder: stable Rust (rustfmt, clippy) for Linux, and Windows builds
# through cargo-xwin (clang-cl/lld-link against the MSVC CRT and Windows SDK).
# A recipe builds with e.g.
#   . ~/.cargo/env && cargo xwin build --release --target x86_64-pc-windows-msvc
# The CRT/SDK are fetched here once, into ~/.cache/cargo-xwin, which accepts
# Microsoft's licence (as the clangcl kind does).
set -e
apt-get update -qq
apt-get install -y -qq curl ca-certificates git build-essential pkg-config time clang lld llvm >/dev/null
curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal -c rustfmt,clippy -t x86_64-pc-windows-msvc >/dev/null
. /root/.cargo/env
cargo install --locked cargo-xwin >/dev/null 2>&1
# Warm the CRT/SDK cache with a throwaway crate, so the first job doesn't download it.
d=$(mktemp -d) && cargo new -q --bin "$d/warm" &&
  (cd "$d/warm" && XWIN_ACCEPT_LICENSE=1 cargo xwin build -q --release --target x86_64-pc-windows-msvc) && rm -rf "$d"
echo "$(cargo --version); $(cargo xwin --version 2>/dev/null | head -1)"
