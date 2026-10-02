# A ps3recomp game: the runtime library from the ps3recomp checkout (the first
# dep), then the game against it. Runs on the builder in /work, appended to the
# job's variables by farm/build.sh.
set -e -o pipefail
RT=${DEPS%% *}
[ -n "$RT" ] || { echo "ps3recomp: pass the ps3recomp checkout as the first dep" >&2; exit 2; }
cd "/work/$RT"
cmake -S . -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/clangcl.cmake -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
cd "/work/$GAME"
cmake -S . -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/clangcl.cmake \
  -DCMAKE_BUILD_TYPE=Release -DPS3RECOMP_DIR="/work/$RT" $CMAKE_ARGS
/usr/bin/time -f "build wall %e s" cmake --build build -j"$(nproc)"
find build -maxdepth 1 \( -name '*.exe' -o -name '*.pdb' -o -name '*.map' \) |
  sed "s|^|$GAME/|" > "/work/.artifacts-$JOB"
