#!/bin/bash
# Quick fix: Rebuild VMware modules, sign them, and start the service
# Run this after a kernel update if VMware won't start

set -e
KVER=$(uname -r)
MOD_DIR="/lib/modules/${KVER}/misc"
SIGN_TOOL="/lib/modules/${KVER}/build/scripts/sign-file"
KEY_DIR="${HOME}/.vmware-keys"

echo "=== Fixing VMware modules for kernel ${KVER} ==="

echo "[1/3] Compiling modules..."
sudo vmware-modconfig --console --install-all

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

echo "[3/3] Starting VMware..."
sudo systemctl reset-failed vmware vmware-USBArbitrator 2>/dev/null || true
sudo systemctl enable vmware vmware-USBArbitrator 2>/dev/null || true
sudo systemctl start vmware

systemctl status vmware --no-pager

echo ""
echo "=== Done! Start your VM with: ==="
echo "vmrun -vp '<password>' start '<path-to-vmx>' gui"
