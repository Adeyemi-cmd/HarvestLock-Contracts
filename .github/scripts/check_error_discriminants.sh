#!/usr/bin/env bash
# Guards the `#[contracterror] Error` enum's numbering stability.
# Manual audit: #84. Automated by CI: #126.
#
# Fails if any new variant is inserted at a non-terminal discriminant value,
# i.e.:
#   1. any variant lacks an explicit `= N` discriminant,
#   2. discriminants are not exactly 1..N in source order (gap, duplicate,
#      or out-of-order numbering), or
#   3. the pinned snapshot's prefix does not exactly match the enum's first
#      K variants (a renumber or non-terminal insert, even if sequentially
#      renumbered, changes an existing variant's meaning for old clients).
#
# When adding a new error: append it to the enum with the next discriminant
# AND append the same line to contracts/escrow/error_discriminants.snapshot.
set -euo pipefail

LIB="contracts/escrow/src/lib.rs"
SNAP="contracts/escrow/error_discriminants.snapshot"

if [[ ! -f "$LIB" ]]; then
  echo "error: $LIB not found (run from repo root)" >&2
  exit 1
fi
if [[ ! -f "$SNAP" ]]; then
  echo "error: $SNAP not found" >&2
  exit 1
fi

python3 - "$LIB" "$SNAP" <<'PY'
import re
import sys

lib_path, snap_path = sys.argv[1], sys.argv[2]
text = open(lib_path).read()

m = re.search(r"pub\s+enum\s+Error\s*\{(.*?)\n\}", text, re.S)
if not m:
    print("error: could not locate `pub enum Error` in " + lib_path)
    sys.exit(1)
block = m.group(1)

current = []          # [(variant, discriminant)]
variant_lines = 0    # every variant definition, with or without `= N`
missing = []         # variants without an explicit discriminant
for raw in block.splitlines():
    line = raw.strip()
    if not line or line.startswith("///") or line.startswith("//") or line.startswith("#") or line.startswith("["):
        continue
    variant_lines += 1
    em = re.match(r"^([A-Za-z][A-Za-z0-9_]*)\s*=\s*([0-9]+)\s*,?\s*$", line)
    if em:
        current.append((em.group(1), int(em.group(2))))
    else:
        # A variant definition that did not match `Name = N` — most likely
        # a bare `Name,` with no explicit discriminant.
        vm = re.match(r"^([A-Za-z][A-Za-z0-9_]*)\s*,?\s*$", line)
        if vm:
            missing.append(vm.group(1))
        else:
            print(f"error: unparseable line in Error enum: {raw!r}")
            print("hint: keep each variant on its own `Variant = N,` line")
            sys.exit(1)

if missing:
    print("error: these Error variants lack an explicit `= N` discriminant:")
    for v in missing:
        print(f"  - {v}")
    print("hint: every variant must pin its number explicitly so a later")
    print("      insert cannot silently shift existing discriminants")
    sys.exit(1)

if not current:
    print("error: no `Variant = N` entries found in Error enum")
    sys.exit(1)

# 1..N in source order, no gaps/dups/reorders.
for i, (name, disc) in enumerate(current, start=1):
    if disc != i:
        print(f"error: Error::{name} has discriminant {disc}, expected {i}")
        print("hint: discriminants must be exactly 1..N in source order;")
        print("      append new variants at the end with max + 1, never")
        print("      insert in the middle (that renumbers every variant")
        print("      after the insertion point for already-deployed clients)")
        sys.exit(1)

# Append-only check against the pinned snapshot.
snap = []
for raw in open(snap_path):
    line = raw.strip()
    if not line or line.startswith("#"):
        continue
    sm = re.match(r"^([A-Za-z][A-Za-z0-9_]*)\s*=\s*([0-9]+)\s*$", line)
    if not sm:
        print(f"error: unparseable line in {snap_path}: {raw!r}")
        sys.exit(1)
    snap.append((sm.group(1), int(sm.group(2))))

if len(current) < len(snap):
    print(f"error: Error enum has {len(current)} variants but snapshot pins {len(snap)}")
    print("hint: variants must never be removed or merged; if one was")
    print("      deleted, restore it (or keep it deprecated) so old error")
    print("      codes keep their meaning")
    sys.exit(1)

for i, ((s_name, s_disc), (c_name, c_disc)) in enumerate(zip(snap, current)):
    if s_name != c_name or s_disc != c_disc:
        print(f"error: non-terminal change at position {i + 1}: snapshot pins")
        print(f"       `{s_name} = {s_disc}` but source has `{c_name} = {c_disc}`")
        print("hint: existing variants must never be renumbered, reordered, or")
        print("      have a new variant inserted before them; append new")
        print("      variants at the end with the next discriminant and extend")
        print("      the snapshot with the same appended line(s) in the same PR")
        sys.exit(1)

added = len(current) - len(snap)
if added:
    print(f"ok: Error discriminants 1..{len(current)} sequential; {added} new terminal variant(s):")
    for name, disc in current[len(snap):]:
        print(f"  + {name} = {disc}")
    print(f"hint: ensure {snap_path} was extended with the same appended line(s)")
else:
    print(f"ok: Error discriminants 1..{len(current)} sequential, snapshot prefix matches")
PY
