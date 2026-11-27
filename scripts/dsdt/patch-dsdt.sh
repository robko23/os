#!/bin/bash
# Patch the Yoga 7i firmware DSDT:
#   1. advertise S3 (deep) sleep: Name (SS3, Zero) -> Name (SS3, One)
#   2. touchpad (TPD0, ELAN 04F3:3138): expose the EC touchpad-enable flag
#      (ECTP, EC MMIO @ 0xFE0B0443, written by TPD0.TPWR) as a proper ACPI
#      power resource (TPPR) referenced by _PR0. This lets the kernel
#      power-cycle the pad from the OS: driver unbind -> _PS3 -> ECTP=0,
#      driver bind -> _PS0 -> ECTP=1 (firmware cold boot). Set
#      TP_ECTP_PR0=0 to skip this patch.
# plus an OEM revision bump, which is required for the kernel's initramfs
# table override to accept the table (drivers/acpi/tables.c:
# acpi_table_initrd_override() skips tables whose oem_revision is not greater
# than the firmware table's).
#
# See https://wiki.archlinux.org/title/Lenovo_Yoga_7i#Activating_S3_sleep
#
# Run INSIDE a distrobox container that has acpica-tools installed:
#   sudo dnf install -y acpica-tools   # in the container
#   ./patch-dsdt.sh [path/to/DSDT.firmware.aml]
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
override_dir="$repo_root/ntb-rootfs/etc/dracut.conf.d/yoga7i-acpi"
check_dir="$repo_root/ntb-rootfs/usr/share/dsdt-override"
input="${1:-$script_dir/DSDT.firmware.aml}"

