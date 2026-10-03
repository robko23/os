#!/bin/bash
# Patch the Yoga 7i firmware DSDT to advertise S3 (deep) sleep:
#   Name (SS3, Zero) -> Name (SS3, One)
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
override_dir="$repo_root/rootfs/usr/lib/acpi-override"
check_dir="$repo_root/rootfs/usr/share/dsdt-override"
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

# 3. bump the OEM revision so the override is applied
oldrev=$(grep -m1 -oP '^DefinitionBlock.*\K0x[0-9A-Fa-f]+(?=\))' dsdt.dsl)
[ -n "$oldrev" ] || { echo "error: could not read the OEM revision from the DefinitionBlock" >&2; exit 1; }
expected_rev=$((oldrev + 1))
newrev=$(printf '0x%08X' "$expected_rev")
sed -i "/^DefinitionBlock /s/$oldrev/$newrev/" dsdt.dsl

grep -q 'Name (SS3, One)' dsdt.dsl
grep -q "^DefinitionBlock.*$newrev" dsdt.dsl

# 4. recompile and verify: round-trip + OEM revision in the AML header
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

# 5. install into the image tree
mkdir -p "$override_dir" "$check_dir"
cp dsdt.aml "$override_dir/DSDT.aml"
cp dsdt.dat "$check_dir/DSDT.orig.aml"
cp dsdt.dsl "$script_dir/DSDT.patched.dsl"

echo
echo "wrote:"
echo "  rootfs/usr/lib/acpi-override/DSDT.aml        (patched table, packed into the initramfs by dracut)"
echo "  rootfs/usr/share/dsdt-override/DSDT.orig.aml (unpatched firmware table, used by dsdt-override-check.service)"
echo "  scripts/dsdt/DSDT.patched.dsl                (patched source, for reference)"
sha256sum "$override_dir/DSDT.aml" "$check_dir/DSDT.orig.aml"