# VMware Secure Boot Kernel Module Auto-Fix

**Never manually fix VMware after a kernel update again.**

When a kernel update breaks VMware Workstation on Ubuntu with Secure Boot enabled, this hook automatically:
1. Recompiles `vmmon` and `vmnet` for the new kernel
2. Signs them with your MOK key for Secure Boot
3. Verifies the signatures actually took effect (catches silent failures)
4. Enables `vmware.service` so it starts on next boot
5. Clears the "failed" state left by `vmware-modconfig`

## Quick Start

```bash
# 1. One-time setup — generate and enroll MOK keys
sudo mkdir -p /root/.vmware-keys
sudo openssl req -new -x509 -newkey rsa:2048 -keyout /root/.vmware-keys/MOK.priv \
  -outform DER -out /root/.vmware-keys/MOK.der -nodes -days 36500 \
  -subj "/CN=VMware-MOK"
sudo mokutil --import /root/.vmware-keys/MOK.der
# Reboot, enroll the key in the MOK Manager, then continue:

# 2. Install the hook
sudo cp vmware-sign-modules /etc/kernel/postinst.d/vmware-sign-modules
sudo chmod +x /etc/kernel/postinst.d/vmware-sign-modules

# 3. Run it once for the current kernel (optional — hook handles future updates)
sudo /etc/kernel/postinst.d/vmware-sign-modules $(uname -r)
```

That's it. Next time a kernel update arrives, VMware will work after reboot — no manual intervention.

## Root Cause Analysis

### The Problem

On Ubuntu with Secure Boot enabled, VMware Workstation breaks after every kernel update:

```
$ systemctl status vmware
× vmware.service - LSB: This service starts and stops VMware services
     Active: failed
   Virtual machine monitor - failed
   Virtual ethernet - failed

$ dmesg | tail -2
Loading of unsigned module is rejected
Loading of unsigned module is rejected
```

### Three Interlocking Bugs

This problem is caused by **three compounding issues** that must all be fixed:

#### Bug 1: Wrong-Target Signing

The kernel post-install hook runs during `dpkg --configure`, *before* reboot. The typical approach:

```bash
VMMON=$(modinfo -n vmmon)      # ← BUG: finds OLD kernel's module!
sign-file sha256 key.priv key.der "$VMMON"
```

`modinfo -n` queries the **currently running** kernel's module tree. During kernel installation, that's still the **old** kernel. So the hook signs the old kernel's modules, while `vmware-modconfig` compiles new (unsigned) ones for the new kernel.

**Fix:** Target the new kernel explicitly:
```bash
MOD_DIR="/lib/modules/${KERNEL_VERSION}/misc"
sign-file sha256 key.priv key.der "${MOD_DIR}/vmmon.ko"
```

#### Bug 2: Disabled Service

`vmware.service` is often in a `disabled` state. Even after a successful compile + sign, systemd will never auto-start it after reboot:

```bash
$ systemctl is-enabled vmware
disabled
```

**Fix:** `systemctl enable vmware` in the hook.

#### Bug 3: Persisted Failed State

`vmware-modconfig --console --install-all` tries to start the service during compilation. Since the new modules can't load into the old kernel, it fails. Systemd marks the service `failed` — and that state persists across reboots. A failed service won't auto-start.

**Fix:** `systemctl reset-failed vmware` in the hook to clear the stale state.

### Why "Succeeded" Signing Can Still Fail

You might see this in logs:

```
vmmon signed OK
vmnet signed OK
```

But `modinfo vmmon | grep sig_id` returns nothing — the module is unsigned. This happens when:

- `vmware-modconfig` recompiles modules **after** signing (some init scripts do this)
- `sign-file` writes to a temp location but the module at the final path is a fresh copy
- Module paths change between compilation and signing

**Fix:** Add a verification step with `modinfo -F sig_id` that exits with error if the signature didn't take.

## Files

| File | Purpose |
|------|---------|
| `vmware-sign-modules` | The kernel post-install hook (install to `/etc/kernel/postinst.d/`) |
| `fix-vmware.sh` | Manual quick-fix for the current kernel |
| `README.md` | This document |

## Requirements

- VMware Workstation / Player 17+
- Ubuntu 22.04+ with Secure Boot enabled
- MOK keypair generated and enrolled in firmware
- Kernel headers installed (`linux-headers-$(uname -r)`)

## License

MIT
