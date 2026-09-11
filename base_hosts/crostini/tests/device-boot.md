# Validate on ChromeOS without developer mode

Use normal crosh (`Ctrl+Alt+T`). No ChromeOS root shell, SSH server, custom
kernel or host filesystem access is required. Keep the existing VM intact;
use a new name for a fresh image test. Record the ChromeOS version from
`chrome://version`, the downloaded image artifact/run and its published
checksum. The simulated CI boot does not qualify as this device test.

First collect the current failure without opening a guest shell:

```text
vmc list
vmc logs autofirma
vmc start --help
```

The help must list `--no-shell`. Do not substitute user-provisioning flags
or a guest login if that option is unavailable; record the version/help so
the startup procedure can be adapted. In particular, `--user` belongs to
`vmc start`, not crosh's `vsh` command.

Once the corrected ARM artifact is in Downloads, create a separate VM:

```text
vmc create --vm-type BAGUETTE --size 10G --source /home/chronos/user/MyFiles/Downloads/baguette_rootfs.img.zst autofirma-boot-test
vmc start --vm-type BAGUETTE --no-shell autofirma-boot-test
vmc logs autofirma-boot-test
```

Use that fresh name only if it does not already exist. Record whether start
returns successfully and preserve the complete boot log before attempting
`vsh` or launching an application. If start hangs, collect `vmc logs` from
a second crosh tab. Do not enable lingering or start user services to help
the test pass. Successful registration and user-manager startup must happen
without a login. The no-shell start still performs the normal ChromeOS
registration handshake; it does not replace maitred or garcon.

After recording startup, connect:

```text
vsh autofirma-boot-test penguin
```

Run these **inside the guest**, not at the `crosh>` prompt:

```sh
id
uname -r
cat /proc/cmdline
readlink -f /run/current-system
findmnt -n -o SOURCE,FSTYPE,OPTIONS /opt/google/cros-containers
systemctl --failed --no-pager
systemctl show user@1000.service -p ActiveState -p ActiveEnterTimestampMonotonic
systemctl --user --failed --no-pager
systemctl --user show garcon.service sommelier@0.service sommelier@1.service sommelier-x@0.service sommelier-x@1.service -p Id -p ActiveState -p NRestarts -p ActiveEnterTimestampMonotonic
systemctl --user show-environment
```

Review environment output before sharing it; only the display, runtime
directory and `MOZ_LEGACY_HOME` entries are relevant. These observations
after login supplement the saved pre-login log, rather than proving startup
on their own. If `vsh` fails, preserve that error and the host logs.

Share Downloads through the Files app, put a synthetic test certificate at
`cert.p12`, and launch **Firefox (AutoFirma)** from ChromeOS. Verify import
and an actual signature. Exercise both `cert.password` and the interactive
password dialog in separate fresh sessions. Test clean stop/start, then
host sleep/wake, collecting `vmc logs` and service restart counts each time.
Stop/start discards this AutoFirma guest's tmpfs home, so save test outputs
to the shared folder first. No personal signing certificate is needed.

For the original regression, repeat the no-shell startup procedure with
the original affected image under a different fresh VM name on the same
ChromeOS build. It must fail registration/session startup while the corrected
image succeeds. Do not infer the cause of a different failure from the name
of the image. Keep both logs and artifact identities with the test result.

Normal crosh does not expose all host kernel/tools-disk bytes for hashing.
Record the observable build/kernel/tools mount information and report this
limit; do not claim byte-for-byte host equivalence from version strings.
