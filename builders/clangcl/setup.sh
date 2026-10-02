# clang-cl builder: clang-cl + lld-link and an xwin splat of the MSVC CRT and
# Windows SDK (x86 and x64), so MSVC-ABI Windows programs build on Linux.
# Builds go through /opt/clangcl.cmake (clangcl.cmake here):
#
#   cmake -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/clangcl.cmake \
#         -DXWIN_ARCH=x86|x86_64 -DCMAKE_BUILD_TYPE=Release
#
# Running xwin accepts the Microsoft CRT/SDK license (--accept-license).
set -e
XWIN=0.10.0
apt-get update -qq
apt-get install -y -qq clang lld llvm cmake ninja-build python3 git curl ca-certificates rsync time >/dev/null
ln -sf "$(ls /usr/bin/clang-cl-* | sort -V | tail -1)" /usr/bin/clang-cl
cd /tmp
curl -fsSL "https://github.com/Jake-Shadle/xwin/releases/download/$XWIN/xwin-$XWIN-x86_64-unknown-linux-musl.tar.gz" | tar xz
install "xwin-$XWIN-x86_64-unknown-linux-musl/xwin" /usr/local/bin/xwin
/usr/local/bin/xwin --accept-license --arch x86,x86_64 --cache-dir /opt/xwin-cache splat --output /opt/xwin
rm -rf /opt/xwin-cache xwin-$XWIN-*
cp /opt/farm-builder/clangcl.cmake /opt/clangcl.cmake
# farm-compat.lib: MSVC intrinsics clang-cl declares but doesn't define.
clang-cl --target=i686-pc-windows-msvc /c /O2 /Fo/tmp/msvc-compat.obj -- /opt/farm-builder/msvc-compat.c
llvm-lib /out:/opt/xwin/crt/lib/x86/farm-compat.lib /tmp/msvc-compat.obj
