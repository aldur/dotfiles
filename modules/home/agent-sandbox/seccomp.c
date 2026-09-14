/* Build-time BPF generator. Bubblewrap loads the filter before exec, so it
 * applies to every descendant and fails closed on kernels without seccomp.
 * Keep ordinary development, including nested sandboxes, working. This is
 * a small denylist, not a general syscall allowlist.
 */
#include <errno.h>
#include <linux/ioprio.h>
#include <seccomp.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/resource.h>
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
     * TIOCSPGRP would let a background sandbox take over the host terminal.
     */
    check(seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(ioctl), 1,
                          SCMP_A1_64(SCMP_CMP_MASKED_EQ, UINT32_MAX, TIOCSTI)));
    check(seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(ioctl), 1,
                          SCMP_A1_64(SCMP_CMP_MASKED_EQ, UINT32_MAX, TIOCLINUX)));
    check(seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(ioctl), 1,
                          SCMP_A1_64(SCMP_CMP_MASKED_EQ, UINT32_MAX, TIOCSPGRP)));

    /* Without bwrap's --new-session, the initial process group can contain
     * callers outside the PID namespace. These special zero forms operate on
     * the inherited kernel process-group object rather than a visible PID.
     */
    check(seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(kill), 1,
                          SCMP_A0(SCMP_CMP_EQ, 0)));
    check(seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(setpriority), 2,
                          SCMP_A0(SCMP_CMP_EQ, PRIO_PGRP),
                          SCMP_A1(SCMP_CMP_EQ, 0)));
    check(seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(ioprio_set), 2,
                          SCMP_A0(SCMP_CMP_EQ, IOPRIO_WHO_PGRP),
                          SCMP_A1(SCMP_CMP_EQ, 0)));

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
