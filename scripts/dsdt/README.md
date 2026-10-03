# S3 (deep) sleep on the Yoga 7i via DSDT override

The Yoga 7 14ITL5 BIOS hides S3 sleep ("Modern Standby" / s2idle only) by
setting `SS3 = Zero` in the DSDT, although the firmware implements S3. The fix
is to override the DSDT from the initramfs with a patched copy:
https://wiki.archlinux.org/title/Lenovo_Yoga_7i#Activating_S3_sleep

## How it works, end to end

1. `scripts/dsdt/extract-dsdt.sh` (host, sudo) dumps the firmware DSDT;
   `scripts/dsdt/patch-dsdt.sh` (distrobox, `acpica-tools`) sets
   `SS3 = One`, bumps the OEM revision, recompiles and drops
   `ntb-rootfs/etc/dracut.conf.d/yoga7i-acpi/DSDT.aml`.
2. `task build-ntb` passes `MACHINE=ntb`; `build.sh` then merges
   `ntb-rootfs/` into the image, enables `dsdt-override-check.service`, and
   runs dracut in the build container, **overwriting** the initramfs the base
   image already ships at `/usr/lib/modules/<kver>/initramfs.img`.
3. At deploy, rpm-ostree does **not** regenerate anything for a pure
   container-image origin; libostree deploys the image's
   `/usr/lib/modules/<kver>/initramfs.img` verbatim (paired with the kernel in
   the same directory).
4. The kernel applies the initrd ACPI table override during early boot.
5. `mem_sleep_default=deep` karg (per-machine, set once) makes deep the
   default: `sudo rpm-ostree kargs --append=mem_sleep_default=deep`.
6. `dsdt-override-check.service` runs at every boot and fails visibly if the
   override is not active or the firmware DSDT changed.

## Hard requirements (each of these cost us hours)

- **Secure Boot must be OFF.** With Secure Boot on, the kernel is in
  lockdown=integrity and `acpi_table_upgrade()` bails out with
  `security_locked_down(LOCKDOWN_ACPI_TABLES)` — dmesg shows
  `kernel is locked down, ignoring table override`, and the override is
  silently ignored. A custom kernel with `CONFIG_ACPI_CUSTOM_DSDT` would be
  the only alternative; we chose disabling Secure Boot.
- **The override's OEM revision must be GREATER than the firmware table's.**
  The kernel matches overrides by (signature, OEM ID, OEM Table ID) and only
  accepts them if `existing_table->oem_revision < table->oem_revision`
  (`acpi_table_initrd_override()`, drivers/acpi/tables.c). This is why
  `patch-dsdt.sh` bumps `0x00000002` → `0x00000003` and then verifies the
  compiled AML header at offset 24 — an assertion added after a printf bug
  silently skipped the bump once.
- **The initramfs must live at `/usr/lib/modules/<kver>/initramfs.img`.**
  libostree's deploy-time kernel layout pairs the kernel
  (`/usr/lib/modules/<kver>/vmlinuz`) with an `initramfs.img` in the *same
  directory*; a copy in `/usr/lib/ostree-boot/` is silently ignored when the
  modules fast path finds the kernel. The uBlue base image already ships an
  initramfs there (built by its pipeline), so `build.sh` must overwrite that
  exact file — adding the table anywhere else has no effect.
- **For a pure container-image origin, rpm-ostree never regenerates the
  initramfs at deploy.** Local assembly (and hence client-side dracut) only
  happens when the origin has `regenerate-initramfs`/`initramfs-etc` or
  layered packages (`may_require_local_assembly()`, rust/src/treefile.rs).
  Whatever the image ships at the modules path is what boots.
- **`/etc` is per-deployment.** A dracut conf created while booted in one
  deployment is invisible when regenerating from/for another deployment.
- **Each boot entry costs ~260MB on /boot** (initramfs ~240MB + vmlinuz).
  When `/boot` fills up, the deployment fails to finalize with
  `Installing kernel: regfile copy: No space left on device` and
  `rpm-ostree status` shows
  `failed to finalize previous deployment`. Fix: free space by unpinning and
  cleaning old deployments (`ostree admin pin --unpin <n>` +
  `rpm-ostree cleanup`), then reboot — the staged deployment is finalized by
  `ostree-finalize-staged.service` on the next boot.

## Troubleshooting playbook

Symptom: `mem_sleep` lacks `deep`, and/or `dsdt-override-check.service` fails
with "the DSDT override is NOT active".

1. `sudo dmesg | grep -i 'table upgrade'` — absence means the kernel never saw
   the table (success looks like `Table Upgrade: override [DSDT-LENOVO-CB-01]`
   plus `DSDT ACPI table found in initrd`).
2. Check the deployed initramfs is ours, not the base image's:
   `hash=$(sed -n 's/.*BOOT_IMAGE=[^)]*)\/ostree\/\(fedora-[0-9a-f]*\)\/.*/\1/p' /proc/cmdline)`
   then `stat -c %s /boot/ostree/$hash/initramfs-$(uname -r).img`.
   Ours ≈ 240310824 bytes; the base image's is ≈ 237836359. (The size changes
   with kernel versions — the point is: is it the size of the file baked by
   this build?)
3. `rpm-ostree status` — look for a "failed to finalize previous deployment"
   warning (almost always `/boot` ENOSPC, see above). If finalize failed, you
   are still booted on the *previous* deployment and everything looks old.
