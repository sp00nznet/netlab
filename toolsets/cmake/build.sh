# A CMake game built with clang-cl for Windows: pcrecomp, xboxrecomp and any
# other toolkit whose game is one CMake project. Runs on the builder in /work,
# appended to the job's variables by farm/build.sh. Release by default;
# CMAKE_ARGS come later and win (-DXWIN_ARCH=x86, -DGEN_OPT=/O1, ...).
set -e -o pipefail
cd "/work/$GAME"
cmake -S . -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=/opt/clangcl.cmake \
  -DCMAKE_BUILD_TYPE=Release $CMAKE_ARGS
/usr/bin/time -f "build wall %e s" cmake --build build -j"$(nproc)"
# Games put the exe in build/ or bin/ (burnout3).
find build bin -maxdepth 1 \( -name '*.exe' -o -name '*.pdb' -o -name '*.map' \) 2>/dev/null |
  sed "s|^|$GAME/|" > "/work/.artifacts-$JOB"
