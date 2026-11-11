# Validate on ChromeOS without developer mode

Use normal crosh (`Ctrl+Alt+T`). You do not need a ChromeOS root shell, an SSH
server, a custom kernel or access to the host filesystem. The simulated CI
boot does not replace this test.

Record the ChromeOS version from `chrome://version`. Record the image
artifact, its CI run and its published checksum.

## Collect the host state

Do not open a guest shell.

```text
vmc list
vmc logs <vm>
vmc start --help
```

The help must list `--no-shell`. If it does not, record the version and the
help text. Do not use user-provisioning flags or a guest login as a
substitute. `--user` is an option of `vmc start`, not of the `vsh` command.

## Start a new VM

Do not change an existing VM. Use a name that does not exist:

```text
vmc create --vm-type BAGUETTE --size 10G --source /home/chronos/user/MyFiles/Downloads/baguette_rootfs.img.zst nixos-boot-test
vmc start --vm-type BAGUETTE --no-shell nixos-boot-test
vmc logs nixos-boot-test
```

- Record if `vmc start` returns successfully.
- Save the full boot log before you use `vsh` or start an application.
- If the start does not return, collect `vmc logs` from a second crosh tab.
- Do not enable lingering. Do not start user services manually. Registration
  and the user manager must start without a login.

A start with `--no-shell` does the normal ChromeOS registration handshake. It
does not replace maitred or garcon.

## Examine the guest

Connect after you save the boot log:

```text
vsh nixos-boot-test penguin
```

If `vsh` fails, save the error and the host logs. Run these commands **in the
guest**, not at the `crosh>` prompt:

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

Examine the environment output before you share it. Only the display and
runtime directory entries are relevant. These results add to the saved boot
log. They do not prove a correct startup by themselves.

## Applications, restart and sleep

1. Use the applications of the image as its README tells you.
2. Stop the VM, then start it.
3. Let the host sleep, then wake it.

After each step, collect `vmc logs` and the service restart counts. A guest
with a tmpfs home loses its files when it stops. Save the test outputs to the
shared folder first.

## Results

Keep the logs and the artifact identity with the test result.

Normal crosh cannot read all bytes of the host kernel and tools disk. Record
the build, kernel and tools mount data that you can see, and report this
limit. Version strings do not prove that the host is byte-for-byte equal.