4. `cat /sys/kernel/security/lockdown` → must be `[none]` (Secure Boot off).
5. `sudo lsinitrd /boot/ostree/$hash/initramfs-$(uname -r).img | grep
   firmware/acpi` — the patched table must appear in the Early CPIO section.

Symptom: boot drops to emergency mode with
`Failed to switch root: ... os-release file is missing`.

The initramfs lacks `ostree-prepare-root`. The atomic dracut confs force
non-hostonly builds (`20-atomic-nohostonly.conf`), which excludes the
hostonly-only `50ostree` dracut module (its `check()` returns 255). Any
**manual** `dracut` run must pass `--add ostree` (see below). Deploys of this
image don't need it — the baked initramfs already contains the module.

Symptom: `dsdt-override-check.service` fails with "firmware DSDT differs from
both stored copies".

A BIOS update changed the DSDT. Re-do the patch (see "After a BIOS update").

## After a BIOS update

1. `rpm-ostree rollback` and reboot, so the override is not active (or boot a
   live media) — `extract-dsdt.sh` refuses to run when the override is active,
   because `/sys/firmware/acpi/tables/DSDT` may then show the overridden table
   instead of the real firmware one.
2. `./extract-dsdt.sh` + (in distrobox) `./patch-dsdt.sh`, commit, `task ntb`,
   rebase, reboot.

## Notes on manual initramfs regeneration (ostree)

- `/etc` is per-deployment: a dracut conf created while booted in one
  deployment is invisible when regenerating from/for another deployment.
- Atomic desktops build the initramfs in non-hostonly mode
  (`20-atomic-nohostonly.conf`), which excludes the hostonly-only `50ostree`
  dracut module. A plain `dracut -f` therefore produces an initramfs that
  drops to emergency mode at switch-root. Always pass `--add ostree`:

  ```
  sudo dracut -f --add ostree "/boot/ostree/<hash>/initramfs-<kver>.img" <kver>
  ```

  When regenerating for a *different* deployment, also pass
  `--kmoddir <deployment>/lib/modules/<kver>`.
- What gets deployed is `/usr/lib/modules/<kver>/initramfs.img` from the
  image tree (not the `/boot` copy) — patch the image, not the deployed file,
  or the next deploy reverts it.
- The override only reaches the kernel if Secure Boot (kernel lockdown) is
  off; otherwise the initrd table is silently ignored.

## Key source references (coreos/rpm-ostree)

Explored the hard way so you don't have to re-clone:

- `src/libpriv/rpmostree-kernel.cxx` — `rpmostree_find_kernel()` /
  `find_kernel_and_initramfs_in_bootdir()`: scan order
  (`usr/lib/ostree-boot` → `boot` → `usr/lib/modules`), naming rules
  (`vmlinuz` / `vmlinuz-<kver>`; `initramfs.img` or `initramfs-<kver>.img`;
  regular files only; exactly one `initramfs*` per scanned dir).
- `src/daemon/rpmostree-sysroot-upgrader.cxx` —
  `perform_local_assembly()`: the only place client-side dracut runs, gated by
  `kernel_or_initramfs_changed`; `may_require_local_assembly()` decides
  whether assembly happens at all.
- `rust/src/treefile.rs` — `may_require_local_assembly()`: cliwrap,
  regenerate-initramfs, initramfs-etc, or layered packages.
- libostree `ostree/src/libostree/ostree-sysroot-deploy.c` —
  `get_kernel_from_tree()`: the modules-dir fast path pairs
  `vmlinuz` with `initramfs.img` in the same directory.
- Linux `drivers/acpi/tables.c` — `acpi_table_upgrade()` (lockdown gate) and
  `acpi_table_initrd_override()` (signature/OEM/revision matching rules).

## Files

| path | purpose |
| --- | --- |
| `ntb-rootfs/etc/dracut.conf.d/20-yoga7i-s3.conf` | dracut conf: packs the patched table into the initramfs |
| `ntb-rootfs/etc/dracut.conf.d/yoga7i-acpi/DSDT.aml` | patched table |
| `ntb-rootfs/usr/share/dsdt-override/DSDT.orig.aml` | unpatched firmware table, compared at boot by `dsdt-override-check.service` |
| `ntb-rootfs/usr/libexec/dsdt-override-check` (+ systemd unit) | boot-time integrity check |
| `scripts/dsdt/DSDT.patched.dsl` | patched DSDT source, for reference |

Everything under `ntb-rootfs/` is only built into the **ntb** image
(`task build-ntb` passes `MACHINE=ntb`; build.sh merges it in; the workstation
image is unaffected — its build.sh branch deletes `/ntb-rootfs`).

## Procedure (fresh machine or full redo)

1. Disable Secure Boot in BIOS (F2 → Security → Secure Boot → Disabled).
2. On the host: `./extract-dsdt.sh`.
3. In a distrobox with `acpica-tools`: `./patch-dsdt.sh`.
4. `task ntb` (build + push, rebase as root), reboot.
5. One-time, per machine:
   `sudo rpm-ostree kargs --append=mem_sleep_default=deep`, reboot.
6. Verify: `cat /sys/power/mem_sleep` → `[deep]`;
   `sudo journalctl -b -k -g "PM: suspend"` shows
   `PM: suspend entry (deep)` after a suspend cycle;
   `dsdt-override-check.service` active/OK.
