/* What MSVC provides that clang-cl declares but doesn't define. setup.sh
 * builds this into farm-compat.lib for x86; clangcl.cmake links it by default.
 *
 * __writefsdword: clang's intrin.h declares it for x86 but there is no
 * builtin, so lifted code's SEH writes to the TIB (fs:[0], StackBase, ...)
 * link as an undefined ___writefsdword. */
#if defined(_M_IX86)
void __writefsdword(unsigned long offset, unsigned long value)
{
    __asm__ volatile("movl %1, %%fs:(%0)" : : "r"(offset), "r"(value) : "memory");
}
#endif
