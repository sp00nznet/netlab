# mingw builder: GCC for Windows (mingw-w64, x86_64) and SDL2 built for it,
# for projects whose Windows build is a GNU Makefile rather than MSVC/CMake.
# Small enough to share a container with clangcl: farm/builders lists such a
# builder as `clangcl,mingw`.
#
#   make CC=x86_64-w64-mingw32-gcc PKG_CONFIG=mingw-pkg-config
#
# mingw-pkg-config is pkg-config pointed at the SDL2 tree only, so a cross
# build never picks up the builder's own Linux libraries.
set -e
SDL=${SDL:-2.32.10}
apt-get update -qq
apt-get install -y -qq gcc-mingw-w64-x86-64-posix g++-mingw-w64-x86-64-posix \
  make pkgconf python3 git curl ca-certificates time >/dev/null
update-alternatives --set x86_64-w64-mingw32-gcc /usr/bin/x86_64-w64-mingw32-gcc-posix >/dev/null
rm -rf /opt/sdl2-mingw && mkdir -p /opt/sdl2-mingw
curl -fsSL "https://github.com/libsdl-org/SDL/releases/download/release-$SDL/SDL2-devel-$SDL-mingw.tar.gz" |
  tar xz -C /opt/sdl2-mingw --strip-components=2 "SDL2-$SDL/x86_64-w64-mingw32"
cat > /usr/local/bin/mingw-pkg-config <<'EOF'
#!/bin/sh
PKG_CONFIG_LIBDIR=/opt/sdl2-mingw/lib/pkgconfig exec pkg-config --define-prefix "$@"
EOF
chmod +x /usr/local/bin/mingw-pkg-config
echo "$(x86_64-w64-mingw32-gcc --version | head -1), SDL2 $(mingw-pkg-config --modversion sdl2)"
