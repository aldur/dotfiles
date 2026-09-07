/* Harmless policy probes: no real terminal or keyring is ever accessed. */
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <unistd.h>

int main(int argc, char **argv) {
    int expected = argc == 2 && strcmp(argv[1], "baseline") == 0 ? EBADF : EPERM;
    const unsigned long requests[] = {
        TIOCSTI, TIOCLINUX,
#if UINTPTR_MAX > UINT32_MAX
        (1UL << 32) | TIOCSTI, (1UL << 32) | TIOCLINUX,
#endif
    };
    for (size_t i = 0; i < sizeof(requests) / sizeof(requests[0]); i++) {
        errno = 0;
        long result = syscall(SYS_ioctl, -1, requests[i], NULL);
        if (result != -1 || errno != expected) {
            fprintf(stderr, "ioctl policy: expected %s, got %s\n",
                    strerror(expected), strerror(errno));
            return 1;
        }
    }
    if (expected == EPERM) {
        errno = 0;
        if (syscall(SYS_keyctl, -1, 0, 0, 0, 0) != -1 || errno != EPERM) {
            fputs("keyring policy must return EPERM\n", stderr);
            return 1;
        }
    }
    return 0;
}