[ -f "$input" ] || { echo "error: '$input' not found — run extract-dsdt.sh on the host first" >&2; exit 1; }
command -v iasl >/dev/null || { echo "error: iasl not found — install acpica-tools (dnf install acpica-tools)" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp "$input" "$work/dsdt.dat"
cd "$work"

# 1. decompile
iasl -d dsdt.dat
[ -f dsdt.dsl ] || { echo "error: decompilation did not produce dsdt.dsl" >&2; exit 1; }

# 2. advertise S3
n=$(grep -c 'Name (SS3, Zero)' dsdt.dsl || true)
if [ "$n" -ne 1 ]; then
    echo "error: expected exactly one 'Name (SS3, Zero)' in the DSDT, found $n." >&2
    echo "       Either the firmware no longer hides S3 (patch not needed?) or the" >&2
    echo "       extracted table is not the real firmware DSDT." >&2
    exit 1
fi
sed -i 's/Name (SS3, Zero)/Name (SS3, One)/' dsdt.dsl

# 3. touchpad: wire the EC enable flag (ECTP) in as an ACPI power resource
if [ "${TP_ECTP_PR0:-1}" = "1" ]; then
    python3 - <<'PYEOF'
src = open('dsdt.dsl').read()

anchor = "        I2CX = One\n"
if src.count(anchor) != 1:
    raise SystemExit(f"error: I2C1 scope anchor 'I2CX = One' found {src.count(anchor)} times, expected 1")

tpwr = (
    "            Method (TPWR, 1, Serialized)\n"
    "            {\n"
    "                ^^^LPCB.EC0.ECTP = Arg0\n"
    "            }\n"
)
if src.count(tpwr) != 1:
    raise SystemExit(f"error: TPD0.TPWR anchor found {src.count(tpwr)} times, expected 1")

powerres = "\n".join([
    "",
    "        PowerResource (TPPR, 0x00, 0x0000)",
    "        {",
    "            Method (_ON, 0, Serialized)",
    "            {",
    "                \\_SB_.PC00.LPCB.EC0_.ECTP = One",
    "            }",
    "",
    "            Method (_OFF, 0, Serialized)",
    "            {",
    "                \\_SB_.PC00.LPCB.EC0_.ECTP = Zero",
    "            }",
    "",
    "            Method (_STA, 0, NotSerialized)",
    "            {",
    "                Return (\\_SB_.PC00.LPCB.EC0_.ECTP)",
    "            }",
    "        }",
    "",
])
src = src.replace(anchor, anchor + powerres)
src = src.replace(tpwr, tpwr + "\n            Name (_PR0, Package (One) { TPPR })\n")

open('dsdt.dsl', 'w').write(src)
print("patched: PowerResource TPPR added to \\_SB.PC00.I2C1, _PR0 added to TPD0")
PYEOF
    [ "$(grep -c 'PowerResource (TPPR' dsdt.dsl)" -eq 1 ] || { echo "error: TPPR insertion verification failed" >&2; exit 1; }
    [ "$(grep -c 'Name (_PR0, Package (One) { TPPR })' dsdt.dsl)" -eq 1 ] || { echo "error: _PR0 insertion verification failed" >&2; exit 1; }
else
    echo "TP_ECTP_PR0=0: skipping the touchpad power-resource patch"
fi

# 4. bump the OEM revision so the override is applied
oldrev=$(grep -m1 -oP '^DefinitionBlock.*\K0x[0-9A-Fa-f]+(?=\))' dsdt.dsl)
[ -n "$oldrev" ] || { echo "error: could not read the OEM revision from the DefinitionBlock" >&2; exit 1; }
expected_rev=$((oldrev + 1))
newrev=$(printf '0x%08X' "$expected_rev")
sed -i "/^DefinitionBlock /s/$oldrev/$newrev/" dsdt.dsl

grep -q 'Name (SS3, One)' dsdt.dsl
grep -q "^DefinitionBlock.*$newrev" dsdt.dsl

# 5. recompile and verify: round-trip + OEM revision in the AML header
#    (offset 24, little-endian u32) must equal oldrev + 1
iasl dsdt.dsl
[ -f dsdt.aml ] || { echo "error: compilation did not produce dsdt.aml" >&2; exit 1; }
aml_rev=$(od -An -tu4 -j24 -N4 dsdt.aml | tr -d ' ')
if [ "$aml_rev" != "$expected_rev" ]; then
    echo "error: compiled AML has OEM revision $aml_rev, expected $expected_rev" >&2
    exit 1
fi
mkdir rt
cp dsdt.aml rt/
iasl -d rt/dsdt.aml
grep -q 'Name (SS3, One)' rt/dsdt.dsl || { echo "error: round-trip check failed" >&2; exit 1; }
if [ "${TP_ECTP_PR0:-1}" = "1" ]; then
    grep -q 'PowerResource (TPPR' rt/dsdt.dsl || { echo "error: round-trip lost the touchpad power resource" >&2; exit 1; }
    # the re-disassembled source prints the package count as 0x01, not One,
    # and may reflow the braces - so check _PR0 and its TPPR reference loosely
    if ! grep -A3 'Name (_PR0' rt/dsdt.dsl | grep -q 'TPPR'; then
        echo "error: round-trip lost TPD0._PR0" >&2
        exit 1
    fi
fi

# 6. install into the image tree
mkdir -p "$override_dir" "$check_dir"
cp dsdt.aml "$override_dir/DSDT.aml"
cp dsdt.dat "$check_dir/DSDT.orig.aml"
cp dsdt.dsl "$script_dir/DSDT.patched.dsl"

echo
echo "wrote:"
echo "  ntb-rootfs/etc/dracut.conf.d/yoga7i-acpi/DSDT.aml        (patched table, packed into the initramfs by dracut)"
echo "  ntb-rootfs/usr/share/dsdt-override/DSDT.orig.aml         (unpatched firmware table, used by dsdt-override-check.service)"
echo "  scripts/dsdt/DSDT.patched.dsl                (patched source, for reference)"
sha256sum "$override_dir/DSDT.aml" "$check_dir/DSDT.orig.aml"
