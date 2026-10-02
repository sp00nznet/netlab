# clang-cl + lld-link against an xwin splat: MSVC-ABI Windows builds on Linux.
#   cmake -DCMAKE_TOOLCHAIN_FILE=/opt/clangcl.cmake -DXWIN_ARCH=x86|x86_64 ...
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_VERSION 10.0)
if(NOT XWIN_ARCH)
  set(XWIN_ARCH x86_64)
endif()
set(XWIN /opt/xwin)
if(XWIN_ARCH STREQUAL "x86")
  set(CMAKE_SYSTEM_PROCESSOR X86)
  set(_target i686-pc-windows-msvc)
else()
  set(CMAKE_SYSTEM_PROCESSOR AMD64)
  set(_target x86_64-pc-windows-msvc)
endif()
# toolchain files are re-read in try_compile projects
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES XWIN_ARCH)

set(CMAKE_C_COMPILER clang-cl)
set(CMAKE_CXX_COMPILER clang-cl)
set(CMAKE_LINKER lld-link)
set(CMAKE_AR llvm-lib)
set(CMAKE_RC_COMPILER llvm-rc)
set(CMAKE_MT llvm-mt)

set(_inc "/imsvc${XWIN}/crt/include /imsvc${XWIN}/sdk/include/ucrt /imsvc${XWIN}/sdk/include/um /imsvc${XWIN}/sdk/include/shared")
set(CMAKE_C_FLAGS_INIT "--target=${_target} ${_inc}")
set(CMAKE_CXX_FLAGS_INIT "--target=${_target} ${_inc}")
set(_lib "/libpath:${XWIN}/crt/lib/${XWIN_ARCH} /libpath:${XWIN}/sdk/lib/um/${XWIN_ARCH} /libpath:${XWIN}/sdk/lib/ucrt/${XWIN_ARCH}")
set(CMAKE_EXE_LINKER_FLAGS_INIT "${_lib}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_lib}")
set(CMAKE_MODULE_LINKER_FLAGS_INIT "${_lib}")
# ponytail: no debug CRT in the splat (msvcrtd.lib); Debug builds need `xwin splat --include-debug-libs`
set(CMAKE_TRY_COMPILE_CONFIGURATION Release)
