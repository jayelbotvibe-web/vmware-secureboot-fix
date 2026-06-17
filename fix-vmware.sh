#!/bin/bash
# Quick one-shot fix: Rebuild + sign + start VMware for the current kernel
# Run this after a kernel update if VMware won't start.
#
# Config via env vars (same as the auto-hook):
#   MOK_PRIV_DIR — path to MOK keys (default: /root/.vmware-keys)

set -e
KVER=$(uname -r)
MOD_DIR="/lib/modules/${KVER}/misc"
SIGN_TOOL="/lib/modules/${KVER}/build/scripts/sign-file"
KEY_DIR="${MOK_PRIV_DIR:-/root/.vmware-keys}"

echo "=== Fixing VMware modules for kernel ${KVER} ==="

# Detect Secure Boot
SB=0
if command -v mokutil &>/dev/null && mokutil --sb-state 2>/dev/null | grep -q "SecureBoot enabled"; then
    SB=1
    echo "Secure Boot: ENABLED"
else
    echo "Secure Boot: disabled — skipping signing"
fi

echo "[1/3] Compiling modules..."
sudo vmware-modconfig --console --install-all

if [[ $SB -eq 1 ]]; then
    echo "[2/3] Signing modules..."
    sudo "${SIGN_TOOL}" sha256 "${KEY_DIR}/MOK.priv" "${KEY_DIR}/MOK.der" "${MOD_DIR}/vmmon.ko"
    sudo "${SIGN_TOOL}" sha256 "${KEY_DIR}/MOK.priv" "${KEY_DIR}/MOK.der" "${MOD_DIR}/vmnet.ko"

    echo "[2b/3] Verifying signatures..."
    for mod in vmmon vmnet; do
        SIG=$(modinfo -F sig_id "${MOD_DIR}/${mod}.ko" 2>/dev/null)
        if [[ -n "$SIG" ]]; then
            echo "  ${mod}: signed (${SIG})"
        else
            echo "  ${mod}: STILL UNSIGNED — something went wrong"
            exit 1
        fi
    done
else
    echo "[2/3] Skipped (Secure Boot off)"
fi

echo "[3/3] Starting VMware..."
sudo systemctl reset-failed vmware vmware-USBArbitrator 2>/dev/null || true
sudo systemctl enable vmware vmware-USBArbitrator 2>/dev/null || true
sudo systemctl start vmware
systemctl status vmware --no-pager

echo ""
echo "=== Done! ==="
