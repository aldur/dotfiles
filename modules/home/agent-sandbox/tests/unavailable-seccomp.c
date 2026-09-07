/* Simulate a kernel where installing an additional seccomp filter fails. */
#include <errno.h>
#include <seccomp.h>
#include <sys/prctl.h>
#include <unistd.h>

int main(void) {
    scmp_filter_ctx ctx = seccomp_init(SCMP_ACT_ALLOW);
    if (ctx == NULL)
        return 1;
    if (seccomp_rule_add(ctx, SCMP_ACT_ERRNO(ENOSYS), SCMP_SYS(seccomp), 0) < 0 ||
        seccomp_rule_add(ctx, SCMP_ACT_ERRNO(ENOSYS), SCMP_SYS(prctl), 1,
                         SCMP_A0(SCMP_CMP_EQ, PR_SET_SECCOMP)) < 0 ||
        seccomp_export_bpf(ctx, STDOUT_FILENO) < 0)
        return 1;
    seccomp_release(ctx);
    return 0;
}
