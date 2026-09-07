/* Build-time BPF generator. Bubblewrap loads the filter before exec, so it
 * applies to every descendant and fails closed on kernels without seccomp.
 * Keep ordinary development, including nested sandboxes, working. This is
 * a small denylist, not a general syscall allowlist.
 */
#include <errno.h>
#include <seccomp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static void check(int result) {
    if (result < 0) {
        fprintf(stderr, "agent-sandbox seccomp: %s\n", strerror(-result));
        exit(EXIT_FAILURE);
    }
}

int main(void) {
    scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_ALLOW);
    if (ctx == NULL)
        return EXIT_FAILURE;

    /* Add compatible ABIs before rules; unsupported ABIs retain libseccomp's
     * default kill action. All enabled ABIs receive the same restrictions.
     */
#if defined(__x86_64__)
    check(seccomp_arch_add(ctx, SCMP_ARCH_X86));
    check(seccomp_arch_add(ctx, SCMP_ARCH_X32));
#elif defined(__aarch64__)
    check(seccomp_arch_add(ctx, SCMP_ARCH_ARM));
#endif

    /* ioctl's request is an unsigned int in the kernel. Ignore upper bits,
     * while leaving normal terminal operations (size, modes, input) alone.
     */
    check(seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(ioctl), 1,
                          SCMP_A1_64(SCMP_CMP_MASKED_EQ, UINT32_MAX, TIOCSTI)));
    check(seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(ioctl), 1,
                          SCMP_A1_64(SCMP_CMP_MASKED_EQ, UINT32_MAX, TIOCLINUX)));

    /* Do not inherit access to the host user's kernel keyrings, or expose
     * kernel instrumentation interfaces that normal agent work does not need.
     */
    const int denied[] = {
        SCMP_SYS(add_key), SCMP_SYS(request_key), SCMP_SYS(keyctl),
        SCMP_SYS(bpf), SCMP_SYS(perf_event_open), SCMP_SYS(userfaultfd),
    };
    for (size_t i = 0; i < sizeof(denied) / sizeof(denied[0]); i++)
        check(seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), denied[i], 0));

    check(seccomp_export_bpf(ctx, STDOUT_FILENO));
    seccomp_release(ctx);
    return EXIT_SUCCESS;
}
