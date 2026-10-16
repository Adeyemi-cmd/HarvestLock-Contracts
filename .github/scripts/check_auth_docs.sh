#!/usr/bin/env bash
# Enforces that every public contract method's doc comment names its required
# auth party. Manual audit: #66. Automated by CI: #127.
#
# Each `pub fn` in contracts/escrow/src/lib.rs must have a `///` doc block
# directly above it whose text matches (case-insensitive) at least one of:
#   auth | permissionless | gated | consent | signature | attest
#
# Rationale: bare party names ("buyer", "cooperative") are NOT enough — the
# doc must say something about authorization itself, e.g.:
#   - "Requires buyer auth" / "Requires cooperative auth"
#   - "Requires the warehouse operator's attestation"
#   - "Requires both the buyer's and the cooperative's auth"
#   - "Requires unanimous three-party consent"
#   - "Permissionless — no auth required"
#   - "No auth required — read-only view"
#   - "Deliberately not auth-gated: ..."
#
# This catches both missing docs and docs that describe payouts/recipients
# without ever stating who must authorize the call (e.g. `settle` naming
# "cooperative" and "buyer" as payees but never saying the call itself is
# permissionless).
set -euo pipefail

LIB="contracts/escrow/src/lib.rs"

if [[ ! -f "$LIB" ]]; then
  echo "error: $LIB not found (run from repo root)" >&2
  exit 1
fi

python3 - "$LIB" <<'PY'
import re
import sys

lib_path = sys.argv[1]
lines = open(lib_path).read().splitlines()

# Auth vocabulary: must say something about authorization, not just name a party.
pattern = re.compile(r"auth|permissionless|gated|consent|signature|attest", re.I)

failures = []
checked = 0
for i, line in enumerate(lines):
    m = re.match(r"^\s*pub\s+fn\s+([A-Za-z0-9_]+)\s*\(", line)
    if not m:
        continue
    name = m.group(1)
    # Collect contiguous `///` lines directly above, skipping nothing:
    # the doc block ends at the first non-`///` line (attributes like
    # `#[...]` between docs and fn would break contiguity and count as
    # missing docs — none exist on pub fns today, and that strictness is
    # intentional).
    docs = []
    k = i - 1
    while k >= 0 and lines[k].strip().startswith("///"):
        docs.append(lines[k])
        k -= 1
    docs.reverse()
    checked += 1
    doc_text = "\n".join(docs)
    if not docs:
        failures.append((name, i + 1, "missing doc comment (no `///` block directly above `pub fn`)"))
    elif not pattern.search(doc_text):
        failures.append((
            name, i + 1,
            "doc comment does not name its required auth party "
            "(must match, case-insensitive: auth|permissionless|gated|consent|signature|attest)",
        ))

if failures:
    print(f"error: {len(failures)} of {checked} public method(s) fail the auth-doc check:")
    for name, lineno, reason in failures:
        print(f"  - {name} (line {lineno}): {reason}")
    print("hint: add one explicit sentence, e.g. `Requires buyer auth.`,")
    print("      `Requires cooperative auth.`, `Requires the warehouse")
    print("      operator's attestation.`, `Permissionless — no auth")
    print("      required.`, or `No auth required — read-only view.`")
    sys.exit(1)

print(f"ok: all {checked} public method doc comments name their required auth party")
PY
