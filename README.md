# Fix VMware "Virtual Machine Monitor Failed" After Ubuntu Kernel Update

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Ubuntu%20%7C%20Debian-orange)]()

**Every kernel update breaks VMware. This fixes it — once, permanently.**

If you see this after `apt upgrade`:

```
$ systemctl status vmware
× vmware.service - LSB: This service starts and stops VMware services
   Virtual machine monitor - failed
   Virtual ethernet - failed

$ dmesg | grep module
Loading of unsigned module is rejected
Loading of unsigned module is rejected
```

You're in the right place.

---

## Quick Fix (VMware is broken *right now*)

This rebuilds and signs modules for your current kernel immediately:

```bash
git clone https://github.com/jayelbotvibe-web/vmware-secureboot-fix.git
cd vmware-secureboot-fix
sudo ./fix-vmware.sh
```

VMware works again. But the next kernel update will break it again — unless you install the auto-fix below.

---

## Permanent Fix (never breaks again)

This installs a hook that runs automatically after every kernel update. Next time `apt` installs a new kernel, VMware modules are rebuilt, signed, and ready **before you even reboot**.

```bash
sudo cp vmware-sign-modules /etc/kernel/postinst.d/vmware-sign-modules
sudo chmod +x /etc/kernel/postinst.d/vmware-sign-modules
```

**That's it.** No terminal, no googling, no `vmware-modconfig` ever again. Kernel updates become boring.

> **How it works:** The hook compiles `vmmon.ko` and `vmnet.ko` against the *new* kernel's headers (not the running kernel — that's the bug every other approach misses), signs them if Secure Boot is on, and clears any stale `failed` state from systemd. When you reboot, VMware starts clean.

---

## Secure Boot Setup (one-time, only if Secure Boot is ON)

Check first:

```bash
mokutil --sb-state
```

If it says `SecureBoot enabled`, you need a Machine Owner Key (MOK) so the kernel trusts signed modules. Do this once, before or after installing the hook.

### Step 1: Generate a key

```bash
sudo mkdir -p /root/.vmware-keys
sudo openssl req -new -x509 -newkey rsa:2048 \
  -keyout /root/.vmware-keys/MOK.priv \
  -outform DER -out /root/.vmware-keys/MOK.der \
  -nodes -days 36500 -subj "/CN=VMware-MOK"
```

### Step 2: Tell the system to enroll it

```bash
sudo mokutil --import /root/.vmware-keys/MOK.der
```

You'll be asked to set a one-time password. Make it simple — you only use it once.

### Step 3: Reboot into the MOK manager

```bash
sudo reboot
```

During boot, you'll see a **blue screen with white text** (the MOK Manager — it looks like BIOS, not Ubuntu). This screen only appears once.

What to do on the blue screen:
- Select **"Enroll MOK"** → Enter
- Select **"Continue"** → Enter
- Type the password you set in Step 2 → Enter
- Select **"Reboot"** → Enter

The system reboots normally. From now on, VMware modules signed with your key are trusted.

> **Missed the blue screen?** It only shows once after `mokutil --import`. Run `sudo mokutil --import` again to re-trigger it.

### Secure Boot is OFF?

Skip this entire section. The hook auto-detects this and skips signing. Nothing to configure.

---

## The Three Bugs This Fixes

Why do existing approaches fail? Three compounding issues:

### 🐛 Bug 1: Compiling and signing for the wrong kernel

Kernel hooks run during package installation, **before reboot**. The running kernel is still the old one. Two things go wrong:

- `vmware-modconfig` calls `uname -r` → compiles modules for the OLD kernel → they land in `/lib/modules/OLD_KERNEL/`
- `modinfo -n vmmon` also queries the running kernel → signing targets the wrong path

The hook then looks in `/lib/modules/NEW_KERNEL/` — but the modules were never compiled there.

**Our fix:** bypass `vmware-modconfig` entirely. Compile directly against the new kernel's build system (`make -C /lib/modules/$NEW_KERNEL/build`), then sign the result at the correct path.

### 🐛 Bug 2: Disabled service

`vmware.service` defaults to `disabled`. Systemd won't auto-start a disabled service after reboot, even with perfectly compiled and signed modules.

**Our fix:** `systemctl enable vmware` in the hook.

### 🐛 Bug 3: Persisted failed state

Previous failed boot attempts leave `vmware.service` in a `failed` state. That state survives reboots and blocks auto-start, even after modules are fixed.

**Our fix:** `systemctl reset-failed vmware` to clear the stale state.

---

## Troubleshooting

### Check the hook log

```bash
cat /var/log/vmware-hook.log
```

Every run is timestamped. Look for `ERROR` lines.

### "ERROR: vmmon.tar not found"

VMware Workstation / Player isn't installed, or it's installed in a non-standard location. The hook expects `/usr/lib/vmware/modules/source/`.

### "ERROR: compilation failed"

Missing kernel headers or build tools:
```bash
sudo apt install linux-headers-$(uname -r) build-essential
```

### "ERROR: Secure Boot is ON but no MOK keys"

You skipped the Secure Boot setup. See the section above — generate and enroll a key.

### "ERROR: depmod failed"

Something is wrong with the kernel module tree. Try:
```bash
sudo depmod $(uname -r)
```

### VMware still broken after reboot?

1. Check if the hook actually ran: `cat /var/log/vmware-hook.log | grep $(uname -r)`
2. Check module signatures: `modinfo /lib/modules/$(uname -r)/misc/vmmon.ko | grep sig_id`
3. Check service state: `systemctl status vmware`

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
| `README.md` | This file |

## License

MIT — use it, fork it, ship it.
