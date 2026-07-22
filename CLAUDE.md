# CLAUDE.md — vmware-secureboot-fix

Fixes the recurring "Virtual machine monitor — failed" / "Loading of unsigned module is
rejected" breakage that hits VMware Workstation on Ubuntu/Debian after every kernel update.
Ships two things: a one-shot manual repair for a currently-broken system, and a
`/etc/kernel/postinst.d/` hook that rebuilds and Secure-Boot-signs `vmmon.ko`/`vmnet.ko`
automatically after each kernel install.

**Unrelated to the Hermes projects** despite sitting beside them — it lives here because the
same laptop runs VMware for the SIFT VM.

## ⚠ Known bug — the permanent-fix path does not work as committed

`vmware-sign-modules:102` calls:

```bash
make -C "$BUILD_DIR" M="$mod_src_dir" modules
```

**`$BUILD_DIR` is never defined anywhere in the file.** The variable holding
`/lib/modules/${KERNEL_VERSION}/build` is named `HEADER_DIR` (line 39). The script runs
under `set -euo pipefail`, so the hook aborts with `BUILD_DIR: unbound variable` at the
compile step **every time**.

Consequence: the advertised automatic fix never runs. Only `fix-vmware.sh` works, because it
uses `vmware-modconfig` and doesn't touch that variable.

Introduced by the last functional commit, `29ecb4d` (2026-06-18) — the rewrite that replaced
`vmware-modconfig` with a direct `make` was never executed. There is no CI, which is why it
survived. **Fix this before recommending the repo to anyone**; it is public and
search-optimized.

## Commands

No build, test, or lint. Two operations, both requiring root:

```bash
sudo ./fix-vmware.sh                                       # one-shot fix, running kernel

sudo cp vmware-sign-modules /etc/kernel/postinst.d/vmware-sign-modules
sudo chmod +x /etc/kernel/postinst.d/vmware-sign-modules   # permanent (see bug above)
```

One-time Secure Boot setup — only if `mokutil --sb-state` reports enabled — is a MOK
generate + `mokutil --import` + reboot into the blue MOK Manager screen. Full steps in the
README.

## Stack

Two Bash scripts. No language runtime, no dependencies beyond system tools: `mokutil`,
`openssl`, `make`, kernel headers, `sign-file`, `depmod`, `systemctl`, and
`vmware-modconfig` (only in `fix-vmware.sh`).

## Architecture

| File | Role |
|---|---|
| `vmware-sign-modules` (204) | The real deliverable — kernel postinst hook; takes `$1` = kernel version; wait for headers → compile → sign → depmod → enable services |
| `fix-vmware.sh` (54) | Manual entry point — `vmware-modconfig` against the running kernel, sign, start service |
| `README.md` (205) | Install, MOK enrollment, "The Three Bugs This Fixes", troubleshooting |

## What it changes on the system — as root

- Writes `vmmon.ko` / `vmnet.ko` into `/lib/modules/<kernel>/misc/`
- Signs them with `sign-file sha256` using `/root/.vmware-keys/MOK.priv` + `MOK.der`
- Runs `depmod <kernel>`
- Runs `systemctl reset-failed vmware vmware-USBArbitrator` and **permanently enables**
  `vmware` and `vmware-USBArbitrator` (deliberate — README "Bug 2")
- Appends to `/var/log/vmware-hook.log`
- Creates/removes `mktemp -d /tmp/vmware-build-XXXXXX` workdirs

**Installing the hook means it runs unattended on every future kernel package install.**
With `set -euo pipefail` and `exit 1` on failure, a failed build can make the kernel
postinst step fail during `apt upgrade`.

## Configuration

Optional env vars, settable in `/etc/default/vmware-sign-modules` or at the top of the hook:
`MOK_PRIV_DIR` (default `/root/.vmware-keys`), `LOG_FILE`
(default `/var/log/vmware-hook.log`), `MAX_RETRIES` (3), `RETRY_DELAY` (30).

Hardcoded assumptions: VMware source tarballs at `/usr/lib/vmware/modules/source/`, binary
at `/usr/bin/vmware` (the hook exits 0 if absent). Secure Boot off → signing auto-skipped.

## State

Presents as polished and public-facing (MIT, search-optimized README, badges) but is
**untested since the final rewrite and does not work as documented** — see the bug above.
5 commits, all in a two-day burst 2026-06-17 → 2026-06-18, nothing since. Clean tree on
`main`, pushed. No CI.

The only TODO/FIXME grep hit is the false positive `mktemp -d /tmp/vmware-build-XXXXXX`.
