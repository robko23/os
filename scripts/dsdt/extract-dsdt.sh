#!/bin/bash
# Extract the firmware-provided DSDT ACPI table so it can be patched
# (see patch-dsdt.sh). Run on the HOST, it asks for sudo:
#
#   ./extract-dsdt.sh
#
# Must be run on a boot where the DSDT override is NOT active (e.g. before the
# first deployment carrying the override, or from the rollback deployment /
# live media), otherwise /sys may expose the overridden table instead of the
# real firmware table.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/DSDT.firmware.aml"

if sudo dmesg 2>/dev/null | grep -q 'Table Upgrade: override \[DSDT-'; then
    echo "error: the DSDT override is active on this boot, so /sys/firmware/acpi/tables/DSDT" >&2
    echo "       is probably not the real firmware table. Boot the stock/rollback deployment" >&2
    echo "       (rpm-ostree rollback) or a live media and run this script again." >&2
    exit 1
fi

sudo cat /sys/firmware/acpi/tables/DSDT > "$out"

if [ "$(head -c4 "$out")" != "DSDT" ]; then
    echo "error: extracted table does not start with the ACPI signature 'DSDT'" >&2
    exit 1
fi

echo "wrote $out ($(stat -c '%s' "$out") bytes)"
sha256sum "$out"
echo
echo "next step: patch it inside a distrobox container (see README.md):"
echo "  sudo dnf install -y acpica-tools   # in the container"
echo "  ${here}/patch-dsdt.sh"