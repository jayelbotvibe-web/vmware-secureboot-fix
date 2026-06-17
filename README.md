# VMware Kernel Module Auto-Fix

**Never manually fix VMware after a kernel update again.**

Works on any Debian/Ubuntu system — Secure Boot or not. The hook detects your environment and does the right thing.

## What it does

| Step | With Secure Boot | Without Secure Boot |
|------|-----------------|---------------------|
| 1 | Recompiles `vmmon` + `vmnet` for new kernel | Same |
| 2 | Signs modules with your MOK key | Skipped |
| 3 | Verifies signatures took effect | Skipped |
| 4 | Enables `vmware.service` (auto-start on boot) | Same |
| 5 | Clears stale "failed" state | Same |

## Quick Start

### 1. Generate MOK keys (Secure Boot users only)

Skip this if Secure Boot is disabled on your system. Check with `mokutil --sb-state`.

```bash
sudo mkdir -p /root/.vmware-keys
sudo openssl req -new -x509 -newkey rsa:2048 \
  -keyout /root/.vmware-keys/MOK.priv \
  -outform DER -out /root/.vmware-keys/MOK.der \
  -nodes -days 36500 -subj "/CN=VMware-MOK"
sudo mokutil --import /root/.vmware-keys/MOK.der
# Reboot, select "Enroll MOK" in the blue MOK Manager screen, then continue:
```

### 2. Install the hook

```bash
sudo cp vmware-sign-modules /etc/kernel/postinst.d/vmware-sign-modules
sudo chmod +x /etc/kernel/postinst.d/vmware-sign-modules
```

### 3. Run it once for the current kernel (optional)

```bash
sudo /etc/kernel/postinst.d/vmware-sign-modules $(uname -r)
```

Done. Next kernel update will be handled automatically.

## Configuration

Set these environment variables before the hook runs — either at the top of the hook file, or in `/etc/default/vmware-sign-modules`:

| Variable | Default | Description |
|----------|---------|-------------|
| `MOK_PRIV_DIR` | `/root/.vmware-keys` | Path to MOK key directory |
| `LOG_FILE` | `/var/log/vmware-hook.log` | Log file location |
| `MAX_RETRIES` | `3` | Retry attempts for headers/signing |
| `RETRY_DELAY` | `30` | Seconds between retries |

Example for custom key location:
```bash
sudo mkdir -p /etc/default
echo 'MOK_PRIV_DIR=/etc/vmware-keys' | sudo tee /etc/default/vmware-sign-modules
```

## Manual Quick-Fix

If VMware is currently broken and you want to fix it right now:

```bash
sudo ./fix-vmware.sh
```

Or for custom key location:
```bash
sudo MOK_PRIV_DIR=/custom/path ./fix-vmware.sh
```

## Root Cause: Why This Problem Exists

Three compounding bugs break VMware after every kernel update on Secure Boot systems:

### Bug 1: Wrong-Target Signing

Kernel hooks run during `dpkg --configure`, *before* reboot. The typical sign attempt uses:

```bash
VMMON=$(modinfo -n vmmon)      # ← BUG: returns OLD kernel's module path!
```

`modinfo -n` queries the currently running kernel. Since we haven't rebooted yet, that's still the **old** kernel. The hook signs old modules while `vmware-modconfig` compiles new, unsigned ones.

### Bug 2: Disabled Service

`vmware.service` is often `disabled`. Systemd won't auto-start a disabled service after reboot, even if modules are ready.

### Bug 3: Persisted Failed State

`vmware-modconfig` tries to start the service during compilation. The new modules can't load into the old kernel, so it fails. Systemd marks it `failed` — that state persists across reboots, and a failed service won't auto-start.

### Why Signing Can Silently Fail

Even when logs show `vmmon signed OK`, the signature may not take. This happens when:

- `vmware-modconfig` overwrites the modules after signing
- The sign tool succeeds on a temp file but the module at the final path isn't updated

**This hook verifies with `modinfo -F sig_id` and exits with error if the signature didn't stick.**

## Compatibility

- **VMware Workstation / Player** 17+ (older versions may work)
- **Debian / Ubuntu** (any distro with `/etc/kernel/postinst.d/`)
- **Secure Boot** on or off — auto-detected
- **Any kernel version**

## Files

| File | Purpose |
|------|---------|
| `vmware-sign-modules` | Kernel post-install hook |
| `fix-vmware.sh` | Manual one-shot fix |
| `README.md` | This document |

## License

MIT
