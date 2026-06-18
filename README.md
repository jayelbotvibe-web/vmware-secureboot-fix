# Fix VMware "Virtual Machine Monitor Failed" After Ubuntu Kernel Update

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-orange)]()

**The one-click fix for the most annoying VMware-on-Linux problem.**

If you see this after a kernel update:

```
$ systemctl status vmware
× vmware.service - LSB: This service starts and stops VMware services
   Virtual machine monitor - failed
   Virtual ethernet - failed

$ dmesg | grep module
Loading of unsigned module is rejected
Loading of unsigned module is rejected
```

**This repo fixes it permanently.** One install, zero future intervention — works with or without Secure Boot.

---

## The Problem

Every time Ubuntu pushes a kernel update, VMware Workstation / Player breaks. The `vmmon` and `vmnet` kernel modules need to be recompiled for the new kernel, and if Secure Boot is enabled, they must be signed with a Machine Owner Key (MOK) or the kernel rejects them as "unsigned."

Existing fixes are manual, fragile, or target the wrong kernel version. This hook fixes all three root-cause bugs.

## The Fix

```bash
git clone https://github.com/jayelbotvibe-web/vmware-secureboot-fix.git
cd vmware-secureboot-fix

# Secure Boot users only — generate + enroll a MOK key (one-time):
sudo mkdir -p /root/.vmware-keys
sudo openssl req -new -x509 -newkey rsa:2048 \
  -keyout /root/.vmware-keys/MOK.priv \
  -outform DER -out /root/.vmware-keys/MOK.der \
  -nodes -days 36500 -subj "/CN=VMware-MOK"
sudo mokutil --import /root/.vmware-keys/MOK.der
# Reboot → select "Enroll MOK" in the blue screen → reboot again

# Install the hook (works for everyone):
sudo cp vmware-sign-modules /etc/kernel/postinst.d/vmware-sign-modules
sudo chmod +x /etc/kernel/postinst.d/vmware-sign-modules

# Fix current kernel right now (optional):
sudo ./fix-vmware.sh
```

**That's it.** Next kernel update: VMware works after reboot. No terminal, no googling, no `vmware-modconfig`.

---

## What It Actually Does

| Step | Secure Boot ON | Secure Boot OFF |
|------|:---:|:---:|
| Detects environment | ✅ `mokutil --sb-state` | ✅ |
| Compiles `vmmon` + `vmnet` for target kernel | ✅ `make` (kernel build system) | ✅ |
| Signs modules with MOK key | ✅ `sign-file` | ⏭️ Skipped |
| Verifies signatures took effect | ✅ `modinfo -F sig_id` | ⏭️ Skipped |
| Runs `depmod` for new kernel | ✅ | ✅ |
| Enables `vmware.service` | ✅ `systemctl enable` | ✅ |
| Clears stale "failed" state | ✅ `systemctl reset-failed` | ✅ |

---

## The Three Bugs This Fixes

Why do existing approaches fail? Three compounding issues:

### 🐛 Bug 1: Compiling and signing for the wrong kernel

Kernel hooks run during package installation, *before reboot*. Two tools query the running (old) kernel:

- `vmware-modconfig` calls `uname -r` → compiles `vmmon.ko`/`vmnet.ko` for the OLD kernel → modules land in `/lib/modules/OLD_KERNEL/misc/`
- `modinfo -n vmmon` returns the OLD kernel's module path → signing targets the wrong file

The hook then looks for modules at `/lib/modules/${NEW_KERNEL}/misc/` — but they were never compiled there.

**Our fix**: bypass `vmware-modconfig` entirely. Compile directly against the new kernel's build system with `make -C /lib/modules/${NEW_KERNEL}/build`, then sign the resulting modules at the correct path.

### 🐛 Bug 2: Disabled service

`vmware.service` defaults to `disabled`. Systemd won't auto-start a disabled service after reboot, even with perfectly signed modules.

**Our fix**: `systemctl enable vmware` in the hook.

### 🐛 Bug 3: Persisted failed state

`vmware-modconfig` tries to start the service during compilation. New modules can't load into the old kernel → service fails → systemd marks it `failed`. That state persists across reboots and prevents auto-start.

**Our fix**: `systemctl reset-failed vmware` to clear the stale state.

---

## Configuration

Set in `/etc/default/vmware-sign-modules` or at the top of the hook file:

| Variable | Default | Description |
|----------|---------|-------------|
| `MOK_PRIV_DIR` | `/root/.vmware-keys` | Where your MOK keypair lives |
| `LOG_FILE` | `/var/log/vmware-hook.log` | Hook log location |
| `MAX_RETRIES` | `3` | Retries for headers/signing |
| `RETRY_DELAY` | `30` | Seconds between retries |

---

## Compatibility

- **VMware Workstation 17+ / Player 17+**
- **Ubuntu 22.04+ / Debian 12+** (any distro with `/etc/kernel/postinst.d/`)
- **Secure Boot** on or off — auto-detected, no config needed
- **Any kernel version**

## Files

| File | Purpose |
|------|---------|
| `vmware-sign-modules` | Kernel post-install hook (the auto-fix) |
| `fix-vmware.sh` | Manual one-shot fix for right now |
| `README.md` | You're reading it |

## License

MIT — use it, fork it, ship it.
